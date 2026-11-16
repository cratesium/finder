import AVFoundation
import Flutter
import QuickLook
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FinderIosPlugin") {
      FinderIosPlugin.register(with: registrar)
    }
  }
}

/// iOS side of the `finder/ios` channel (lib/services/ios/ios_bridge.dart).
///
/// iOS apps can't run yt-dlp or FFmpeg, so:
/// * `mux` joins the separately downloaded H.264 video and AAC audio with
///   AVFoundation (passthrough export: no re-encoding, source quality kept);
/// * `beginBackgroundTask`/`endBackgroundTask` let an active download keep
///   running for the short time iOS allows after the app is backgrounded;
/// * `preview`/`share`/`openInFiles` expose downloads through system UI.
final class FinderIosPlugin: NSObject, FlutterPlugin, QLPreviewControllerDataSource {
  private var previewURL: URL?
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "finder/ios", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FinderIosPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "mux":
      guard let video = args["video"] as? String, let audio = args["audio"] as? String,
            let output = args["output"] as? String else {
        return result(FlutterError(code: "args", message: "video, audio and output are required", details: nil))
      }
      mux(video: URL(fileURLWithPath: video), audio: URL(fileURLWithPath: audio),
          output: URL(fileURLWithPath: output), result: result)
    case "beginBackgroundTask":
      result(beginBackgroundTask(name: args["name"] as? String ?? "download"))
    case "endBackgroundTask":
      if let id = args["id"] as? Int { endBackgroundTask(id) }
      result(nil)
    case "preview":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: nil, details: nil)) }
      preview(URL(fileURLWithPath: path), result: result)
    case "share":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: nil, details: nil)) }
      share(URL(fileURLWithPath: path), result: result)
    case "openInFiles":
      guard let path = args["path"] as? String else { return result(false) }
      openInFiles(path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Muxing

  private func mux(video: URL, audio: URL, output: URL, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      func fail(_ message: String) {
        DispatchQueue.main.async { result(FlutterError(code: "mux", message: message, details: nil)) }
      }
      let videoAsset = AVURLAsset(url: video)
      let audioAsset = AVURLAsset(url: audio)
      guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else { return fail("no video track") }
      guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first else { return fail("no audio track") }

      let composition = AVMutableComposition()
      guard let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        return fail("couldn't create composition tracks")
      }
      let videoRange = CMTimeRange(start: .zero, duration: videoAsset.duration)
      let audioRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(audioAsset.duration, videoAsset.duration))
      do {
        try v.insertTimeRange(videoRange, of: videoTrack, at: .zero)
        try a.insertTimeRange(audioRange, of: audioTrack, at: .zero)
      } catch {
        return fail("insert failed: \(error.localizedDescription)")
      }
      v.preferredTransform = videoTrack.preferredTransform

      try? FileManager.default.removeItem(at: output)
      guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
        return fail("passthrough export unavailable")
      }
      export.outputURL = output
      export.outputFileType = .mp4
      export.shouldOptimizeForNetworkUse = true
      let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
      let shortSide = Int(min(abs(size.width), abs(size.height)))
      export.exportAsynchronously {
        DispatchQueue.main.async {
          switch export.status {
          case .completed:
            result(shortSide)
          default:
            try? FileManager.default.removeItem(at: output)
            result(FlutterError(code: "mux",
                                message: export.error?.localizedDescription ?? "export ended with status \(export.status.rawValue)",
                                details: nil))
          }
        }
      }
    }
  }

  // MARK: - Background execution

  private func beginBackgroundTask(name: String) -> Int {
    var id: UIBackgroundTaskIdentifier = .invalid
    id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      // Time is up: iOS suspends the app. The download stops and resumes
      // (HTTP range) when the app returns to the foreground.
      self?.endBackgroundTask(id.rawValue)
    }
    if id != .invalid { backgroundTasks[id.rawValue] = id }
    return id.rawValue
  }

  private func endBackgroundTask(_ raw: Int) {
    guard let id = backgroundTasks.removeValue(forKey: raw) else { return }
    UIApplication.shared.endBackgroundTask(id)
  }

  // MARK: - Files, Quick Look and sharing

  private func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private func preview(_ url: URL, result: @escaping FlutterResult) {
    guard let top = topController() else { return result(FlutterError(code: "ui", message: "no window", details: nil)) }
    previewURL = url
    let controller = QLPreviewController()
    controller.dataSource = self
    top.present(controller, animated: true)
    result(nil)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    (previewURL ?? URL(fileURLWithPath: "/")) as NSURL
  }

  private func share(_ url: URL, result: @escaping FlutterResult) {
    guard let top = topController() else { return result(FlutterError(code: "ui", message: "no window", details: nil)) }
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = controller.popoverPresentationController {
      // iPad: anchor the sheet to the middle of the screen.
      popover.sourceView = top.view
      popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    top.present(controller, animated: true)
    result(nil)
  }

  /// `shareddocuments://<path>` opens the Files app at a folder inside this
  /// app's Documents (exposed by UIFileSharingEnabled).
  private func openInFiles(_ path: String, result: @escaping FlutterResult) {
    var components = URLComponents()
    components.scheme = "shareddocuments"
    components.path = path
    guard let url = components.url else { return result(false) }
    UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
  }
}
