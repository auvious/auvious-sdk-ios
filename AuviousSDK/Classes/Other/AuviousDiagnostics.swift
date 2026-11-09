//
//  AuviousDiagnostics.swift
//  AuviousSDK
//

import Foundation
import UIKit
import os
import Sentry

/// What the SDK sends to Sentry. Same levels as the Android SDK; turn Sentry off with `AuviousErrorReporting.disabled`.
public enum AuviousLogLevel {
    /// Crashes in the SDK, with the SDK's error logs as breadcrumbs. The default
    case minimal
    /// Crashes in the SDK, the SDK's error logs and failures as events, all its logs as breadcrumbs (troubleshooting)
    case full
}

/// Where the SDK sends its Sentry reports. Same choices as the Android SDK.
public enum AuviousErrorReporting: Equatable {
    /// Auvious' Sentry, the default
    case auvious
    /// Your own Sentry project
    case custom(dsn: String)
    /// No reports leave the device
    case disabled
}

/// How much the SDK writes to the console (unified logging). Each level includes the ones above it.
public enum AuviousConsoleLogLevel: Int, Comparable {
    /// No SDK logs
    case none = 0
    case error
    /// The default
    case warning
    case info
    /// Everything
    case debug

    public static func < (lhs: AuviousConsoleLogLevel, rhs: AuviousConsoleLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Error reporting and logging of the SDK. Set these before using the SDK, e.g. in `application(_:didFinishLaunchingWithOptions:)`.
///
/// When the app has not started Sentry itself, the SDK starts it to catch crashes, and reports only the crashes in the
/// SDK's code (AuviousSDK, WebRTC), not the rest of the app's. If the app uses Sentry, start it before using the SDK:
/// the SDK then leaves it alone, reports its errors through a client of its own and catches no crashes.
public enum AuviousDiagnostics {

    /// What the SDK reports to Sentry. Default `.minimal`.
    public static var logLevel: AuviousLogLevel {
        get { locked { _logLevel } }
        set { locked { _logLevel = newValue; stopReporting() } }
    }

    /// Where Sentry reports go. Default `.auvious`.
    public static var errorReporting: AuviousErrorReporting {
        get { locked { _errorReporting } }
        set { locked { _errorReporting = newValue; stopReporting() } }
    }

    /// SDK console logs at this level or above are written. Default `.warning`.
    public static var consoleLogLevel: AuviousConsoleLogLevel {
        get { locked { _consoleLogLevel } }
        set { locked { _consoleLogLevel = newValue } }
    }

    // MARK: Internal

    private static let auviousDSN = "https://74765e10688d4f828efd5bc5320c607c@sentry.auvious.com/9"

    /// Tag of the events the SDK captures itself, so the crash filter keeps them
    private static let sdkEventTag = "auvious.sdk_event"

    /// Binaries and symbols of the SDK's code: a crash is reported only when one of its frames is in them
    private static let sdkCodeMarkers = ["AuviousSDK", "WebRTC"]

    /// Where reports go
    private enum Reporter {
        /// Not decided yet
        case notStarted
        case off
        /// The SDK started SentrySDK: crashes and reports go through it
        case global
        /// The app started SentrySDK: reports go through the SDK's own client, no crashes
        case hub(SentryHub)
    }

    private static let lock = NSLock()
    private static var _logLevel: AuviousLogLevel = .minimal
    private static var _errorReporting: AuviousErrorReporting = .auvious
    private static var _consoleLogLevel: AuviousConsoleLogLevel = .warning
    private static var reporter: Reporter = .notStarted

    /// The SDK version with its pre-release part (1.5.0-beta.3)
    static var sdkVersion: String {
        let info = Bundle(for: AuviousConferenceSDK.self).infoDictionary
        return info?["AuviousSDKVersion"] as? String ?? info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Starts reporting, crashes included, if it hasn't started yet. Called when the SDK is first used.
    static func start() {
        _ = currentReporter()
    }

    static func isConsoleEnabled(_ type: OSLogType) -> Bool {
        return consoleLevel(of: type) <= consoleLogLevel
    }

    /// Whether an SDK log line of this type and category goes to Sentry
    static func wantsRecord(_ type: OSLogType, category: String) -> Bool {
        guard errorReporting != .disabled else { return false }
        switch logLevel {
        case .minimal: return type == .error || type == .fault
        //API and login debug lines carry tokens and whole responses
        case .full: return !(type == .debug && (category == "API" || category == "Authentication"))
        }
    }

    /// An SDK log line: a breadcrumb (errors only, all with `.full`), and an event for errors with `.full`
    static func record(_ message: String, category: String, type: OSLogType) {
        guard wantsRecord(type, category: category) else { return }
        let level = logLevel
        let isError = type == .error || type == .fault

        let crumb = Breadcrumb(level: sentryLevel(of: type), category: category)
        crumb.message = message
        addBreadcrumb(crumb)

        if level == .full && isError {
            let event = Event(level: .error)
            event.message = SentryMessage(formatted: message)
            event.tags = ["category": category]
            capture(event: event)
        }
    }

    /// Breadcrumbs from the SDK's code; with `.minimal` only errors are kept
    static func addBreadcrumb(_ crumb: Breadcrumb) {
        if logLevel == .minimal && crumb.level != .error && crumb.level != .fatal { return }
        switch currentReporter() {
        case .global: SentrySDK.addBreadcrumb(crumb)
        case .hub(let hub): hub.add(crumb)
        case .off, .notStarted: break
        }
    }

    /// Error events are sent with `.full` only, like the Android SDK
    static func capture(error: Error) {
        guard logLevel == .full else { return }
        switch currentReporter() {
        case .global: SentrySDK.capture(error: error) { $0.setTag(value: "true", key: sdkEventTag) }
        case .hub(let hub): hub.capture(error: error)
        case .off, .notStarted: break
        }
    }

    /// Error events are sent with `.full` only, like the Android SDK
    static func capture(event: Event) {
        guard logLevel == .full else { return }
        switch currentReporter() {
        case .global:
            event.tags = (event.tags ?? [:]).merging([sdkEventTag: "true"]) { $1 }
            SentrySDK.capture(event: event)
        case .hub(let hub): hub.capture(event: event)
        case .off, .notStarted: break
        }
    }

    private static func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func consoleLevel(of type: OSLogType) -> AuviousConsoleLogLevel {
        switch type {
        case .debug: return .debug
        case .error, .fault: return .error
        default: return .info
        }
    }

    private static func sentryLevel(of type: OSLogType) -> SentryLevel {
        switch type {
        case .debug: return .debug
        case .error: return .error
        case .fault: return .fatal
        default: return .info
        }
    }

    /// Called with the lock held. The next report decides again where reports go.
    private static func stopReporting() {
        switch reporter {
        case .global: SentrySDK.close()
        case .hub(let hub): hub.close()
        case .off, .notStarted: break
        }
        reporter = .notStarted
    }

    private static func currentReporter() -> Reporter {
        lock.lock()
        defer { lock.unlock() }
        if case .notStarted = reporter {
            reporter = makeReporter()
        }
        return reporter
    }

    /// Called with the lock held. No sdkLog in here: it would take the lock again.
    private static func makeReporter() -> Reporter {
        let dsn: String
        switch _errorReporting {
        case .auvious: dsn = auviousDSN
        case .custom(let customDSN): dsn = customDSN.trimmingCharacters(in: .whitespacesAndNewlines)
        case .disabled: return .off
        }
        guard !dsn.isEmpty else { return .off }

        //The app's Sentry stays as it is
        if SentrySDK.isEnabled {
            return makeHub(dsn: dsn).map { .hub($0) } ?? .off
        }

        SentrySDK.start { options in
            configure(options, dsn: dsn)
            options.beforeSend = { event in isSdkEvent(event) ? event : nil }
            //Only crashes: nothing about the rest of the app
            options.enableAutoSessionTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableAppHangTracking = false
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableNetworkTracking = false
            options.enableCaptureFailedRequests = false
            options.enableAutoPerformanceTracing = false
            options.enableUIViewControllerTracing = false
            options.enableUserInteractionTracing = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableSwizzling = false
            options.enableMetricKit = false
            options.tracesSampleRate = 0
        }
        SentrySDK.configureScope { applyTags(to: $0) }
        return .global
    }

    private static func makeHub(dsn: String) -> SentryHub? {
        let options = Options()
        configure(options, dsn: dsn)
        guard let client = SentryClient(options: options) else {
            os_log("Error reporting off, the Sentry client could not start", log: Log.conferenceSDK, type: .error)
            return nil
        }
        //A client of its own gets none of SentrySDK's device context, so the basics go in as tags
        let scope = Scope()
        applyTags(to: scope)
        return SentryHub(client: client, andScope: scope)
    }

    private static func configure(_ options: Options, dsn: String) {
        options.dsn = dsn
        #if DEBUG
        options.environment = "debug"
        #else
        options.environment = "production"
        #endif
        options.releaseName = "auvious-sdk@\(sdkVersion)"
        options.maxBreadcrumbs = 100
    }

    private static func applyTags(to scope: Scope) {
        let app = Bundle.main
        scope.setTag(value: sdkVersion, key: "auvious_sdk_version")
        scope.setTag(value: app.bundleIdentifier ?? "unknown", key: "app_bundle_id")
        scope.setTag(value: app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown", key: "app_version")
        scope.setTag(value: Utilities.getDeviceModel(), key: "device_model")
        scope.setTag(value: UIDevice.current.systemVersion, key: "os_version")
    }

    /// True for events the SDK captured itself, and for crashes with a frame in the SDK's code
    static func isSdkEvent(_ event: Event) -> Bool {
        if event.tags?[sdkEventTag] != nil { return true }
        let crashedThreadFrames = (event.threads ?? []).filter { $0.crashed?.boolValue == true }.compactMap { $0.stacktrace?.frames }
        let exceptionFrames = (event.exceptions ?? []).compactMap { $0.stacktrace?.frames }
        return (crashedThreadFrames + exceptionFrames).joined().contains { frame in
            let names = [frame.package, frame.function].compactMap { $0 }
            return names.contains { name in sdkCodeMarkers.contains { name.contains($0) } }
        }
    }
}

/// `os_log` that follows `AuviousDiagnostics.consoleLogLevel`, and records the line for Sentry by `AuviousDiagnostics.logLevel`.
/// Same arguments as `os_log`, up to 5 format arguments.
internal func sdkLog(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ args: CVarArg...) {
    if AuviousDiagnostics.isConsoleEnabled(type) {
        switch args.count {
        case 0: os_log(message, log: log, type: type)
        case 1: os_log(message, log: log, type: type, args[0])
        case 2: os_log(message, log: log, type: type, args[0], args[1])
        case 3: os_log(message, log: log, type: type, args[0], args[1], args[2])
        case 4: os_log(message, log: log, type: type, args[0], args[1], args[2], args[3])
        default: os_log(message, log: log, type: type, args[0], args[1], args[2], args[3], args[4])
        }
    }
    let category = log.category
    guard AuviousDiagnostics.wantsRecord(type, category: category) else { return }
    //Sentry gets the line formatted: drop os_log's privacy markers, String(format:) doesn't know them
    let format = "\(message)".replacingOccurrences(of: "%{public}", with: "%").replacingOccurrences(of: "%{private}", with: "%")
    AuviousDiagnostics.record(String(format: format, arguments: args), category: category, type: type)
}

private extension OSLog {
    /// The category given to `Log`'s loggers, for the breadcrumbs
    var category: String {
        switch self {
        case Log.api: return "API"
        case Log.mqtt: return "MQTT"
        case Log.rtc: return "RTC"
        case Log.auth: return "Authentication"
        case Log.conferenceSDK: return "Conference SDK"
        case Log.conferenceUI, Log.callUI: return "Conference UI"
        case Log.conferenceApp: return "Conference App"
        default: return "AuviousSDK"
        }
    }
}
