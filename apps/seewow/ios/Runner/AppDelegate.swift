import Flutter
import UIKit
import Security
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeBridge: IOSNativeBridge?
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
    }
  }
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
