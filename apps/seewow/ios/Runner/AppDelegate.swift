import Flutter
import UIKit
import Security
import UniformTypeIdentifiers
import AVKit
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeBridge: IOSNativeBridge?
  private var playbackBridge: IOSPlaybackBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SeeWowNative") {
      nativeBridge = IOSNativeBridge(registrar: registrar)
      playbackBridge = IOSPlaybackBridge(registrar: registrar)
    }
  }
}

/// System background audio and AVKit PiP. The normal in-app renderer stays libmpv.
final class IOSPlaybackBridge: NSObject, AVPictureInPictureControllerDelegate {
  private let channel: FlutterMethodChannel
  private weak var presenter: UIViewController?
  private var player: AVPlayer?
  private var host: UIView?
  private var layer: AVPlayerLayer?
  private var pip: AVPictureInPictureController?
  private var readiness: NSKeyValueObservation?
  private var possibility: NSKeyValueObservation?
  private var pending: FlutterResult?
  private var wantedPlaying = false
  private var backgroundEnabled = false
  private var routeObserver: NSObjectProtocol?
  private var requestID = 0
  private var commands: [(MPRemoteCommand, Any)] = []

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "seewow/playback", binaryMessenger: registrar.messenger())
    presenter = registrar.viewController
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] _ in
        guard let self else { return }
        // PiP has its own AVPlayer; silence it before asking Dart to re-evaluate.
        self.player?.volume = 0
        self.channel.invokeMethod("audio.routeChanged", arguments: self.audioRoute())
      }
  }
  deinit { if let observer = routeObserver { NotificationCenter.default.removeObserver(observer) } }
  private func audioRoute() -> [String: String] {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    let route: String
    if !outputs.isEmpty && outputs.allSatisfy({ $0.portType == .headphones }) { route = "headphones" }
    else if !outputs.isEmpty && outputs.allSatisfy({ $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver }) { route = "speaker" }
    else { route = "unknown" } // A2DP, AirPlay, HDMI and USB may be shared outputs.
    return ["route": route, "token": outputs.map { "\($0.uid):\($0.portType.rawValue)" }.joined(separator: ",")]
  }
  private func approvedVolume(_ args: [String: Any]) -> Float {
    let current = audioRoute()
    guard args["routeToken"] as? String == current["token"],
      !(args["sensitive"] as? Bool == true && current["route"] != "headphones") else { return 0 }
    return Float(max(0, min(1, args["volume"] as? Double ?? 0)))
  }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "audio.route": result(audioRoute())
    case "audio.volume": player?.volume = approvedVolume(args); result(true)
    case "background":
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
        backgroundEnabled = args["enabled"] as? Bool == true
        if backgroundEnabled { installCommands() } else { clearCommands() }
        result(true)
      } catch { result(FlutterError(code: "audio", message: "系统音频会话未就绪", details: nil)) }
    case "update":
      if player == nil {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: args["title"] as? String ?? "SeeWow",
          MPMediaItemPropertyPlaybackDuration: (args["duration"] as? Double ?? 0) / 1000,
          MPNowPlayingInfoPropertyElapsedPlaybackTime: (args["position"] as? Double ?? 0) / 1000,
          MPNowPlayingInfoPropertyPlaybackRate: args["playing"] as? Bool == true ? 1.0 : 0.0]
      }
      result(true)
    case "pip": startPip(args, result)
    case "pip.stop": pip?.stopPictureInPicture(); result(true)
    case "end":
      requestID += 1
      pending?(false); pending = nil
      cleanup(); clearCommands(); MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      result(true)
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func installCommands() {
    if !commands.isEmpty { return }
    let center = MPRemoteCommandCenter.shared()
    for (command, action) in [(center.playCommand, "play"), (center.pauseCommand, "pause"), (center.togglePlayPauseCommand, "toggle"), (center.stopCommand, "stop")] {
      let token = command.addTarget { [weak self] _ in
        DispatchQueue.main.async {
          guard let self else { return }
          if let player = self.player {
            switch action { case "play": player.play(); case "pause": player.pause(); case "toggle": player.rate == 0 ? player.play() : player.pause(); default: self.pip?.stopPictureInPicture() }
          } else { self.channel.invokeMethod("action", arguments: ["action": action]) }
        }
        return .success
      }
      commands.append((command, token))
    }
  }
  private func clearCommands() { for (command, token) in commands { command.removeTarget(token) }; commands.removeAll() }
  private func startPip(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard AVPictureInPictureController.isPictureInPictureSupported(), let view = presenter?.view else {
      result(FlutterError(code: "pip", message: "当前设备不支持系统画中画", details: nil)); return
    }
    guard (args["headers"] as? [String: String] ?? [:]).isEmpty else {
      result(FlutterError(code: "pip", message: "iOS 系统画中画暂不接收自定义认证头，可使用已下载的本机文件", details: nil)); return
    }
    guard let raw = args["url"] as? String else { result(false); return }
    let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : URL(string: raw)
    guard let url, ["file", "http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil else { result(false); return }
    if pending != nil || pip?.isPictureInPictureActive == true { result(false); return }
    cleanup()
    requestID += 1; let ticket = requestID
    pending = result; wantedPlaying = args["playing"] as? Bool == true
    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    newPlayer.volume = approvedVolume(args)
    player = newPlayer
    let holder = UIView(frame: CGRect(x: max(0, view.bounds.width - 180), y: max(0, view.bounds.height - 120), width: 176, height: 99))
    holder.backgroundColor = .black; holder.isUserInteractionEnabled = false
    let videoLayer = AVPlayerLayer(player: newPlayer); videoLayer.frame = holder.bounds; holder.layer.addSublayer(videoLayer)
    view.addSubview(holder); host = holder; layer = videoLayer
    guard let controller = AVPictureInPictureController(playerLayer: videoLayer) else { fail("系统画中画控制器不可用"); return }
    pip = controller; controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = false
    let seconds = (args["position"] as? Double ?? 0) / 1000
    readiness = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self, self.requestID == ticket, self.pending != nil else { return }
        if item.status == .failed { self.fail("此媒体格式或连接不能由 iOS 系统画中画播放，可继续使用应用内播放器"); return }
        if item.status == .readyToPlay {
          self.readiness = nil
          newPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
              guard let self, self.requestID == ticket else { return }
              self.possibility = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
                DispatchQueue.main.async {
                  guard let self, self.requestID == ticket, self.pending != nil else { return }
                  if controller.isPictureInPicturePossible { self.possibility = nil; controller.startPictureInPicture() }
                }
              }
            }
          }
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard let self, self.requestID == ticket, self.pending != nil else { return }
      self.fail("画中画准备超时，请检查系统权限或媒体格式")
    }
  }
  private func fail(_ message: String) {
    let callback = pending; pending = nil; cleanup()
    callback?(FlutterError(code: "pip", message: message, details: nil))
  }
  private func cleanup() {
    readiness = nil; possibility = nil
    pip?.delegate = nil; pip?.stopPictureInPicture(); pip = nil
    player?.pause(); player = nil; layer?.removeFromSuperlayer(); layer = nil; host?.removeFromSuperview(); host = nil
  }
  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    host?.alpha = 0
    if wantedPlaying { player?.play() }
    pending?(true); pending = nil
    installCommands()
    channel.invokeMethod("pip.mode", arguments: ["active": true])
  }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) { fail("系统画中画启动失败，可继续在应用内播放") }
  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let seconds = player?.currentTime().seconds ?? 0, playing = (player?.rate ?? 0) != 0
    cleanup()
    if !backgroundEnabled { clearCommands() }
    channel.invokeMethod("pip.restore", arguments: ["position": seconds.isFinite ? seconds * 1000 : 0, "playing": playing])
  }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }
}

/// iOS credentials never fall back to a subprocess or a plaintext secrets file.
final class IOSNativeBridge: NSObject, UIDocumentPickerDelegate {
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private var folderResult: FlutterResult?
  private var folders: [String: URL] = [:]
  private let bookmarkKey = "SeeWow.mediaFolderBookmarks"
  private let service = "com.seewow.seewow"

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "seewow/native", binaryMessenger: registrar.messenger())
    super.init()
    restoreFolders()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  private func query(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: key]
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let key = args["key"] as? String ?? ""
    switch call.method {
    case "secret.read", "secret.write", "secret.delete":
      guard !key.isEmpty else { result(FlutterError(code: "invalid", message: "缺少凭据标识", details: nil)); return }
      var q = query(key)
      if call.method == "secret.read" {
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil); return }
        guard status == errSecSuccess else { failure(status, result); return }
        result((item as? Data).flatMap { String(data: $0, encoding: .utf8) })
      } else if call.method == "secret.write" {
        let data = Data((args["value"] as? String ?? "").utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          q[kSecValueData as String] = data
          q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          let added = SecItemAdd(q as CFDictionary, nil)
          if added == errSecSuccess { result(true) } else { failure(added, result) }
        } else if status == errSecSuccess { result(true) } else { failure(status, result) }
      } else {
        let status = SecItemDelete(q as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { result(true) } else { failure(status, result) }
      }
    case "folder.pick":
      guard folderResult == nil, let presenter = registrar.viewController else {
        result(FlutterError(code: "busy", message: "文件选择器尚未就绪", details: nil)); return
      }
      folderResult = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.delegate = self
      presenter.present(picker, animated: true)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func failure(_ status: OSStatus, _ result: FlutterResult) {
    result(FlutterError(code: "keychain", message: "无法访问 iOS 钥匙串，请解锁设备后重试", details: status))
  }

  private func restoreFolders() {
    let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] ?? [:]
    for (path, data) in bookmarks {
      var stale = false
      if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
         url.startAccessingSecurityScopedResource() {
        folders[path] = url
      }
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let callback = folderResult else { return }
    folderResult = nil
    guard let url = urls.first else { callback(nil); return }
    guard url.startAccessingSecurityScopedResource() else {
      callback(FlutterError(code: "access", message: "无法读取所选文件夹，请重新授权", details: nil)); return
    }
    do {
      let data = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
      var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] ?? [:]
      bookmarks[url.path] = data
      UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
      if folders[url.path] != nil { url.stopAccessingSecurityScopedResource() }
      else { folders[url.path] = url }
      callback(url.path)
    } catch {
      url.stopAccessingSecurityScopedResource()
      callback(FlutterError(code: "bookmark", message: "无法保存文件夹访问授权", details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    folderResult?(nil)
    folderResult = nil
  }

  deinit { for url in folders.values { url.stopAccessingSecurityScopedResource() } }
}
