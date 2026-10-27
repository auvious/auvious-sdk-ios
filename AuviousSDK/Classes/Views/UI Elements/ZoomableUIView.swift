//
//  ZoomableUIView.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 31/10/20.
//

import UIKit

public struct ZoomableViewOptions {
   var minZoom: CGFloat
   var maxZoom: CGFloat

   public init(minZoom: CGFloat, maxZoom: CGFloat) {
      self.minZoom = minZoom
      self.maxZoom = maxZoom
   }
}

public protocol ZoomableUIView {
   func reset()
   func viewForZooming() -> UIView
   func optionsForZooming() -> ZoomableViewOptions
   /// Views zoomed and panned together with viewForZooming (e.g. drawings over the video), centered on the same point
   func viewsZoomingAlong() -> [UIView]
   /// False while touches belong to something else (e.g. drawing), so the zoom gestures don't start
   func canZoom() -> Bool
   /// Where the content is drawn unzoomed, in this view's coordinates (e.g. an aspect fit video inside viewForZooming)
   func contentRectForZooming() -> CGRect
   /// Called after every zoom or pan
   func zoomDidChange()
}

public extension ZoomableUIView {
   func viewsZoomingAlong() -> [UIView] {
      return []
   }

   func canZoom() -> Bool {
      return true
   }
   
   func contentRectForZooming() -> CGRect {
      let view = viewForZooming()
      return CGRect(x: view.center.x - view.bounds.width / 2, y: view.center.y - view.bounds.height / 2,
                    width: view.bounds.width, height: view.bounds.height)
   }
   
   func zoomDidChange() {
   }
}

private var zoomHandlerKey: UInt8 = 0

extension ZoomableUIView where Self: UIView {

   public func reset() {
      zoomHandler?.setZoom(scale: optionsForZooming().minZoom, offset: .zero, animated: true)
   }

   public func setZoomable(_ zoomable: Bool) {
      ([viewForZooming()] + viewsZoomingAlong()).forEach { $0.transform = .identity }
      isUserInteractionEnabled = zoomable
      gestureRecognizers = nil
      layer.masksToBounds = zoomable

      zoomHandler = zoomable ? ZoomHandler(zoomable: self) : nil
      zoomHandler?.recognizers.forEach { addGestureRecognizer($0) }
   }

   /// Keeps the zoomed view covering this view after its size changes
   public func clampZoom() {
      guard let handler = zoomHandler else { return }
      handler.setZoom(scale: handler.scale, offset: handler.offset, animated: false)
   }

   fileprivate var zoomHandler: ZoomHandler? {
      get { objc_getAssociatedObject(self, &zoomHandlerKey) as? ZoomHandler }
      set { objc_setAssociatedObject(self, &zoomHandlerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
   }

}

/// Pinch to zoom, pan while zoomed, double tap to zoom back out. The content never gets smaller than unzoomed.
/// Along an axis where the zoomed content is larger than the zoomable view it always covers it, otherwise it stays centered.
fileprivate final class ZoomHandler: NSObject, UIGestureRecognizerDelegate {

   private weak var zoomable: (UIView & ZoomableUIView)?

   private let pinch = UIPinchGestureRecognizer()
   //One finger; two fingers pan through the pinch
   private let pan = UIPanGestureRecognizer()
   private let doubleTap = UITapGestureRecognizer()

   var recognizers: [UIGestureRecognizer] {
      return [pinch, pan, doubleTap]
   }

   //Scale and offset when the pinch began, and the pinch's centre then (from the zoomed view's centre)
   private var pinchStart: (scale: CGFloat, offset: CGPoint, location: CGPoint)?

   init(zoomable: UIView & ZoomableUIView) {
      self.zoomable = zoomable
      super.init()

      pinch.addTarget(self, action: #selector(pinched(_:)))
      pan.addTarget(self, action: #selector(panned(_:)))
      doubleTap.addTarget(self, action: #selector(doubleTapped))

      pan.maximumNumberOfTouches = 1
      //Nothing to pan until zoomed in
      pan.isEnabled = false
      doubleTap.numberOfTapsRequired = 2

      pinch.delegate = self
      pan.delegate = self
   }

   var scale: CGFloat {
      return zoomable?.viewForZooming().transform.a ?? 1
   }

   var offset: CGPoint {
      guard let transform = zoomable?.viewForZooming().transform else { return .zero }
      return CGPoint(x: transform.tx, y: transform.ty)
   }

   func setZoom(scale: CGFloat, offset: CGPoint, animated: Bool) {
      guard let zoomable = zoomable else { return }
      let scale = clamped(scale)
      let content = zoomable.contentRectForZooming()
      //The transform scales around the zoomed view's centre
      let center = zoomable.viewForZooming().center
      
      func clampedOffset(_ offset: CGFloat, contentMin: CGFloat, contentMax: CGFloat, center: CGFloat, length: CGFloat) -> CGFloat {
         let zoomedMin = center + (contentMin - center) * scale
         let zoomedMax = center + (contentMax - center) * scale
         guard zoomedMax - zoomedMin > length else { return 0 }
         //No further than uncovering an edge
         return min(max(offset, length - zoomedMax), -zoomedMin)
      }
      
      let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                        tx: clampedOffset(offset.x, contentMin: content.minX, contentMax: content.maxX, center: center.x, length: zoomable.bounds.width),
                                        ty: clampedOffset(offset.y, contentMin: content.minY, contentMax: content.maxY, center: center.y, length: zoomable.bounds.height))

      pan.isEnabled = scale > zoomable.optionsForZooming().minZoom

      let views = [zoomable.viewForZooming()] + zoomable.viewsZoomingAlong()
      if animated {
         UIView.animate(withDuration: 0.3) {
            views.forEach { $0.transform = transform }
         }
      } else {
         views.forEach { $0.transform = transform }
      }
      zoomable.zoomDidChange()
   }

   private func clamped(_ scale: CGFloat) -> CGFloat {
      guard let options = zoomable?.optionsForZooming() else { return scale }
      return min(max(scale, options.minZoom), options.maxZoom)
   }

   /// Where the gesture is, from the zoomed view's centre (where the transform scales around)
   private func location(of gesture: UIGestureRecognizer) -> CGPoint {
      guard let zoomable = zoomable else { return .zero }
      let location = gesture.location(in: zoomable)
      let center = zoomable.viewForZooming().center
      return CGPoint(x: location.x - center.x, y: location.y - center.y)
   }

   @objc private func pinched(_ pinch: UIPinchGestureRecognizer) {
      switch pinch.state {
      case .began:
         pinchStart = (scale, offset, location(of: pinch))
      case .changed:
         guard let start = pinchStart else { return }
         //The point of the content that was under the fingers stays under them, as they spread and move
         let newScale = clamped(start.scale * pinch.scale)
         let contentPoint = CGPoint(x: (start.location.x - start.offset.x) / start.scale,
                                    y: (start.location.y - start.offset.y) / start.scale)
         let current = location(of: pinch)
         setZoom(scale: newScale,
                 offset: CGPoint(x: current.x - newScale * contentPoint.x, y: current.y - newScale * contentPoint.y),
                 animated: false)
      default:
         pinchStart = nil
      }
   }

   @objc private func panned(_ pan: UIPanGestureRecognizer) {
      guard let zoomable = zoomable else { return }
      let translation = pan.translation(in: zoomable)
      pan.setTranslation(.zero, in: zoomable)
      //While pinching, the pinch moves the content
      guard pinchStart == nil else { return }
      setZoom(scale: scale, offset: CGPoint(x: offset.x + translation.x, y: offset.y + translation.y), animated: false)
   }

   @objc private func doubleTapped() {
      zoomable?.reset()
   }

   //MARK: UIGestureRecognizerDelegate

   func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      return zoomable?.canZoom() ?? false
   }

   func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      return otherGestureRecognizer === pinch || otherGestureRecognizer === pan
   }

}
