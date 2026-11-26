import Flutter
import UIKit
import Security
import UniformTypeIdentifiers
import AVKit
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeBridge: IOSNativeBridge?
  private var playbackBridge: IOSPlaybackBridge?
  private var voiceBridge: IOSVoiceBridge?
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
      voiceBridge = IOSVoiceBridge(registrar: registrar)
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
  private var pipVolume: Float = 1
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
  /// 画面要真的贴在一个已上屏的窗口上，PiP 才可能成立。scene 架构下
  /// registrar.viewController 有时不在窗口层级里，所以再退一步找 key window。
  private var hostView: UIView? {
    if let view = presenter?.view, view.window != nil { return view }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
        let view = window.rootViewController?.view {
        return view
      }
    }
    return presenter?.view
  }

  private func startPip(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard AVPictureInPictureController.isPictureInPictureSupported(), let view = hostView else {
      NSLog("[SeeWow] pip unsupported: supported=\(AVPictureInPictureController.isPictureInPictureSupported()) host=\(hostView != nil)")
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
    // PiP 属于后台音频场景：会话没立起来时，PiP 里会没声音甚至起不来。
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch { NSLog("[SeeWow] pip audio session failed: \(error)") }
    requestID += 1; let ticket = requestID
    pending = result; wantedPlaying = args["playing"] as? Bool == true
    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    pipVolume = approvedVolume(args)
    newPlayer.volume = pipVolume
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
              // 先静音播起来：PiP 只能从正在播的画面起，声音等主播放器
              // 让出来之后（didStart 里）再放开，避免两路同时响。
              newPlayer.isMuted = true
              newPlayer.play()
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
      NSLog("[SeeWow] pip timeout: status=\(String(describing: item.status.rawValue)) possible=\(controller.isPictureInPicturePossible)")
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
    // 主播放器在收到 pip.mode 后会自己停，这里再放开声音。
    player?.isMuted = false
    player?.volume = pipVolume
    if wantedPlaying { player?.play() } else { player?.pause() }
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

/// 自动解说的 iOS 语音后端。桌面端走 `say` / SAPI / espeak 子进程，iOS 沙箱
/// 不允许 spawn 进程，所以用 AVSpeechSynthesizer 的离线渲染把解说词写成
/// 16 位 PCM WAV——与桌面 `say + afconvert` 交给播放器的产物等价。
/// 没有系统语音时如实报告不可用，不回落到任何在线服务。
final class IOSVoiceBridge: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private let synthesizer = AVSpeechSynthesizer()
  private var pending: FlutterResult?
  private var sink: AVAudioFile?
  private var converter: AVAudioConverter?
  private var outputPath: URL?
  private var watchdog: DispatchWorkItem?

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "seewow/voice", binaryMessenger: registrar.messenger())
    super.init()
    synthesizer.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  deinit {
    watchdog?.cancel()
    sink = nil
    synthesizer.stopSpeaking(at: .immediate)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "tts.probe":
      let voices = AVSpeechSynthesisVoice.speechVoices()
      result(voices.isEmpty ? nil : voices.count)
    case "tts.synthesize": synthesize(args, result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func synthesize(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "上一段解说还在合成", details: nil)); return
    }
    guard let text = args["text"] as? String,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(nil); return
    }
    guard let path = args["path"] as? String, path.hasSuffix(".wav") else {
      result(FlutterError(code: "invalid", message: "解说音频路径无效", details: nil)); return
    }
    let utterance = AVSpeechUtterance(string: text)
    // 语言提示与桌面 espeak 的 _espeakVoice 映射同源：zh / ja / en，缺省跟系统。
    if let language = args["language"] as? String, !language.isEmpty,
      AVSpeechSynthesisVoice(language: language) != nil {
      utterance.voice = AVSpeechSynthesisVoice(language: language)
    }
    utterance.postUtteranceDelay = 0.05
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    pending = result
    outputPath = url
    // 120 秒看门狗：渲染卡死时如实报错，不让 Dart 侧永远等一个不会来的回调。
    let timeout = DispatchWorkItem { [weak self] in self?.fail("系统语音合成超时，请重试") }
    watchdog = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
    synthesizer.write(utterance) { [weak self] buffer in
      DispatchQueue.main.async { self?.sink(buffer) }
    }
  }

  /// 逐缓冲写入。目标固定 16 位单声道 WAV（与桌面 LEI16 一致）；源格式
  /// Float32 只有格式差异，用 AVAudioConverter 转换后落盘。
  private func sink(_ rawBuffer: AVAudioBuffer) {
    guard pending != nil, let pcm = rawBuffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
    if sink == nil {
      guard let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: pcm.format.sampleRate,
        channels: 1,
        interleaved: true),
        let url = outputPath,
        let output = try? AVAudioFile(
          forWriting: url,
          settings: target.settings,
          commonFormat: .pcmFormatInt16,
          interleaved: true),
        let bridge = AVAudioConverter(from: pcm.format, to: target) else {
        fail("无法创建解说音频文件"); return
      }
      sink = output
      converter = bridge
    }
    guard let converter, let sink else { return }
    let ratio = (converter.outputFormat.sampleRate / pcm.format.sampleRate).rounded(.up)
    let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 64
    guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
      fail("解说音频缓冲不足"); return
    }
    var delivered = false
    var convertError: NSError?
    let status = converter.convert(to: out, error: &convertError) { _, status in
      if delivered { status.pointee = .endOfStream; return nil }
      delivered = true
      status.pointee = .haveData
      return pcm
    }
    if status == .error || convertError != nil {
      fail("系统语音合成失败：\(convertError?.localizedDescription ?? "转换错误")"); return
    }
    if out.frameLength > 0 {
      do { try sink.write(from: out) } catch {
        fail("解说音频写入失败：\(error.localizedDescription)"); return
      }
    }
  }

  private func finish() {
    watchdog?.cancel(); watchdog = nil
    let callback = pending; pending = nil
    let url = outputPath
    let frames = sink?.length
    sink = nil; converter = nil; outputPath = nil
    guard let callback, let url else { return }
    guard (frames ?? 0) > 128,
      let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
      size >= 128 else {
      try? FileManager.default.removeItem(at: url)
      callback(FlutterError(code: "tts", message: "系统语音没有生成音频", details: nil)); return
    }
    callback(url.path)
  }

  private func fail(_ message: String) {
    watchdog?.cancel(); watchdog = nil
    let callback = pending; pending = nil
    let url = outputPath
    sink = nil; converter = nil; outputPath = nil
    if let url { try? FileManager.default.removeItem(at: url) }
    callback?(FlutterError(code: "tts", message: message, details: nil))
  }

  // MARK: AVSpeechSynthesizerDelegate

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    finish()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    fail("系统语音合成被取消")
  }
}
