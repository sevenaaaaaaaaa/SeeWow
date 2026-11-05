import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    NativeBridge.shared.register(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
    self.minSize = NSSize(width: 900, height: 640)
    self.title = "SeeWow"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor.black
    self.isMovableByWindowBackground = true
    self.isRestorable = false
    self.setFrameAutosaveName("")
    DispatchQueue.main.async { [weak self] in
      guard let self, let screen = self.screen ?? NSScreen.main else { return }
      let visible = screen.visibleFrame
      var size = NSSize(width: min(1440, visible.width - 96), height: min(900, visible.height - 96))
      if let spec = ProcessInfo.processInfo.environment["SEEWOW_WINDOW"] {
        let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
        if parts.count == 2, parts[0] >= 360, parts[1] >= 360 {
          size = NSSize(width: parts[0], height: parts[1])
        }
      }
      let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
      self.setFrame(NSRect(origin: origin, size: size), display: true)
    }
  }
}

/// Native side of SeeWow: SMB mounting through NetFS and Keychain secrets.
///
/// Both live in this file so the Flutter runner target needs no project changes.
final class NativeBridge: NSObject {
  static let shared = NativeBridge()
  private let service = "com.seewow.seewow"
  private var netfsHandle: UnsafeMutableRawPointer?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "seewow/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "secret.read":
      result(secretRead(args["key"] as? String ?? ""))
    case "secret.write":
      let key = args["key"] as? String ?? ""
      let value = args["value"] as? String ?? ""
      result(key.isEmpty ? false : secretWrite(key: key, value: value))
    case "secret.delete":
      result(secretDelete(args["key"] as? String ?? ""))
    case "smb.mount":
      do {
        result(try smbMount(args))
      } catch let error as BridgeError {
        result(FlutterError(code: error.code, message: error.message, details: error.status))
      } catch {
        result(FlutterError(code: "mount_failed", message: error.localizedDescription, details: nil))
      }
    case "smb.unmount":
      // Shares are mounted inside Application Support; leaving them is harmless
      // and remounting reuses the same mount point.
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Keychain

  private func keychainQuery(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: key]
  }

  private func secretWrite(key: String, value: String) -> Bool {
    SecItemDelete(keychainQuery(key) as CFDictionary)
    var attrs = keychainQuery(key)
    attrs[kSecValueData as String] = Data(value.utf8)
    attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
  }

  private func secretRead(_ key: String) -> String? {
    guard !key.isEmpty else { return nil }
    var query = keychainQuery(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func secretDelete(_ key: String) -> Bool {
    guard !key.isEmpty else { return false }
    return SecItemDelete(keychainQuery(key) as CFDictionary) == errSecSuccess
  }

  // MARK: - SMB (NetFS)

  private struct BridgeError: Error {
    let code: String
    let message: String
    var status: Int?
  }

  private typealias MountFn = @convention(c) (CFURL?, CFURL?, CFString?, CFString?, CFMutableDictionary?, CFMutableDictionary?, UnsafeMutablePointer<CFArray?>?) -> Int32

  private func loadNetFS() -> MountFn? {
    if let fn = mountFn { return fn }
    guard let handle = dlopen("/System/Library/Frameworks/NetFS.framework/NetFS", RTLD_NOW),
          let sym = dlsym(handle, "NetFSMountURLSync") else { return nil }
    netfsHandle = handle
    let fn = unsafeBitCast(sym, to: MountFn.self)
    mountFn = fn
    return fn
  }
  private var mountFn: MountFn?

  private func smbMount(_ args: [String: Any]) throws -> String {
    guard let host = (args["host"] as? String)?.trimmingCharacters(in: .whitespaces), !host.isEmpty else {
      throw BridgeError(code: "invalid", message: "缺少主机地址", status: nil)
    }
    guard let share = (args["share"] as? String)?.trimmingCharacters(in: .whitespaces), !share.isEmpty else {
      throw BridgeError(code: "invalid", message: "缺少共享名", status: nil)
    }
    let username = args["username"] as? String ?? ""
    let password = args["password"] as? String ?? ""
    let subpath = args["subpath"] as? String ?? ""
    guard let mountPath = args["mountPoint"] as? String, !mountPath.isEmpty else {
      throw BridgeError(code: "invalid", message: "缺少挂载点", status: nil)
    }
    let fm = FileManager.default
    try? fm.createDirectory(atPath: mountPath, withIntermediateDirectories: true)

    let existing = (try? fm.contentsOfDirectory(atPath: mountPath)) ?? []
    if !existing.isEmpty {
      return join(subpath, to: mountPath)
    }

    guard let fn = loadNetFS() else {
      throw BridgeError(code: "unsupported", message: "当前系统不支持 SMB 挂载", status: nil)
    }
    guard let url = URL(string: "smb://" + (host + "/" + share).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else {
      throw BridgeError(code: "invalid", message: "SMB 地址格式不正确", status: nil)
    }
    var mountpoints: CFArray?
    let point = URL(fileURLWithPath: mountPath)
    let status = fn(url as CFURL, point as CFURL, username as CFString, password as CFString, nil, nil, &mountpoints)
    if status != 0 {
      let authCodes: Set<Int32> = [-5995, -5996, -5997, -6003, -6004]
      throw BridgeError(
        code: authCodes.contains(status) ? "auth" : "mount_failed",
        message: authCodes.contains(status) ? "连接被拒绝：请检查账号、密码或共享权限" : "SMB 挂载失败（错误码 \(status)）",
        status: Int(status)
      )
    }
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      let contents = (try? fm.contentsOfDirectory(atPath: mountPath)) ?? []
      if !contents.isEmpty { break }
      Thread.sleep(forTimeInterval: 0.2)
    }
    return join(subpath, to: mountPath)
  }

  private func join(_ subpath: String, to mountPath: String) -> String {
    let trimmed = subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return trimmed.isEmpty ? mountPath : mountPath + "/" + trimmed
  }
}
