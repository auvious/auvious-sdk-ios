//
//  AuviousConferenceVCNew.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 24/9/20.
//

import UIKit
import os

//Defines the possible UI modes
public enum ScreenMode {
    case fullScreen, pip, expandedPip
    
    var width: CGFloat {
        switch self {
        case .fullScreen:
            return UIScreen.main.bounds.width
        case .pip:
            return 100
        case .expandedPip:
            return 130
        }
    }
    
    var height: CGFloat {
        switch self {
        case .fullScreen:
            return UIScreen.main.bounds.height
        case .pip:
            return 160
        case .expandedPip:
            return 208
        }
    }
}

public class AuviousConferenceVCNew: UIViewController, AuviousSDKConferenceDelegate {
    
    //Pip gestures
    internal var panGesture: UIPanGestureRecognizer!
    internal var tapGesture: UITapGestureRecognizer!
    internal var doubleTapGesture: UITapGestureRecognizer!
    
    //Pip buttons
    internal var pipBottomBar: UIStackView = UIStackView(frame: .zero)
    internal var pipMuteButton: PIPButton = PIPButton(type: .micEnabled)
    internal var pipMaximiseButton: UIButton = UIButton(frame: .zero)
    internal var pipStopShareButton: UIButton = UIButton(frame: .zero)
    
    //The current state of our UI (backing store accessible from extensions)
    internal var _screenMode: ScreenMode = .fullScreen

    internal var screenMode: ScreenMode {
        get { _screenMode }
        set {
            _screenMode = newValue
            updateGestureState(for: newValue)
            createConstraints()
            refreshCobrowseChrome()
        }
    }

    //In-call co-browse: the running session, the mode to go back to when it ends, and the agent's
    //sketch metadata received before it started
    internal var cobrowseSession: CobrowseSessionController?
    internal var screenModeBeforeCobrowse: ScreenMode?
    internal var pendingCobrowseMetadata: [ConferenceMetadataUpdatedEvent] = []
    //Where the call's view lives in the host app, while it is moved to the co-browse overlay
    internal weak var callHostSuperview: UIView?
    internal var callHostIndex: Int?
    //The call's view is moving between the host app and the co-browse overlay: UIKit may send it a
    //disappear/appear cycle for that, which must not end the call
    internal var isMovingCallForCobrowse = false
    //The host app was told co-browse started (onCobrowseStarted)
    internal var didNotifyCobrowseStarted = false
    //"<Agent> can't see the call", while sharing with the call full screen
    internal var callHiddenChip: UIView?

    //AR pointer: the session, where it is drawn (a call tile or the screen share overlay) and its controls
    internal let arPointer = ArPointerSession()
    internal var arPointerTile: StreamView?
    internal var arPointerTileSurface: AnnotationSurfaceView?
    internal var arPointerDock: CobrowseDockView?
    internal var arPointerFreezeBadge: UIView?
    internal var arPointerTool: SketchTool = .laser
    internal var isArPointerAnnotating = false
    internal var screenAnnotationWindow: CobrowseOverlayWindow?
    internal var screenAnnotationOverlay: ScreenAnnotationOverlayViewController?
    //Holds the other tiles while one tile is in focus (agent screen share or AR pointer target)
    internal let focusStrip = UIScrollView()
    //The strip's content: the tiles and their guide live here, since a guide owned by the scroll view itself
    //moves with the scroll offset and makes the row scroll the opposite way
    internal let focusStripContent = UIView()
    internal let focusGroupGuide = UILayoutGuide()
    //Row and column guides of the grid layout
    internal var gridGuides: [UILayoutGuide] = []
    
    //UI components
    internal var clientConfiguration = AuviousConferenceConfiguration()
    
    //Network indicator view
    private let networkIndicator = NetworkIndicatorView()
    private let networkIndicatorDetails = NetworkDetailsNotificationView(with: nil)
    private var hideNetworkDetailsBlock: DispatchWorkItem?
    private var lastKnownNetworkStatistics: NetworkStatistics? = nil
    private let notification = DismissableNotificationView(title: "", subtitle: "")
    private var hideNotificationBlock: DispatchWorkItem?
    private let recorderIndicator = UIImageView()
    
    //Container of all stream views
    internal var streamContainerView: UIView!
    //Our local stream view
    internal var localView: StreamView = StreamView()
    //List of all remote stream views, excluding the share screen
    internal var remoteViews: [StreamView] = []
    //Share screen stream view
    internal var shareScreenContainerView: StreamView?
    //Bottom button bar
    internal var buttonContainerView: ConferenceButtonBar!
    //Button for stopping the screen share when in PIP mode
    internal var stopScreenSharingButton: LargeButton = LargeButton(title: "Stop sharing", iconName: "stopSharing")
    
    //Overlay view for hold mode
    private var blurredOverlayView: ConferenceHoldView?
    
    //UI constraints
    private var existingConstraints: [NSLayoutConstraint] = []
    private var statusCapsuleConstraints: [NSLayoutConstraint] = []

    //Top left status capsule: network, recording and the remote participant's mute, each in a fixed slot
    private let statusCapsule = UIVisualEffectView()
    private let statusStack = UIStackView()
    //The agent's mute, only in PiP (in full screen every participant's video shows its own badge)
    private let remoteMutedIcon = UIImageView()
    private var isRecording = false
    //The capsule's glass or blur, kept so it can materialize when the capsule appears
    private var statusCapsuleEffect: UIVisualEffect?
    private var isStatusCapsuleRevealed = false

    //Our tile fades and scales in once, after the first layout places it
    private var hasShownLocalView = false

    //Remote tiles just added, faded and scaled in by the next layout animation
    private var appearingRemoteViews: [StreamView] = []

    //Banner shown over the host app while the call is in PiP
    private weak var windowNotification: DismissableNotificationView?
    internal let viewPadding: CGFloat = 10
    internal let viewSize: CGFloat = 80
    private var networkIndicatorDetailsTop: NSLayoutConstraint!
    private var notificationTop: NSLayoutConstraint!
    internal let maximumRemoteStreamsRendered = 7
    
    //Triggers portrait/landscape rendering of agent remote view
    //Works ONLY on 1-1 calls without screensharing
    private var agentVideoPortraitMode: Bool = false {
        didSet {
            createConstraints()
        }
    }

    //Endpoints whose video has portraitMode metadata: their tiles always fill, taps don't switch them to fit
    private var portraitModeEndpoints: Set<String> = []

    //Triggers network indicator positioning
    //Works ONLY on 1-1 calls with agentVideoPortraitMode and without screensharing
    private var isAgentMuted: Bool = false {
        didSet {
            createConstraints()
        }
    }
    
    //UI feedback
    private let selectionFeedbackGenerator = UIImpactFeedbackGenerator()
    
    //Service dispatch group for distinguishing remote streams
    private let serviceGroup = DispatchGroup()
    
    //Configuration
    private var videoViewBackgroundColor: UIColor!
    
    //Conference properties
    private var username: String = ""
    private var password: String = ""
    private var conference: String = ""
    private var participantName: String?
    private var baseEndpoint: String = ""
    private var mqttEndpoint: String = ""
    private var clientId: String = ""
    private var params: [String: String] = [:]
    private var configuredStreamType: StreamType = .unknown
    // Tracks the user's preferred audio route so it survives backgrounding.
    // Updated both from the speaker button and from AVAudioSession route-change
    // notifications (e.g. Bluetooth removed → system switches to speaker without
    // touching the button).
    private var prefersSpeaker: Bool = false

    //Control flags
    private var performedInitialValidations: Bool = false
    internal var conferenceJoined: Bool = false
    private var shareScreenFullScreen: Bool = false
    private var initialStreamsConnected: Bool = false
    private var hasAppliedInitialAudioRoute: Bool = false
    //State the options menu reflects
    private var isAgentSharingScreen = false
    internal var isConferenceOnHold = false
    
    //Delegate
    internal weak var delegate: AuviousSimpleConferenceDelegate?
    
    //Our local stream id
    internal var localScreenShareStreamId: String?
    internal var localStreamId: String?
    private var localStreamType: StreamType?
    //The conference we're in
    internal var currentConference: ConferenceSimpleView!
    //Current conference participants
    private var conferenceParticipants: Int = 0 {
        didSet {
            setScreenTitle()
        }
    }
    
    //Pip resizing
    var currentCorner: Corner = .bottomRight
    var currentKeyboardFrame: CGRect?
    
    //Public constructor
    public init(configuration: AuviousConferenceConfiguration, delegate: AuviousSimpleConferenceDelegate) {
        self.clientConfiguration = configuration
        
        self.clientId = configuration.clientId
        self.baseEndpoint = configuration.baseEndpoint
        self.mqttEndpoint = configuration.mqttEndpoint
        self.username = configuration.username
        self.password = configuration.password
        self.conference = configuration.conference
        self.participantName = configuration.participantName
        self.delegate = delegate
        
        self.params["username"] = configuration.username
        self.params["password"] = configuration.password
        self.params["grant_type"] = configuration.grantType
        
        switch configuration.callMode {
        case .audio:
            configuredStreamType = .mic
        case .video:
            configuredStreamType = .cam
        case .audioVideo:
            configuredStreamType = .micAndCam
        }
        
        super.init(nibName: nil, bundle: Bundle(for: AuviousConferenceVC.self))
        sdkLog("UI Conference component: initialised", log: Log.conferenceUI, type: .debug)
    }
    
    //Public constructor
    public init(clientId: String, params: [String: String], baseEndpoint: String, mqttEndpoint: String, delegate: AuviousSimpleConferenceDelegate, callMode: AuviousCallMode) {
        self.params = params
        self.clientId = clientId
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
        self.delegate = delegate
        
        if let username = params["username"] {
            self.username = username
        }
        
        if let password = params["password"] {
            self.password = password
        }
        
        if let conference = params["conference"] {
            self.conference = conference
        }
        
        switch callMode {
        case .audio:
            configuredStreamType = .mic
        case .video:
            configuredStreamType = .cam
        case .audioVideo:
            configuredStreamType = .micAndCam
        }
        
        super.init(nibName: nil, bundle: Bundle(for: AuviousConferenceVC.self))
        
        sdkLog("UI Conference component: initialised", log: Log.conferenceUI, type: .debug)
    }
    
    //Public constructor
    public init(clientId: String, username: String, password: String, conference: String, baseEndpoint: String, mqttEndpoint: String, delegate: AuviousSimpleConferenceDelegate, callMode: AuviousCallMode) {
        self.clientId = clientId
        self.username = username
        self.password = password
        self.conference = conference
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
        self.delegate = delegate
        
        switch callMode {
        case .audio:
            configuredStreamType = .mic
        case .video:
            configuredStreamType = .cam
        case .audioVideo:
            configuredStreamType = .micAndCam
        }
        
        super.init(nibName: nil, bundle: Bundle(for: AuviousConferenceVC.self))
        
        sdkLog("UI Conference component: initialised", log: Log.conferenceUI, type: .debug)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: -
    // MARK: VC Lifecycle
    // MARK: -
        
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        videoViewBackgroundColor = clientConfiguration.conferenceBackgroundColor
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.audioRouteChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidTakeScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        
        view.backgroundColor = clientConfiguration.conferenceBackgroundColor
        
        //Setup the container of all stream views
        streamContainerView = UIView(frame: .zero)
        streamContainerView.translatesAutoresizingMaskIntoConstraints = false
        streamContainerView.backgroundColor = .clear
        view.addSubview(streamContainerView)
        streamContainerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
        streamContainerView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        streamContainerView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0).isActive = true
        streamContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        
        //Status capsule (top left): dark glass holding the network indicator, the recording dot and the
        //remote participant's mute state. Items only appear or disappear inside it, so nothing else moves.
        statusCapsule.translatesAutoresizingMaskIntoConstraints = false
        statusCapsule.overrideUserInterfaceStyle = .dark
        statusCapsule.clipsToBounds = true
        statusCapsule.layer.zPosition = 2000
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = UIColor(white: 0.02, alpha: 0.5)
            statusCapsuleEffect = glass
            statusCapsule.cornerConfiguration = .capsule()
        } else {
            statusCapsuleEffect = UIBlurEffect(style: .systemThinMaterialDark)
        }
        //Hidden until someone joins, then it materializes (revealStatusCapsule())
        statusCapsule.isHidden = true
        view.addSubview(statusCapsule)

        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.isLayoutMarginsRelativeArrangement = true
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusCapsule.contentView.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.topAnchor.constraint(equalTo: statusCapsule.contentView.topAnchor),
            statusStack.bottomAnchor.constraint(equalTo: statusCapsule.contentView.bottomAnchor),
            statusStack.leadingAnchor.constraint(equalTo: statusCapsule.contentView.leadingAnchor),
            statusStack.trailingAnchor.constraint(equalTo: statusCapsule.contentView.trailingAnchor),
        ])

        //Network indicator (the capsule is its background now). As wide as its bars, so the gaps
        //between the items are even; a tap anywhere on the capsule but the dot opens its details.
        networkIndicator.backgroundColor = .clear
        networkIndicator.widthAnchor.constraint(equalToConstant: 16).isActive = true
        networkIndicator.heightAnchor.constraint(equalToConstant: 30).isActive = true
        statusStack.addArrangedSubview(networkIndicator)

        //Recorder indicator: the same red record symbol as the recording notification
        recorderIndicator.image = UIImage(systemName: "record.circle.fill")
        recorderIndicator.contentMode = .center
        recorderIndicator.isUserInteractionEnabled = true
        recorderIndicator.accessibilityLabel = NSLocalizedString("Recording", comment: "Notification")
        let recTapRecogniser = UITapGestureRecognizer(target: self, action: #selector(self.recorderIndicatorPressed))
        recorderIndicator.addGestureRecognizer(recTapRecogniser)
        statusStack.addArrangedSubview(recorderIndicator)

        let tapRecogniser = UITapGestureRecognizer(target: self, action: #selector(self.networkIndicatorPressed))
        tapRecogniser.require(toFail: recTapRecogniser)
        statusCapsule.addGestureRecognizer(tapRecogniser)


        //Agent muted (PiP only): the mute icon of the call buttons
        remoteMutedIcon.image = UIImage(podAssetName: "micDisabled")
        remoteMutedIcon.contentMode = .scaleAspectFit
        //Same size as PiP's resize icon (the default 17pt symbol)
        remoteMutedIcon.widthAnchor.constraint(equalToConstant: 17).isActive = true
        remoteMutedIcon.heightAnchor.constraint(equalToConstant: 17).isActive = true
        remoteMutedIcon.isAccessibilityElement = true
        remoteMutedIcon.accessibilityLabel = NSLocalizedString("Remote participant muted", comment: "Remote participant muted")
        statusStack.addArrangedSubview(remoteMutedIcon)
        //Position and contents managed in layoutStatusCapsule(); start with the right sizes and colors
        layoutStatusCapsule()
        
        //Network indicator details
        view.addSubview(networkIndicatorDetails)
        networkIndicatorDetails.layer.zPosition = 2100
        networkIndicatorDetails.alpha = 0
        networkIndicatorDetails.leadingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.leadingAnchor, constant: 10).isActive = true
        networkIndicatorDetails.trailingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true
        networkIndicatorDetails.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        networkIndicatorDetailsTop = networkIndicatorDetails.topAnchor.constraint(equalTo: view.saferAreaLayoutGuide.topAnchor, constant: -150)
        networkIndicatorDetailsTop.isActive = true
        networkIndicatorDetails.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.hideNetworkDetailsPressed)))
        view.bringSubviewToFront(networkIndicatorDetails)

        //Generic dismissable notification
        view.addSubview(notification)
        notification.layer.zPosition = 2101
        notification.alpha = 0
        notification.leadingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.leadingAnchor, constant: 10).isActive = true
        notification.trailingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true
        notification.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        notificationTop = notification.topAnchor.constraint(equalTo: view.saferAreaLayoutGuide.topAnchor, constant: -150)
        notificationTop.isActive = true
        notification.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.hideNotificationPressed)))
        view.bringSubviewToFront(notification)
        
        hideNotificationBlock = DispatchWorkItem {
            self.hideNotification()
        }
        
        //Setup a cancellable piece of code to hide the network details
        hideNetworkDetailsBlock = DispatchWorkItem {
            self.hideNetworkDetails()
        }
        //Setup feedback
        selectionFeedbackGenerator.prepare()
        
        //Setup notifications
        AuviousNotification.shared.presenter = self
        
        //Create local stream view
        localView.translatesAutoresizingMaskIntoConstraints = false
        localView.frame = .zero
        localView.layer.zPosition = 100
        //Outlined like the remote tiles, whatever it shows
        localView.videoBorder = (UIColor.white.withAlphaComponent(0.3), 1)
        //Our camera starts in a moment: a black tile, then the video fades in on its first frame
        localView.backgroundColor = .black
        localView.showsLoadingIndicator = false
        localView.alpha = 0
        localView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        //Reshape the tile to the camera's video once its size is known
        localView.onVideoShapeChange = { [weak self] in
            self?.createConstraints()
        }
        
        streamContainerView.addSubview(localView)
        
        //Button bar
        createButtonBar()
        
        //Buttons that don't fit go in the options button's menu
        setupOptionsMenu()
        
        //Setup screen sharing stop button
        stopScreenSharingButton.addTarget(self, action: #selector(stopScreenShareButtonPressed), for: .touchUpInside)
        stopScreenSharingButton.alpha = 0
        stopScreenSharingButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stopScreenSharingButton)
        stopScreenSharingButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor, constant: 0).isActive = true
        stopScreenSharingButton.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -20).isActive = true
        stopScreenSharingButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10).isActive = true
        stopScreenSharingButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true
        stopScreenSharingButton.heightAnchor.constraint(equalToConstant: 54).isActive = true
        
        //Setup PIP maximise button
        view.addSubview(pipMaximiseButton)
        pipMaximiseButton.alpha = 0
        pipMaximiseButton.setImage(UIImage(systemName: "arrow.down.left.and.arrow.up.right")?.withRenderingMode(.alwaysTemplate), for: .normal)
        pipMaximiseButton.tintColor = .white
        pipMaximiseButton.addTarget(self, action: #selector(self.maximisebuttonPressed(_:)), for: .touchUpInside)
        pipMaximiseButton.translatesAutoresizingMaskIntoConstraints = false
        //The PiP's own corner: its safe area can still carry the screen's top inset, which pushed the button down
        pipMaximiseButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4).isActive = true
        pipMaximiseButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 4).isActive = true
        pipMaximiseButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        pipMaximiseButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        //Setup PIP bottom bar
        pipBottomBar.alpha = 0
        pipBottomBar.translatesAutoresizingMaskIntoConstraints = false
        pipBottomBar.distribution = .equalSpacing
        pipBottomBar.alignment = .center
        pipBottomBar.spacing = 15
        pipBottomBar.axis = .horizontal
        view.addSubview(pipBottomBar)
        pipBottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        pipBottomBar.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0).isActive = true
        pipBottomBar.heightAnchor.constraint(equalToConstant:55).isActive = true
        
        //PIP stop share button
        pipStopShareButton.setImage(UIImage(podAssetName: "stopSharing")?.withRenderingMode(.alwaysTemplate), for: .normal)
        pipStopShareButton.tintColor = .white
        pipStopShareButton.addTarget(self, action: #selector(self.stopScreenShareButtonPressed(_:)), for: .touchUpInside)
        pipStopShareButton.translatesAutoresizingMaskIntoConstraints = false
        pipStopShareButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        pipBottomBar.addArrangedSubview(pipStopShareButton)
        
        //Setup PIP mute button
        let initialPIPMuteImageName: PIPButtonType = configuredStreamType == .cam ? .micDisabled : .micEnabled
        pipMuteButton.type = initialPIPMuteImageName
        pipMuteButton.addTarget(self, action: #selector(self.pipMicButtonPressed(_:)), for: .touchUpInside)
        pipMuteButton.translatesAutoresizingMaskIntoConstraints = false
        pipMuteButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        if clientConfiguration.microphoneAvailable {
            pipBottomBar.addArrangedSubview(pipMuteButton)
        }
    }

    @objc private func userDidTakeScreenshot() {
        AuviousConferenceSDK.sharedInstance.wasBackgroundedDueToScreenshot = true
    }
    
    //Shows the toast notification view
    internal func showNotification(with title: String, subtitle: String?, symbol: String? = nil, image: UIImage? = nil, tint: UIColor? = nil) {
        //PiP is too small for a banner: show it over the host app instead
        if screenMode != .fullScreen, let window = view.window {
            showWindowNotification(with: title, subtitle: subtitle, symbol: symbol, image: image, tint: tint, in: window)
            return
        }

        notification.updateUI(withTitle: title, subtitle: subtitle, symbol: symbol, image: image, tint: tint)
        
        UIView.animate(withDuration: 0.2, animations: {
            self.notification.alpha = 1
            self.notificationTop.constant = 10
            self.view.layoutIfNeeded()
        }, completion: { finished in
            if finished {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.hideNotification()
                }
            }
        })
    }
    
    /// The same notification banner, added to the window above the host app while the call is in PiP
    private func showWindowNotification(with title: String, subtitle: String?, symbol: String?, image: UIImage?, tint: UIColor?, in window: UIWindow) {
        if let previous = windowNotification {
            Self.dismissWindowNotification(previous)
        }

        let banner = DismissableNotificationView(title: title, subtitle: subtitle)
        banner.updateUI(withTitle: title, subtitle: subtitle, symbol: symbol, image: image, tint: tint)
        banner.alpha = 0
        banner.layer.zPosition = 2101
        window.addSubview(banner)

        let top = banner.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: -150)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            banner.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            banner.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            top,
        ])
        window.layoutIfNeeded()
        banner.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.hideWindowNotificationPressed)))
        windowNotification = banner

        UIView.animate(withDuration: 0.2) {
            banner.alpha = 1
            top.constant = 10
            window.layoutIfNeeded()
        }
        //Holds the banner itself, so it still goes away if the call ends meanwhile
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Self.dismissWindowNotification(banner)
        }
    }

    @objc private func hideWindowNotificationPressed() {
        if let banner = windowNotification {
            Self.dismissWindowNotification(banner)
        }
    }

    private static func dismissWindowNotification(_ banner: DismissableNotificationView) {
        guard banner.superview != nil else { return }
        UIView.animate(withDuration: 0.2, animations: {
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: -40)
        }, completion: { _ in
            banner.removeFromSuperview()
        })
    }

    //Hides the toast notification view
    @objc private func hideNotification() {
        UIView.animate(withDuration: 0.2, animations: {
            self.notification.alpha = 0
            self.notificationTop.constant = -150
            self.view.layoutIfNeeded()
        }, completion: { finished in
            self.notification.updateUI(withTitle: "", subtitle: "")
        })
    }
    
    //Cancels the scheduled dismissal of the toast view and hides it
    @objc private func hideNotificationPressed() {
        self.hideNotificationBlock?.cancel()
        hideNotification()
    }
    
    //Shows the toast notification view
    @objc private func showNetworkDetails() {
        UIView.animate(withDuration: 0.2, animations: {
            self.networkIndicatorDetails.alpha = 1
            self.networkIndicatorDetailsTop.constant = 10
            self.view.layoutIfNeeded()
        }, completion: { finished in
            if finished {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.hideNetworkDetails()
                }
            }
        })
    }
    
    //Hides the toast notification view
    @objc private func hideNetworkDetails() {
        UIView.animate(withDuration: 0.2, animations: {
            self.networkIndicatorDetails.alpha = 0
            self.networkIndicatorDetailsTop.constant = -150
            self.view.layoutIfNeeded()
        }, completion: { finished in
            self.networkIndicatorDetails.updateUI(with: self.lastKnownNetworkStatistics)
        })
    }
    
    //Updates the toast notification view with latest network data and displays the view
    @objc private func networkIndicatorPressed() {
        networkIndicatorDetails.updateUI(with: lastKnownNetworkStatistics)
        showNetworkDetails()
    }
    
    @objc private func recorderIndicatorPressed() {
        showNotification(
            with: NSLocalizedString("Recording", comment: "Notification"),
            subtitle: NSLocalizedString("Session is being recorded", comment: "Notification"),
            symbol: "record.circle.fill",
            tint: .systemRed
        )
    }

    //Cancels the scheduled dismissal of the toast view and hides it
    @objc private func hideNetworkDetailsPressed() {
        self.hideNetworkDetailsBlock?.cancel()
        hideNetworkDetails()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        //Layouts made before the view had a window took the screen's shape, not the window's
        //(iPad split view, Stage Manager), and no size change may follow to redo them
        createConstraints(animated: false)
        
        if !performedInitialValidations {
            //Check for permissions
            if !validateVideoPermissions() {
                sdkLog("No video permission, returning error", log: Log.conferenceUI, type: .debug)
                handleError(AuviousSDKError.videoPermissionIsDisabled)
                return
            }
            
            if !validateMicPermissions() {
                sdkLog("No audio permission, returning error", log: Log.conferenceUI, type: .debug)
                handleError(AuviousSDKError.audioPermissionIsDisabled)
                return
            }
            
            //Check credentials
            if username.isEmpty || clientId.isEmpty {
                sdkLog("Username/password/clientId empty, returning error", log: Log.conferenceUI, type: .debug)
                handleError(AuviousSDKError.missingSDKCredentials)
                return
            }
            
            //Check call target
//            if conference.isEmpty {
//                sdkLog("Conference is empty, returning error", log: Log.conferenceUI, type: .debug)
//                handleError(AuviousSDKError.missingCallTarget)
//                return
//            }
            
            performedInitialValidations = true
        }
            
        if performedInitialValidations && !conferenceJoined {
            AuviousConferenceSDK.sharedInstance.delegate = self
            listenForCobrowse()
            listenForArPointer()
            AuviousConferenceSDK.sharedInstance.configure(params: params, username: username, password: password, name: participantName, clientId: clientId, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
            AuviousConferenceSDK.sharedInstance.setUIConfiguration(config: clientConfiguration)
            sdkLog("Configured ConferenceSDK", log: Log.conferenceUI, type: .debug)
            
            AuviousConferenceSDK.sharedInstance.login(onLoginSuccess: {(userId, conferenceId) in
                sdkLog("Login success", log: Log.conferenceUI, type: .debug)
                
                if let conference = conferenceId {
                    self.conference = conference
                }
                
                AuviousConferenceSDK.sharedInstance.joinConference(conferenceId: self.conference, onSuccess: {(joinedConference) in
                    
                    if let jConference = joinedConference {
                        sdkLog("Joined conference with id %@", log: Log.conferenceUI, type: .debug, String(describing: jConference.id))
                        self.currentConference = jConference
                        self.conferenceJoined = true
                        self.arPointerConferenceJoined()
                        
                        //Handle portrait mode flag so we render the agent video appropriately
                        for p in jConference.participants {
                            for e in p.endpoints {
                                for s in e.streams {
                                    if s.portraitMode {
                                        self.agentVideoPortraitMode = true
                                        self.portraitModeEndpoints.insert(e.id)
                                        break
                                    }
                                }
                            }
                        }
                        
                        //Start connecting to any existing streams in our conference
                        self.handleExistingConferenceStreams()
                        self.startLocalStream()
                        
                        //Joined conference is on hold
                        if self.currentConference.onHold {
                            self.auviousSDK(conferenceOnHold: true)
                        }
                    } else {
                        sdkLog("Unable to join conference", log: Log.conferenceUI, type: .error)
                    }
                }, onFailure: {(error) in
                    self.handleError(error)
                })
                
            }, onLoginFailure: {(error) in
                self.handleError(error)
            })
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isLeavingCall else {
            sdkLog("viewDidDisappear while co-browsing, the call goes on", log: Log.conferenceUI, type: .debug)
            return
        }
        sdkLog("viewDidDisappear, leaving the call", log: Log.conferenceUI, type: .debug)
        endCobrowseWithCall(.customerEnded)

        AuviousConferenceSDK.sharedInstance.logout(onSuccess: {
        }, onFailure: {error in
        })
    }

    /// While co-browsing, UIKit also cycles the call's appearance when the call moves between the host app and the
    /// co-browse overlay, and when the host app changes screens for co-browse (onCobrowseStarted/Ended). Only the
    /// call really going away (dismissed, popped or removed from its superview) ends it then.
    private var isLeavingCall: Bool {
        guard cobrowseSession != nil || isMovingCallForCobrowse else { return true }
        return !isMovingCallForCobrowse && (isBeingDismissed || isMovingFromParent || view.superview == nil)
    }

    //When orientation changes we simply reevaluate our UI constraints
    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.createConstraints(animated: false)
        }, completion: { _ in
            //Again with the scene's final interface orientation, in case it changed after the animation started
            self.createConstraints(animated: false)
        })
    }
    
    // MARK: -
    // MARK: Helpers
    // MARK: -
    
    private func startLocalStream() {
        do {
            localStreamId = try AuviousConferenceSDK.sharedInstance.startPublishLocalStreamFlow(type: configuredStreamType)
        } catch let error {
            sdkLog("startPublishLocalStreamFlow error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
            handleError(error)
        }
    }
    
    //Swaps the local mic or cam stream for a micAndCam one, leaving any screen share stream published
    private func republishLocalStreamAsMicAndCam(replacing streamId: String) {
        do {
            try AuviousConferenceSDK.sharedInstance.startUnpublishLocalStreamFlow(streamId: streamId, streamType: localStreamType ?? configuredStreamType)
        } catch let error {
            sdkLog("startUnpublishLocalStreamFlow error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
        }
        configuredStreamType = .micAndCam
        startLocalStream()
    }
    
    //Initialises the RTC view stream flow for existing conference streams
    private func handleExistingConferenceStreams(){
        //Reset our flag, and start connecting to remote participants
        initialStreamsConnected = false
        var serviceGroupEntries = 0
        
        if !currentConference.participants.isEmpty {
            for user in currentConference.participants {
                for endpointStream in user.endpoints {
                    //Without a camera their tile shows now, with the user placeholder; the others' when their video arrives
                    if !endpointStream.streams.contains(where: { $0.type == .cam || $0.type == .micAndCam }) {
                        showJoinedParticipant(endpointId: endpointStream.id, endpointType: endpointStream.endpointType)
                    }
                    for stream in endpointStream.streams {
                        do {
                            if !initialStreamsConnected {
                                serviceGroup.enter()
                                serviceGroupEntries += 1
                            }
                            try AuviousConferenceSDK.sharedInstance.startRemoteStreamFlow(streamId: stream.id, endpointId: endpointStream.id, streamType: stream.type, remoteUserId: user.id)
                        } catch let error {
                            sdkLog("startRemoteStreamFlow error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
                            
                            if !initialStreamsConnected {
                                serviceGroup.leave()
                            }
                            
                            handleError(error)
                        }
                    }
                }
            }
            
            //Sanity check
            if serviceGroupEntries == 0 {
                initialStreamsConnected = true
            }
            
        } else {
            initialStreamsConnected = true
        }
    }
    
    //Check for video permissions
    func validateVideoPermissions() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    //Check for audio persmissions
    func validateMicPermissions() -> Bool {
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }
    
    //Sets the screen title, according to the number of conference participants
    private func setScreenTitle() {
        let membersString = conferenceParticipants == 1 ? "member" : "members"
        var screenTitle = currentConference.id + " ("
        screenTitle += String(conferenceParticipants) + " "
        screenTitle += membersString + ")"
        title =  screenTitle
    }
    
    private func handleError(_ error: Error) {
        let auviousError = error as! AuviousSDKError
        sdkLog("Handle error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
        
        switch auviousError {
        case .videoPermissionIsDisabled:
            delegate?.onConferenceError(.PERMISSION_REQUIRED) // .videoPermissionIsDisabled
        case .audioPermissionIsDisabled:
            delegate?.onConferenceError(.PERMISSION_REQUIRED) // .audioPermissionIsDisabled
        case .missingSDKCredentials:
            delegate?.onConferenceError(.AUTHENTICATION_FAILURE) // .missingSDKCredentials
        case .missingCallTarget:
            delegate?.onConferenceError(.CONFERENCE_MISSING) // .missingCallTarget
        case .noInternetConnection:
            delegate?.onConferenceError(.NETWORK_ERROR) // .noInternetConnection
        case .callNotAnswered:
            delegate?.onConferenceError(.CALL_REJECTED) // .callNotAnswered
        case .INVALID_TICKET(let ticketId):
            delegate?.onConferenceError(.INVALID_TICKET(ticketId: ticketId))
        default:
            delegate?.onConferenceError(.UNKNOWN_FAILURE) // .callError
        }
    }
    
    private func handleConferenceEndedEvent(){
        endCobrowseWithCall(.agentEnded)
        tearDownArPointer()
        let sdk = AuviousConferenceSDK.sharedInstance
        if sdk.sharingMyScreen {
            sdk.rtcClient?.stopScreenSharing()
        }
        sdk.sharingMyScreen = false
        localScreenShareStreamId = nil
        stopScreenSharingButton.alpha = 0
        delegate?.onConferenceSuccess()
    }
    
    //Triggers stream view refresh/removal according to the remote participant's stream state
    private func handleStreamDisconnection(streamId: String, streamType: StreamType, endpointId: String) {
        defer {
            //The pointed at tile may be gone
            refreshArPointer()
        }
        if streamType == .screen {
            shareScreenContainerView?.videoStreamRemoved()
            shareScreenContainerView?.removeFromSuperview()
            shareScreenContainerView = nil
            
            //Announce it
            isAgentSharingScreen = false
            NotificationCenter.default.post(name: Notification.Name(rawValue: AuviousNotification.shared.agentStoppedScreenShare), object: nil, userInfo: nil)
            
            //Refresh UI
            createConstraints()
        } else {
            var remoteParticipantIndex: Int?
            for (index, item) in remoteViews.enumerated() {
                if item.participantEndpoint?.id == endpointId {
                    remoteParticipantIndex = index
                    break
                }
            }

            if let index = remoteParticipantIndex {
                let participant = remoteViews[index].participantEndpoint

                // Remove the disconnected stream from tracking before checking count,
                // so a concurrent stream addition (e.g. CAM → MIC_AND_CAM race) doesn't
                // inflate the count and trigger the wrong branch.
                participant?.streams.removeAll { $0.id == streamId }

                //We only had 1 stream from this participant: while they are still in the conference their tile
                //stays, with the user placeholder, otherwise it goes
                if participant?.streams.count == 0 {
                    let remoteView = remoteViews[index]

                    if index < maximumRemoteStreamsRendered {
                        if streamType == .mic {
                            remoteView.audioStreamRemoved(screenMode: screenMode)
                        } else if streamType == .cam {
                            remoteView.videoStreamRemoved()
                        } else if streamType == .micAndCam {
                            remoteView.avStreamRemoved()
                        }
                    }

                    if AuviousConferenceSDK.sharedInstance.remoteParticipants[endpointId] != nil {
                        if index == 0 {
                            isAgentMuted = false
                        }
                        updateNoVideoPlaceholder(remoteView)
                    } else {
                        removeRemoteView(at: index)
                    }

                } else if (participant?.streams!.count)! > 0 {

                    let remoteView = remoteViews[index]
                    //Remove the video if needed
                    if streamType == .cam {
                        remoteView.videoStreamRemoved()
                    } else if streamType == .mic {
                        remoteView.audioStreamRemoved(screenMode: screenMode)
                    } else if streamType == .micAndCam {
                        remoteView.avStreamRemoved()
                    }
                    updateNoVideoPlaceholder(remoteView)
                }
            }
        }
    }
    
    //Returns the collection view index path of the cell that will handle this stream
    private func getIndexPathForStream(stream: RTCMediaStream, streamId: String, endpointId: String) -> Int {
        var streamType: StreamType!
        if stream.audioTracks.count > 0 && stream.videoTracks.count > 0 {
            streamType = StreamType.micAndCam
        } else if stream.audioTracks.count == 0 && stream.videoTracks.count > 0 {
            streamType = StreamType.cam
        } else if stream.audioTracks.count > 0 && stream.videoTracks.count == 0 {
            streamType = StreamType.mic
        }
        
        var remoteParticipantIndex: Int?
        for (index, item) in remoteViews.enumerated() {
            if item.participantEndpoint?.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        //Stream view is already created
        if let index = remoteParticipantIndex {

            //Add new stream to this user's endpoint (a stream viewed again after a lost connection is there already)
            let participantEndpoint = remoteViews[index].participantEndpoint
            if participantEndpoint?.streams.contains(where: { $0.id == streamId }) != true {
                let participantStream = ParticipantEndpointStream(id: streamId, type: streamType)
                participantEndpoint?.streams.append(participantStream)
            }
            updateNoVideoPlaceholder(remoteViews[index])

            return index
        } else {

            //Create a new remote participant with the incoming stream
            let participantEndpoint = ParticipantEndpoint(endpointId: endpointId)
            let participantStream = ParticipantEndpointStream(id: streamId, type: streamType)
            participantEndpoint.streams.append(participantStream)

            let remoteView = addRemoteView(for: participantEndpoint)
            updateNoVideoPlaceholder(remoteView)
            return self.remoteViews.count - 1
        }
    }

    //Creates the tile of a remote participant
    private func addRemoteView(for participantEndpoint: ParticipantEndpoint) -> StreamView {
        let remoteView = StreamView(frame: .zero)
        remoteView.translatesAutoresizingMaskIntoConstraints = false
        remoteView.participantEndpoint = participantEndpoint
        //Black, like the camera off state, while the video loads or when there is none
        remoteView.backgroundColor = .black
        //Outlined from the moment it appears, whatever it shows
        remoteView.videoBorder = (UIColor.white.withAlphaComponent(0.3), 1)
        //Square until its video's size is known, then resized to the video (createConstraints())
        remoteView.onVideoShapeChange = { [weak self] in
            self?.createConstraints()
        }
        //Keeps the mute badge clear of the call buttons
        remoteView.audioMutedBadgeBottomLimit = buttonContainerView.topAnchor
        //Tapping switches the video between fit and fill, unless it is a portrait video
        remoteView.portraitMode = portraitModeEndpoints.contains(participantEndpoint.id)
        remoteView.togglesFitOnTap = screenMode == .fullScreen
        remoteView.onFitChange = { [weak self] in
            self?.createConstraints()
        }
        self.remoteViews.append(remoteView)
        streamContainerView.addSubview(remoteView)
        view.bringSubviewToFront(buttonContainerView)

        //Start as a transparent square in the middle of the screen, so the layout animation
        //grows it from the center instead of from the top left corner
        let side = view.safeAreaLayoutGuide.layoutFrame.width
        UIView.performWithoutAnimation {
            remoteView.frame = CGRect(x: view.bounds.midX - side / 2, y: view.bounds.midY - side / 2, width: side, height: side)
            remoteView.layoutIfNeeded()
        }
        remoteView.alpha = 0
        remoteView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        appearingRemoteViews.append(remoteView)

        //If we can't show remote video due to UI limits, notify the user
        if initialStreamsConnected && remoteViews.count > maximumRemoteStreamsRendered {
            self.networkIndicatorDetails.updateUI(with: "A new participant has joined", subtitle: "Due to current limitations, you can only listen")
            self.showNetworkDetails()
        }

        return remoteView
    }

    /// A participant who publishes no camera shows a square tile, like a camera that is off: the mic icon,
    /// or the muted mic when they publish no audio or are muted
    private func updateNoVideoPlaceholder(_ remoteView: StreamView) {
        let publishesVideo = remoteView.participantEndpoint?.streams.contains { $0.type == .cam || $0.type == .micAndCam } ?? false
        remoteView.showsNoVideoPlaceholder = !publishesVideo
    }

    /// Shows the tile of a participant who joined, before (or without) any video. Not for co-browse endpoints, which are screens.
    private func showJoinedParticipant(endpointId: String?, endpointType: String?) {
        guard let endpointId = endpointId, !endpointId.isEmpty,
              endpointId != AuviousConferenceSDK.sharedInstance.userEndpointId,
              endpointType != "displayCapture", endpointType != "coBrowse",
              !remoteViews.contains(where: { $0.participantEndpoint?.id == endpointId }) else {
            return
        }
        //Turning the placeholder on lays the tile out (onVideoShapeChange)
        updateNoVideoPlaceholder(addRemoteView(for: ParticipantEndpoint(endpointId: endpointId)))
    }

    //Removes the tile of a participant who left
    private func removeLeftParticipant(endpointId: String?) {
        guard let index = remoteViews.firstIndex(where: { $0.participantEndpoint?.id == endpointId }) else {
            return
        }
        //Detaches any video still attached
        remoteViews[index].resetStreamView()
        removeRemoteView(at: index)
        //The pointed at tile may be gone
        refreshArPointer()
    }

    //Removes a participant's tile
    private func removeRemoteView(at index: Int) {
        let remoteView = remoteViews.remove(at: index)
        if index == 0 {
            isAgentMuted = false
        }
        remoteView.removeFromSuperview()

        //Refresh UI
        if remoteViews.isEmpty && (screenMode == .pip || screenMode == .expandedPip) && !AuviousConferenceSDK.sharedInstance.sharingMyScreen {
            screenMode = .fullScreen
        }
        createConstraints()
    }
    
    // MARK: -
    // MARK: AuviousSDKConferenceDelegate
    // MARK: -
    
    public func auviousSDK(conferenceOnHold flag: Bool) {
        let effectDuration: Double = 0.2
        
        if flag {
            
            if let screenshot = streamContainerView.screenshot().grayscaled {
                
                blurredOverlayView = ConferenceHoldView(frame: .zero)
                blurredOverlayView!.image = screenshot
                blurredOverlayView?.configurePiP(screenMode != .fullScreen)
                view.insertSubview(blurredOverlayView!, belowSubview: pipMaximiseButton)

                blurredOverlayView?.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
                blurredOverlayView?.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
                blurredOverlayView?.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0).isActive = true
                blurredOverlayView?.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0).isActive = true

                pipMuteButton.isUserInteractionEnabled = false
                pipMuteButton.alpha = 0.5
                if AuviousConferenceSDK.sharedInstance.sharingMyScreen {
                    pipStopShareButton.isUserInteractionEnabled = false
                    pipStopShareButton.alpha = 0.5
                }
                isConferenceOnHold = true

                UIView.animate(withDuration: effectDuration, animations: {
                    self.blurredOverlayView?.blurView.alpha = 0.9
                }, completion: { _ in
                    self.buttonContainerView.conferenceOnHold(true)
                    AuviousConferenceSDK.sharedInstance.removeLocalAudioStream()
                    AuviousConferenceSDK.sharedInstance.removeLocalVideoStream()
                })
            }
        } else {
            if let blurredOverlayView = blurredOverlayView {
                UIView.animate(withDuration: effectDuration, animations: {
                    blurredOverlayView.alpha = 0
                }, completion: { _ in
                    self.buttonContainerView.conferenceOnHold(false)
                    self.pipMuteButton.isUserInteractionEnabled = true
                    self.pipMuteButton.alpha = 1
                    self.pipStopShareButton.isUserInteractionEnabled = true
                    self.pipStopShareButton.alpha = 1
                    self.isConferenceOnHold = false
                    //Off hold re-enabled every button: keep the ones the AR pointer and co-browse disable
                    self.applyArPointerControls()

                    AuviousConferenceSDK.sharedInstance.addLocalAudioStream()
                    AuviousConferenceSDK.sharedInstance.addLocalVideoStream()

                    blurredOverlayView.removeFromSuperview()
                    self.blurredOverlayView = nil
                })
            }
        }
    }

    public func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent) {
        if let joined = event as? ConferenceJoinedEvent {
            conferenceParticipants += 1
            DispatchQueue.main.async {
                self.showJoinedParticipant(endpointId: joined.userEndpointId, endpointType: joined.endpointType)
            }
        } else if event is ConferenceLeftEvent {
            conferenceParticipants -= 1
            DispatchQueue.main.async {
                self.removeLeftParticipant(endpointId: event.userEndpointId)
            }
        } else if event is ConferenceEndedEvent {
            handleConferenceEndedEvent()
        } else if event is ConferenceNetworkIndicatorEvent {
            let endpoint = AuviousConferenceSDK.sharedInstance.userEndpointId
            let object = event as! ConferenceNetworkIndicatorEvent
            networkIndicator.updateUI(with: object, participantId: endpoint)
            
            if let endpoint = endpoint {
                self.lastKnownNetworkStatistics = object.data[endpoint]
            }
        } else if event is ConferenceStreamPublishedEvent {
            let object = event as! ConferenceStreamPublishedEvent
            if object.portraitMode, let endpointId = object.userEndpointId {
                portraitModeEndpoints.insert(endpointId)
            }
            do {
                sdkLog("Starting remote stream flow for type %@", log: Log.conferenceUI, type: .debug, object.streamType.rawValue)
                try AuviousConferenceSDK.sharedInstance.startRemoteStreamFlow(streamId: object.streamId, endpointId: object.userEndpointId, streamType: object.streamType, remoteUserId: object.userId)
            } catch let error {
                sdkLog("startRemoteStreamFlow error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
                handleError(error)
            }
        } else if event is ConferenceStreamUnpublishedEvent {
            let object = event as! ConferenceStreamUnpublishedEvent
            
            do {
                try AuviousConferenceSDK.sharedInstance.stopRemoteStream(streamId: object.streamId, remoteUserId: object.userId, remoteEndpointId: object.userEndpointId, streamType: object.streamType)
            } catch let error {
                sdkLog("stopRemoteStream error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
                handleError(error)
            }
        }
    }
    
    public func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {
        DispatchQueue.main.async {
            //The same shared screen viewed again after its connection was lost: only its video is new
            if type == .screen, let shareView = self.shareScreenContainerView,
               shareView.participantEndpoint?.streams.contains(where: { $0.id == streamId }) == true {
                if let videoTrack = stream.videoTracks.first {
                    shareView.videoStreamAdded(videoTrack, isScreen: true)
                }
                return
            }

            if type == .screen {
                
                //Announce it
                self.isAgentSharingScreen = true
                NotificationCenter.default.post(name: Notification.Name(rawValue: AuviousNotification.shared.agentStartedScreenShare), object: nil, userInfo: nil)
                
                self.shareScreenContainerView = StreamView(frame: .zero)
                self.shareScreenContainerView!.translatesAutoresizingMaskIntoConstraints = false
                self.shareScreenContainerView!.setZoomable(true)
                //Shaped like the shared screen inside its space, resized when the shared screen's shape changes
                self.shareScreenContainerView!.onVideoShapeChange = { [weak self] in
                    self?.createConstraints()
                }
                //Zoomed in it fills its slot; at once, as the pinch continues from the same picture
                self.shareScreenContainerView!.onZoomChange = { [weak self] in
                    self?.createConstraints(animated: false)
                }
                self.shareScreenContainerView!.videoBorder = (UIColor.white.withAlphaComponent(0.3), 1)

                #warning("potential mem leak")
                let tap = UITapGestureRecognizer(target: self, action: #selector(self.shareScreenDoubleTapped))
                tap.numberOfTapsRequired = 2
                self.shareScreenContainerView?.addGestureRecognizer(tap)
                
                //Create a new remote participant with the incoming stream
                let participantEndpoint = ParticipantEndpoint(endpointId: endpointId)
                let participantStream = ParticipantEndpointStream(id: streamId, type: type)
                participantEndpoint.streams.append(participantStream)
                
                self.shareScreenContainerView!.participantEndpoint = participantEndpoint
                self.shareScreenContainerView!.backgroundColor = self.videoViewBackgroundColor
                
                //Add the video stream to our cell
                if stream.videoTracks.count > 0 {
                    let remoteVideoTrack: RTCVideoTrack = stream.videoTracks.first!
                    self.shareScreenContainerView!.videoStreamAdded(remoteVideoTrack, isScreen: true)
                }
                
                self.streamContainerView.addSubview(self.shareScreenContainerView!)
                
            } else {
                let remoteViewIndex = self.getIndexPathForStream(stream: stream, streamId: streamId, endpointId: endpointId)
                let remoteView = self.remoteViews[remoteViewIndex]
                
                //Add the video stream to our cell
                if stream.videoTracks.count > 0 {
                    let remoteVideoTrack: RTCVideoTrack = stream.videoTracks.first!

                    if stream.audioTracks.count > 0 {
                        remoteView.avStreamAdded(remoteVideoTrack)
                    } else {
                        remoteView.videoStreamAdded(remoteVideoTrack)
                    }
                    
                    //Handle muted video tracks
                    if self.currentConference.mutedVideoTracks.contains(streamId) {
                        remoteView.videoStreamRemoved()
                    }
                    //Hande muted audio tracks
                    if self.currentConference.mutedAudioTracks.contains(streamId) {
                        remoteView.audioStreamRemoved(screenMode: self.screenMode)
                        if remoteViewIndex == 0 {
                            self.isAgentMuted = true
                        }
                    }
                    
                    sdkLog("Remote stream added", log: Log.conferenceUI, type: .debug)
                
                } else if stream.audioTracks.count > 0 {
                    remoteView.audioStreamAdded()
                    
                    //Handle muted audio tracks
                    if self.currentConference.mutedAudioTracks.contains(streamId) {
                        remoteView.audioStreamRemoved(screenMode: self.screenMode)
                        if remoteViewIndex == 0 {
                            self.isAgentMuted = true
                        }
                    }
                }
            }
            
            //Keep track of this stream addition
            if !self.initialStreamsConnected {
                self.serviceGroup.leave()
            }
            
            // Proceed when all API requests are finished
            self.serviceGroup.notify(queue: DispatchQueue.main) {
                if !self.initialStreamsConnected {
                    self.initialStreamsConnected = true
                    
                    if self.remoteViews.count > self.maximumRemoteStreamsRendered {
                        let title = "Limited visibility"
                        let subtitle = "You can only see \(self.maximumRemoteStreamsRendered)/\(self.remoteViews.count) participants"
                        self.networkIndicatorDetails.updateUI(with: title, subtitle: subtitle)
                        self.showNetworkDetails()
                    }
                }
            }
            
            //Refresh UI (the AR pointer may be waiting for this stream)
            self.refreshArPointer()
            
            //Respect client configuration for audio routing (only on first join, not rejoin)
            if !self.hasAppliedInitialAudioRoute {
                self.hasAppliedInitialAudioRoute = true
                self.prefersSpeaker = self.clientConfiguration.enableSpeaker
                let result = AuviousConferenceSDK.sharedInstance.changeAudioRoot(toSpeaker: self.prefersSpeaker)
            }
        }
    }
    
    public func auviousSDK(didRejoinConference conference: ConferenceSimpleView) {
        //Clear the streams from the UI
        _ = remoteViews.map{ $0.removeFromSuperview() }
        remoteViews.removeAll()
        isAgentMuted = false

        // Reset local view so the stale video track is detached from the renderer
        // before the republished stream arrives. Without this, the old frozen frame
        // can linger even after the new video track is attached.
        localView.resetStreamView()

        currentConference = conference
        conferenceParticipants = currentConference.participants.count

        // Restore stream type from button state so camera/mic remain
        // in whatever state the user left them before backgrounding
        let camOn = buttonContainerView.cameraButton.type == .camEnabled
        let micOn = buttonContainerView.micButton.type == .micEnabled

        if camOn && micOn {
            configuredStreamType = .micAndCam
        } else if camOn {
            configuredStreamType = .cam
        } else {
            configuredStreamType = .mic
        }

        // Reapply speaker/earpiece route — AVAudioSession resets on rejoin.
        // Use prefersSpeaker rather than the button state: the button can be
        // stale if the system changed the route (e.g. Bluetooth removed, or the
        // user picked an output from the iOS audio-route popup) without going
        // through our speaker button handler.
        let _ = AuviousConferenceSDK.sharedInstance.changeAudioRoot(toSpeaker: prefersSpeaker)

        //Reconnect to conference streams
        handleExistingConferenceStreams()
        startLocalStream()

        //A co-browse that was sharing before the app went to the background shares again
        cobrowseSession?.callResumed()

        //The tiles are rebuilt as the streams come back
        refreshArPointer()
        arPointerConferenceJoined()
    }

    public func auviousSDK(didResumeFromBackground withActiveAudio: Bool) {
        // Audio route and peer connections are still active — just refresh video layout
        createConstraints()
        cobrowseSession?.callResumed()
    }
    
    public func auviousSDK(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String) {
        switch newState {
        case .localStreamIsConnecting:
            sdkLog("Local Stream Is Connecting", log: Log.conferenceUI, type: .debug)
        case .localStreamConnected:
            sdkLog("Local Stream Connected", log: Log.conferenceUI, type: .debug)
        case .remoteStreamIsConnecting:
            sdkLog("Remote Stream Is Connecting", log: Log.conferenceUI, type: .debug)
        case .remoteStreamConnected:
            sdkLog("Remote Stream Connected", log: Log.conferenceUI, type: .debug)
            let _ = AuviousConferenceSDK.sharedInstance.changeAudioRoot(toSpeaker: prefersSpeaker)
        case .localStreamIsDisconnecting:
            sdkLog("Local Stream Is Disonnecting", log: Log.conferenceUI, type: .debug)
        case .localStreamDisconnected:
            sdkLog("Local Stream Disconnected", log: Log.conferenceUI, type: .debug)
        case .remoteStreamIsDisconnecting:
            sdkLog("Remote Stream Is Disonnecting", log: Log.conferenceUI, type: .debug)
        case .remoteStreamDisconnected:
            sdkLog("Remote Stream Disconnected", log: Log.conferenceUI, type: .debug)
            handleStreamDisconnection(streamId: streamId, streamType:streamType, endpointId: endpointId)
        case .localCaptureStarted:
            sdkLog("Local Capture Started", log: Log.conferenceUI, type: .debug)
        case .localCaptureStoped:
            sdkLog("Local Capture Stoped", log: Log.conferenceUI, type: .debug)
        }
    }
    
    //Local stream received (streamAdded)
    public func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        localView.avStreamAdded(localVideoTrack)
        createConstraints()
        
        // sync local view with call type
        switch (configuredStreamType){
            case .cam:
                localView.audioStreamRemoved(screenMode: screenMode)
                break;
            case .mic:
                localView.videoStreamRemoved()
                break;
            default:
                // no changes
            break;
        }
    }
    
    public func auviousSDK(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {
       localStreamType = type
        if  type == .mic {
            localView.audioStreamAdded()
        }
        DispatchQueue.main.async { [weak self] in
            self?.refreshArPointer()
        }
    }
    
    public func auviousSDK(recorderStateChanged toActive: Bool) {
        // show a notification
        sdkLog("recorder state changed", log: Log.conferenceUI, type: .debug )
        
        showNotification(
            with: NSLocalizedString("Recording", comment: "Notification"),
            subtitle: toActive
            ? NSLocalizedString("Session is being recorded", comment: "Notification")
            : NSLocalizedString("Session is no longer recorded", comment: "Notification"),
            symbol: toActive ? "record.circle.fill" : "record.circle",
            tint: toActive ? .systemRed : .secondaryLabel
        )
        isRecording = toActive
        createConstraints()
    }
    
    public func auviousSDK(trackMuted type: StreamType, endpointId: String) {
        var remoteParticipantIndex: Int?
        for (index, item) in remoteViews.enumerated() {
            if item.participantEndpoint?.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        if let index = remoteParticipantIndex {
            if type == .mic {
                remoteViews[index].audioStreamRemoved(screenMode: screenMode)
                //The agent's mute also shows in the PiP status capsule
                if index == 0 {
                    isAgentMuted = true
                }
            } else if type == .cam {
                remoteViews[index].videoStreamRemoved()
            }
        }
    }
    
    public func auviousSDK(trackUnmuted type: StreamType, endpointId: String) {
        var remoteParticipantIndex: Int?
        for (index, item) in remoteViews.enumerated() {
            if item.participantEndpoint?.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        if let index = remoteParticipantIndex {
            if type == .mic {
                remoteViews[index].audioStreamAdded()
                if index == 0 {
                    isAgentMuted = false
                }
            } else if type == .cam {
                remoteViews[index].videoStreamAdded()
            }
        }
    }
    
    public func auviousSDK(agentPortraitMode flag: Bool, endpointId: String) {
        if flag {
            portraitModeEndpoints.insert(endpointId)
        } else {
            portraitModeEndpoints.remove(endpointId)
        }
        remoteViews.first { $0.participantEndpoint?.id == endpointId }?.portraitMode = flag

        var remoteParticipantIndex: Int?
        for (index, item) in remoteViews.enumerated() {
            if item.participantEndpoint?.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        if let index = remoteParticipantIndex {
            agentVideoPortraitMode = flag
        }
    }
    
    public func auviousSDK(screenSharingStarted: Bool) {
        //Co-browse moves the call to PiP itself, without the sharing border
        guard cobrowseSession == nil else { return }

        minimizeToPiP()
        
        //Display sharing border
        toggleSharingBorder(mode: true)
        refreshArPointer()
    }
    
    public func auviousSDK(screenSharingStopped: Bool) {
        localScreenShareStreamId = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopScreenSharingButton.alpha = 0
            self.toggleSharingBorder(mode: false)
            self.cobrowseSession?.screenSharingStopped()
            self.refreshArPointer()
        }
    }

    public func auviousSDK(didRepublishLocalStream oldStreamId: String, as newStreamId: String) {
        DispatchQueue.main.async {
            if self.localStreamId == oldStreamId {
                self.localStreamId = newStreamId
            }
        }
    }

    public func auviousSDK(streamConnectionChanged state: StreamRecoveryState?, endpointId: String, isLocal: Bool) {
        DispatchQueue.main.async {
            if isLocal {
                self.localView.showsConnectionLabel = false
                self.localView.connectionState = state
            } else {
                self.remoteViews.first { $0.participantEndpoint?.id == endpointId }?.connectionState = state
            }
        }
    }

    public func auviousSDK(onError error: AuviousSDKError) {
        DispatchQueue.main.async { [weak self] in
            self?.cobrowseSession?.sdkError(error)
        }
    }
    
    // MARK: -
    // MARK: UI
    // MARK: -
    
    //Creates the button bar
    private func createButtonBar() {
        //Button container
        buttonContainerView = ConferenceButtonBar(configuration: clientConfiguration)
        buttonContainerView.delegate = self
        view.addSubview(buttonContainerView)
        
        buttonContainerView.leadingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.leadingAnchor, constant: 0).isActive = true
        buttonContainerView.trailingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.trailingAnchor, constant: 0).isActive = true
        buttonContainerView.bottomAnchor.constraint(equalTo: view.saferAreaLayoutGuide.bottomAnchor, constant: 0).isActive = true
        buttonContainerView.heightAnchor.constraint(equalToConstant: 60).isActive = true
        
        switch (configuredStreamType){
            case .cam:
                buttonContainerView.micButton.type = .micDisabled
                break;
            case .mic:
                buttonContainerView.cameraButton.type = .camDisabled
                buttonContainerView.cameraSwitchButton.type = .camSwitchDisabled
                break;
            default:
                // no changes
            break;
        }
    }
    
    @objc func shareScreenDoubleTapped() {
        self.shareScreenFullScreen = !shareScreenFullScreen
        createConstraints()
    }
    
    /// Full screen: network and recording dot in the capsule below the status bar; each participant's
    /// video shows its own mute badge. PiP: a small capsule in the top left corner with the recording
    /// and the agent's mute icons, in place of the agent's badge.
    private func layoutStatusCapsule() {
        let inPiP = screenMode != .fullScreen

        networkIndicator.isHidden = inPiP
        recorderIndicator.isHidden = !isRecording
        remoteMutedIcon.isHidden = !inPiP || !isAgentMuted
        if let agentView = remoteViews.first, agentView.showsAudioMutedBadge == inPiP {
            agentView.showsAudioMutedBadge = !inPiP
        }
        //Shown once someone has joined, and only with something in it
        let showsCapsule = !remoteViews.isEmpty && !statusStack.arrangedSubviews.allSatisfy { $0.isHidden }
        if showsCapsule && !isStatusCapsuleRevealed {
            revealStatusCapsule()
        } else if !showsCapsule {
            isStatusCapsuleRevealed = false
            statusCapsule.isHidden = true
            statusCapsule.effect = nil
        }

        //White dot on a red circle
        recorderIndicator.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: inPiP ? 15 : 18, weight: .regular)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
        statusStack.spacing = inPiP ? 6 : 10
        //Tighter when the network bars are alone, so the capsule stays compact
        let networkOnly = recorderIndicator.isHidden
        let leading: CGFloat = inPiP ? 6 : (networkOnly ? 10 : 12)
        //With the dot last, the same space on its right as above and below it ((34 - 20) / 2)
        let trailing: CGFloat = inPiP ? 6 : (networkOnly ? 10 : 7)
        statusStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
        //In PiP taps belong to the PiP window (drag, double tap to expand)
        statusCapsule.isUserInteractionEnabled = !inPiP

        let height: CGFloat = inPiP ? 26 : 34
        statusCapsule.layer.cornerRadius = height / 2

        NSLayoutConstraint.deactivate(statusCapsuleConstraints)
        statusCapsuleConstraints = [
            statusCapsule.heightAnchor.constraint(equalToConstant: height),
            //As wide as the symbol, like the network bars
            recorderIndicator.widthAnchor.constraint(equalToConstant: inPiP ? 17 : 20),
            recorderIndicator.heightAnchor.constraint(equalToConstant: inPiP ? 17 : 30),
        ]
        if inPiP {
            statusCapsuleConstraints += [
                statusCapsule.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
                statusCapsule.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            ]
        } else {
            statusCapsuleConstraints += [
                statusCapsule.topAnchor.constraint(equalTo: view.saferAreaLayoutGuide.topAnchor, constant: 2),
                statusCapsule.leadingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.leadingAnchor, constant: 6),
            ]
        }
        NSLayoutConstraint.activate(statusCapsuleConstraints)
    }

    /// Materializes the capsule's glass and fades its icons in. It waits for the layout animation that
    /// placed the first participant, so the capsule never morphs from an unplaced frame.
    private func revealStatusCapsule() {
        isStatusCapsuleRevealed = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.isStatusCapsuleRevealed else { return }
            self.statusCapsule.effect = nil
            self.statusStack.alpha = 0
            self.statusCapsule.isHidden = false
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut], animations: {
                self.statusCapsule.effect = self.statusCapsuleEffect
                self.statusStack.alpha = 1
            })
        }
    }

    //The orientation the UI is laid out in (unknown before the view has a window)
    private var layoutOrientation: UIInterfaceOrientation {
        guard let scene = view.window?.windowScene else { return .unknown }
        if #available(iOS 16.0, *) {
            return scene.effectiveGeometry.interfaceOrientation
        }
        return scene.interfaceOrientation
    }

    /// The layouts place the tiles edge to edge in their space. For a tile that follows its video's shape, its constraints
    /// place its `layoutSlot` instead, and the tile is the largest rectangle shaped like the video centered in the slot.
    private func fitTilesToVideo(_ constraints: [NSLayoutConstraint]) -> [NSLayoutConstraint] {
        var slots: [ObjectIdentifier: UILayoutGuide] = [:]
        var result: [NSLayoutConstraint] = []

        //Only tiles the layout above places (the screen share only while it is in focus). Our camera only while the AR pointer points at it.
        let placed = Set(constraints.flatMap { [$0.firstItem, $0.secondItem] }.compactMap { $0 as? StreamView }.map(ObjectIdentifier.init))
        for tile in [localView] + remoteViews + [shareScreenContainerView].compactMap({ $0 }) {
            let slot = tile.layoutSlot
            guard tile.followsVideoShape, placed.contains(ObjectIdentifier(tile)), let parent = tile.superview else {
                slot.owningView?.removeLayoutGuide(slot)
                continue
            }
            if slot.owningView !== parent {
                slot.owningView?.removeLayoutGuide(slot)
                parent.addLayoutGuide(slot)
            }
            slots[ObjectIdentifier(tile)] = slot

            let fillWidth = tile.widthAnchor.constraint(equalTo: slot.widthAnchor)
            let fillHeight = tile.heightAnchor.constraint(equalTo: slot.heightAnchor)
            fillWidth.priority = .defaultHigh
            fillHeight.priority = .defaultHigh
            result += [
                tile.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
                tile.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
                tile.widthAnchor.constraint(lessThanOrEqualTo: slot.widthAnchor),
                tile.heightAnchor.constraint(lessThanOrEqualTo: slot.heightAnchor),
                tile.widthAnchor.constraint(equalTo: tile.heightAnchor, multiplier: tile.videoShape.width / tile.videoShape.height),
                fillWidth,
                fillHeight
            ]
        }
        guard !slots.isEmpty else { return constraints }

        func slotted(_ item: AnyObject?) -> AnyObject? {
            guard let tile = item as? StreamView, let slot = slots[ObjectIdentifier(tile)] else { return item }
            return slot
        }
        for constraint in constraints {
            let first = slotted(constraint.firstItem)
            let second = slotted(constraint.secondItem)
            guard first !== constraint.firstItem || second !== constraint.secondItem, let firstItem = first else {
                result.append(constraint)
                continue
            }
            let moved = NSLayoutConstraint(item: firstItem, attribute: constraint.firstAttribute, relatedBy: constraint.relation,
                                           toItem: second, attribute: constraint.secondAttribute,
                                           multiplier: constraint.multiplier, constant: constraint.constant)
            moved.priority = constraint.priority
            result.append(moved)
        }
        return result
    }

    internal func createConstraints(animated: Bool = true) {
        //Before the mode specific layout below, which can return early
        layoutStatusCapsule()

        var constraints: [NSLayoutConstraint] = []
        let safeArea = streamContainerView.saferAreaLayoutGuide
        //The window's shape, not ours (PIP): statusBarOrientation is a no-op from iOS 27
        let windowBounds = view.window?.bounds ?? UIScreen.main.bounds
        let isLandscape = windowBounds.width > windowBounds.height
        var safeLeadingConstraint = view.leadingAnchor
        
        //Notch on the leading side (interface landscapeRight, i.e. device landscapeLeft): the safe area's
        //leading edge, otherwise the superview's. From the interface, not the device: a phone lying flat
        //or with rotation locked reports a device orientation the UI isn't in
        if layoutOrientation == .landscapeRight {
            safeLeadingConstraint = safeArea.leadingAnchor
        }
        
        //In PiP only the agent's tile shows, from the call's own view
        if screenMode != .fullScreen {
            placeTilesInFocusStrip(false, focused: nil)
        }

        //PIP mode
        if screenMode == .pip {
            sdkLog("PIP screen share mode entered", log: Log.conferenceUI, type: .info)
            blurredOverlayView?.configurePiP(true)
            pipMaximiseButton.alpha = 0
            pipBottomBar.alpha = 0
            
            stopScreenSharingButton.alpha = 0
            buttonContainerView.alpha = 0
            
            if !remoteViews.isEmpty {
                let agentView = remoteViews[0]
                agentView.overlayInPIP()
                
                constraints.append(agentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0))
                constraints.append(agentView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0))
                constraints.append(agentView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0))
                constraints.append(agentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0))
            }
        } else if screenMode == .expandedPip {
            sdkLog("Expanded PIP screen share mode entered", log: Log.conferenceUI, type: .info)
            blurredOverlayView?.configurePiP(true)
            stopScreenSharingButton.alpha = 0
            buttonContainerView.alpha = 0
            pipMaximiseButton.alpha = 1
            
            let pipBarItems = pipBottomBar.arrangedSubviews
            for p in pipBarItems {
                pipBottomBar.removeArrangedSubview(p)
                p.removeFromSuperview()
            }
            if !AuviousConferenceSDK.sharedInstance.sharingMyScreen {
                if clientConfiguration.microphoneAvailable {
                    pipBottomBar.addArrangedSubview(pipMuteButton)
                }
            } else {
                pipBottomBar.addArrangedSubview(pipStopShareButton)
                if clientConfiguration.microphoneAvailable {
                    pipBottomBar.addArrangedSubview(pipMuteButton)
                }
            }
            
            pipBottomBar.alpha = 1

            guard !remoteViews.isEmpty else { return }
            let agentView = remoteViews[0]
            agentView.overlayInPIP()
            
            constraints.append(agentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0))
            constraints.append(agentView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0))
            constraints.append(agentView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0))
            constraints.append(agentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0))
        } else {
            sdkLog("PIP screen share mode exited", log: Log.conferenceUI, type: .info)
            blurredOverlayView?.configurePiP(false)
            pipMaximiseButton.alpha = 0
            pipBottomBar.alpha = 0
            
            if AuviousConferenceSDK.sharedInstance.sharingMyScreen {
                stopScreenSharingButton.alpha = 1
            }
            
            //Show button container
            buttonContainerView.alpha = 1
            
            //One tile in focus: the agent's screen share or the AR pointer's target, the others in a row
            let focused = focusedView
            let showsShareFullScreen = focused != nil && focused === shareScreenContainerView && shareScreenFullScreen
            placeTilesInFocusStrip(focused != nil, focused: focused)
            shareScreenContainerView?.isHidden = focused !== shareScreenContainerView
            for r in remoteViews {
                r.restoreOverlay()
                //Only the 1:1 portrait layout below turns it on
                r.tapSwitchesToPortrait = false
            }

            if let focused = focused {
                constraints.append(contentsOf: focusConstraints(focused: focused, fullScreen: showsShareFullScreen, isLandscape: isLandscape, safeArea: safeArea, safeLeading: safeLeadingConstraint))
            } else if renderedRemoteViews.count >= 3 {
                constraints.append(contentsOf: gridConstraints(isLandscape: isLandscape, safeArea: safeArea))
            } else {
                //Our video sits top right from the start, also while we wait for others to join.
                //Shaped like the camera's video, so nothing is cropped: 3:4 (640x480 in portrait)
                //until the first frame gives the real size.
                do {
                    let videoSize = localView.size
                    let aspect: CGFloat = localView.hasVideoSize ? videoSize.height / videoSize.width : (isLandscape ? 3/4 : 4/3)
                    //The same margin from the top and the right
                    constraints.append(localView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -10))
                    constraints.append(localView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 10))
                    constraints.append(localView.widthAnchor.constraint(equalToConstant: isLandscape ? 237 : 135))
                    constraints.append(localView.heightAnchor.constraint(equalTo: localView.widthAnchor, multiplier: aspect))
                }

                if remoteViews.count == 1 {
                    let view1 = remoteViews[0]
                    view1.tapSwitchesToPortrait = !isLandscape
                    
                    if !isLandscape {
                        if !view1.hasVideoSize || view1.showsNoVideoPlaceholder {
                            //Loading, or no video: a centered square until a frame gives its size
                            constraints.append(view1.centerXAnchor.constraint(equalTo: view.centerXAnchor))
                            constraints.append(view1.centerYAnchor.constraint(equalTo: view.centerYAnchor))
                            constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                            constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                            constraints.append(view1.heightAnchor.constraint(equalTo: view1.widthAnchor))
                        } else if agentVideoPortraitMode || view1.isTappedToPortrait {
                            //Full screen portrait video (with top|safeArea)
                            constraints.append(view1.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor))
                            constraints.append(view1.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor))
                            constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                            constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                            constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                            constraints.append(view1.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0))

                        } else {
                            //The safe area is its slot: shaped like its video and centered in it (fitTilesToVideo)
                            constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                            constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                            constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                            constraints.append(view1.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                        }
                    } else {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                    }
                } else if remoteViews.count == 2 {
                    let view1 = remoteViews[0]
                    let view2 = remoteViews[1]
                    
                    if !isLandscape {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        
                        constraints.append(view2.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view2.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view2.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                        
                        constraints.append(view1.bottomAnchor.constraint(equalTo: view2.topAnchor, constant: -viewPadding))
                        constraints.append(view1.heightAnchor.constraint(equalTo: view2.heightAnchor, constant: 0))
                    } else {
                        constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                        
                        constraints.append(view2.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(view2.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view2.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                        
                        constraints.append(view1.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: view2.leadingAnchor, constant: -viewPadding))
                    }
                }
            }
        }

        constraints += arPointerDockConstraints(layout: constraints)
        //Screen shares and tiles tapped to fit take their video's shape, inside the space the layout above gives them
        constraints = fitTilesToVideo(constraints)

        let applyConstraints = {
            //Clear existing constraints
            if !self.existingConstraints.isEmpty {
                NSLayoutConstraint.deactivate(self.existingConstraints)
            }

            NSLayoutConstraint.activate(constraints)
            self.existingConstraints = constraints

            self.view.layoutIfNeeded()

            //New remote tiles fade and scale in as they settle
            for remoteView in self.appearingRemoteViews {
                remoteView.alpha = 1
                remoteView.transform = .identity
            }
            self.appearingRemoteViews.removeAll()
        }

        //The first layout places the views directly, instead of growing them from a zero frame
        if animated && localView.bounds != .zero {
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 2, options: .curveEaseInOut, animations: applyConstraints)
        } else {
            applyConstraints()
        }

        //Our tile appears: fades in while growing from 0.8x to full size
        if !hasShownLocalView && localView.bounds != .zero {
            hasShownLocalView = true
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.curveEaseOut], animations: {
                self.localView.alpha = 1
                self.localView.transform = .identity
            })
        }
    }
}

// MARK: -
// MARK: ConferenceButtonBarDelegate
// MARK: -
extension AuviousConferenceVCNew: ConferenceButtonBarDelegate {
    
    func pipButtonPressed(_ sender: Any) {
        selectionFeedbackGenerator.impactOccurred()
        
        minimizeToPiP()
        buttonContainerView.resetOptionsButton()
    }
    
    @objc internal func maximisebuttonPressed(_ sender: Any) {
        selectionFeedbackGenerator.impactOccurred()
        handlePiPDoubleTap(self.doubleTapGesture)
    }
    
    //Stops screen sharing
    @objc internal func stopScreenShareButtonPressed(_ sender: Any) {
        selectionFeedbackGenerator.impactOccurred()

        //While co-browsing the same buttons end co-browsing, after confirming
        if let session = cobrowseSession {
            session.confirmEnd()
            return
        }
        
        guard let streamId = localScreenShareStreamId else {
            return
        }
        
        do {
            try AuviousConferenceSDK.sharedInstance.startUnpublishLocalStreamFlow(streamId: streamId, streamType: .screen)
            
            DispatchQueue.main.async {
                self.stopScreenSharingButton.alpha = 0
                
                if self.screenMode == .expandedPip {
                    self.minimizeToPiP()
                }
            }
            
        } catch let error {
            sdkLog("startPublishLocalStreamFlow screen share error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
            handleError(error)
        }
    }
    
    /// One screen share at a time: none while co-browsing, nor while the agent points at a stream (same as the web)
    var canStartScreenShare: Bool {
        return cobrowseSession == nil && arPointer.target == nil
    }

    /// The share screen button is disabled while on hold, co-browsing or in an AR pointer session
    func updateScreenShareButton() {
        guard !isConferenceOnHold else { return }
        let enabled = canStartScreenShare
        buttonContainerView.screenShareButton.alpha = enabled ? 1 : 0.5
        buttonContainerView.screenShareButton.isUserInteractionEnabled = enabled
    }

    //Try to start the screen sharing - will trigger iOS permission dialog
    //UI changes will occur once delegation ensures sharing started
    @objc internal func screenShareButtonPressed(_ sender: Any) {
        guard canStartScreenShare else { return }
        selectionFeedbackGenerator.impactOccurred()
        buttonContainerView.resetOptionsButton()

        AuviousConferenceSDK.sharedInstance.requestScreenSharePermission { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async {
                do {
                    self.localScreenShareStreamId = try AuviousConferenceSDK.sharedInstance.startPublishLocalStreamFlow(type: .screen)
                } catch let error {
                    sdkLog("startPublishLocalStreamFlow screen share error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
                    self.handleError(error)
                }
            }
        }
    }
    
    //The options button opens its menu itself (setupOptionsMenu())
    @objc internal func optionsButtonPressed(_ sender: Any) {}

    /// The buttons that don't fit in the bar, as a native menu on the options button (Liquid Glass on
    /// iOS 26 and later). Its items are built each time it opens, so they always show the current state.
    private func setupOptionsMenu() {
        let types = buttonContainerView.overflowButtonTypes
        guard !types.isEmpty else { return }

        let optionsButton = buttonContainerView.optionsButton
        optionsButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                //Each item in its own inline section, so the menu draws a divider between them
                let items = self?.optionsMenuItems(for: types) ?? []
                completion(items.map { UIMenu(title: "", options: .displayInline, children: [$0]) })
            }
        ])
        optionsButton.showsMenuAsPrimaryAction = true
    }

    private func optionsMenuItems(for types: [ConferenceButtonType]) -> [UIMenuElement] {
        func icon(_ type: ConferenceButtonType) -> UIImage? {
            return UIImage(podAssetName: type.imageName)?.withRenderingMode(.alwaysTemplate)
        }

        return types.compactMap { type -> UIMenuElement? in
            switch type {
            case .speakerON, .speakerOFF:
                //Shows what tapping does: "Use earpiece" while on speaker, "Use speaker" otherwise
                let current = buttonContainerView.speakerButton.type
                return UIAction(title: current.title, image: icon(current)) { [weak self] _ in
                    self?.speakerButtonPressed(self as Any)
                }
            case .pip:
                return UIAction(title: type.title, image: icon(type)) { [weak self] _ in
                    self?.pipButtonPressed(self as Any)
                }
            case .screenShare, .screenShareDisabled:
                let sharing = AuviousConferenceSDK.sharedInstance.sharingMyScreen
                let shown: ConferenceButtonType = sharing ? .stopScreenShare : .screenShare
                //Not while the agent shares their screen or the call is on hold
                let attributes: UIMenuElement.Attributes = ((isAgentSharingScreen || isConferenceOnHold) && !sharing) || cobrowseSession != nil ? .disabled : []
                return UIAction(title: shown.title, image: icon(shown), attributes: attributes) { [weak self] _ in
                    guard let self = self else { return }
                    if AuviousConferenceSDK.sharedInstance.sharingMyScreen {
                        self.stopScreenShareButtonPressed(self)
                    } else {
                        self.screenShareButtonPressed(self)
                    }
                }
            default:
                return nil
            }
        }
    }
    
    //Terminates the conference
    @objc internal func hangupButtonPressed(_ sender: Any) {
        sdkLog("hangupButtonPressed", log: Log.conferenceUI, type: .debug)
        selectionFeedbackGenerator.impactOccurred()
        endCobrowseWithCall(.customerEnded)
        tearDownArPointer()
        
        AuviousConferenceSDK.sharedInstance.leaveConference(conferenceId: currentConference.id, onSuccess: {
            sdkLog("Left conference", log: Log.conferenceUI, type: .debug)
            self.delegate?.onConferenceSuccess()

        }, onFailure: {(error) in
            self.handleError(error)
        })
    }
    
    //Toggles front/rear cam
    @objc internal func camSwitchButtonPressed(_ sender: Any) {
        guard !isArPointerOnOurCamera else { return }
        selectionFeedbackGenerator.impactOccurred()
        AuviousConferenceSDK.sharedInstance.switchCamera()
    }
    
    //Toggles audio routing to speaker/earpiece
    @objc internal func speakerButtonPressed(_ sender: Any) {
        selectionFeedbackGenerator.impactOccurred()
        
        // Get the button - either from sender or from buttonContainerView
        let button: ConferenceButton
        if let senderButton = sender as? ConferenceButton {
            button = senderButton
        } else {
            button = buttonContainerView.speakerButton
        }
        
        if button.type == .speakerON {
            button.type = .speakerOFF
            prefersSpeaker = false
            let _ = AuviousConferenceSDK.sharedInstance.changeAudioRoot(toSpeaker: false)
        } else {
            button.type = .speakerON
            prefersSpeaker = true
            let _ = AuviousConferenceSDK.sharedInstance.changeAudioRoot(toSpeaker: true)
        }
    }

    // Keeps prefersSpeaker in sync when the system changes the audio route
    // (e.g. Bluetooth device removed → iOS switches to speaker, or the user
    // picks an output from the system audio-route picker popup).
    @objc private func audioRouteChanged(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // Device plugged/unplugged — update to reflect actual route
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            prefersSpeaker = outputs.contains { $0.portType == .builtInSpeaker }
        default:
            // .override is fired by our own changeAudioRoot calls and by
            // checkCurrentAudioRoute() — ignore to avoid corrupting prefersSpeaker
            break
        }
    }

    //Toggles video stream
    @objc internal func cameraButtonPressed(_ sender: Any) {
        guard let localStreamId = localStreamId, !isArPointerOnOurCamera else {
            return
        }
        
        selectionFeedbackGenerator.impactOccurred()
        
        let button = sender as! ConferenceButton
        
        // open camera
        if button.type == .camDisabled {
            button.type = .camEnabled
            localView.videoStreamAdded()
            // re-enable switch cam
            buttonContainerView.cameraSwitchButton.type = .camSwitch
            
            if localStreamType == .mic {
                // mic is open, we need to unpublish the stream and publish a micAndCam
                republishLocalStreamAsMicAndCam(replacing: localStreamId)
                
            } else {
                AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .remove, type: .video, onSuccess: {

                    AuviousNotification.shared.show(.cameraOn)

                }, onFailure: { [weak self] error in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        button.type = .camDisabled
                        self.localView.videoStreamRemoved()
                        self.buttonContainerView.cameraSwitchButton.type = .camSwitchDisabled
                    }
                })
            }
            
        } else {
            // close camera
            button.type = .camDisabled
            localView.videoStreamRemoved()
            buttonContainerView.cameraSwitchButton.type = .camSwitchDisabled
            
            AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .set, type: .video, onSuccess: {
                AuviousNotification.shared.show(.cameraOff)
            }, onFailure: { [weak self] error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    button.type = .camEnabled
                    self.localView.videoStreamAdded()
                    self.buttonContainerView.cameraSwitchButton.type = .camSwitch
                }
            })
        }
    }
    
    //Toggles audio stream
    @objc internal func micButtonPressed(_ sender: Any) {
        guard let localStreamId = localStreamId else {
            return
        }
        
        selectionFeedbackGenerator.impactOccurred()
        let button = sender as! ConferenceButton
        
        // open microphone
        if button.type == .micDisabled {
            button.type = .micEnabled
            pipMuteButton.type = .micEnabled
            localView.audioStreamAdded()
            
            if localStreamType == .cam {
                // cam is open, we need to unpublish and publish a micAndCam stream
                republishLocalStreamAsMicAndCam(replacing: localStreamId)
                
            } else {
                AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .remove, type: .audio, onSuccess: {
                    AuviousNotification.shared.show(.microphoneOn)

                }, onFailure: { [weak self] error in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        button.type = .micDisabled
                        self.pipMuteButton.type = .micDisabled
                        self.localView.audioStreamRemoved(screenMode: self.screenMode)
                    }
                })
            }
            
        } else {
            // close microphone
            button.type = .micDisabled
            pipMuteButton.type = .micDisabled
            localView.audioStreamRemoved(screenMode: screenMode)
            
            AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .set, type: .audio, onSuccess: {
                AuviousNotification.shared.show(.microphoneOff)

            }, onFailure: { [weak self] error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    button.type = .micEnabled
                    self.pipMuteButton.type = .micEnabled
                    self.localView.audioStreamAdded()
                }
            })
        }
    }
    
    @objc internal func pipMicButtonPressed(_ sender: Any) {
        guard let localStreamId = localStreamId else {
            return
        }
        
        selectionFeedbackGenerator.impactOccurred()
        let button = sender as! PIPButton
        
        // open microphone
        if button.type == .micDisabled {
            button.type = .micEnabled
            buttonContainerView.micButton.type = .micEnabled
            localView.audioStreamAdded()
            
            if localStreamType == .cam {
                // cam is open, we need to unpublish and publish a micAndCam stream
                republishLocalStreamAsMicAndCam(replacing: localStreamId)
                
            } else {
                AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .remove, type: .audio, onSuccess: {

                    //Don't show notification in PIP mode
                    //AuviousNotification.shared.show(.microphoneOn)

                }, onFailure: { [weak self] error in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        button.type = .micDisabled
                        self.buttonContainerView.micButton.type = .micDisabled
                        self.localView.audioStreamRemoved(screenMode: self.screenMode)
                    }
                })
            }
            
        } else {
            // close microphone
            button.type = .micDisabled
            buttonContainerView.micButton.type = .micDisabled
            localView.audioStreamRemoved(screenMode: screenMode)
            
            AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .set, type: .audio, onSuccess: {

                //Don't show notification in PIP mode
//                AuviousNotification.shared.show(.microphoneOff)

            }, onFailure: { [weak self] error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    button.type = .micEnabled
                    self.buttonContainerView.micButton.type = .micEnabled
                    self.localView.audioStreamAdded()
                }
            })
        }
    }
}

