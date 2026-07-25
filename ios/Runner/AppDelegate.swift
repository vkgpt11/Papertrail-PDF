import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.papertrail.pdfreader/open_pdf"
  private var channel: FlutterMethodChannel?
  private var pendingPdf: [String: String]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      channel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel?.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getInitialPdf" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(self?.pendingPdf)
        self?.pendingPdf = nil
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.pathExtension.lowercased() == "pdf",
          let pdf = cachePdf(url) else {
      return super.application(app, open: url, options: options)
    }
    pendingPdf = pdf
    channel?.invokeMethod("openPdf", arguments: pdf)
    return true
  }

  private func cachePdf(_ url: URL) -> [String: String]? {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let target = FileManager.default.temporaryDirectory
        .appendingPathComponent("incoming-\(Int(Date().timeIntervalSince1970 * 1000)).pdf")
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.copyItem(at: url, to: target)
      return ["path": target.path, "name": url.lastPathComponent]
    } catch {
      return nil
    }
  }
}
