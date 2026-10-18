import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 回收站里留存着用户「已删除」的照片原图，绝不能随 iCloud/iTunes 备份上传。
    // Application Support 默认仍会进备份，这里显式排除（与 Dart 侧 AppStorage 的根目录一致）。
    excludeAppDataFromBackup()
    // 兜底注册密钥通道：若引擎不是走隐式引擎路径创建，这里也能注册上
    if let registrar = registrar(forPlugin: "SecureKeyPlugin") {
      SecureKeyChannel.register(with: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func excludeAppDataFromBackup() {
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first else { return }
    let dataDir = appSupport.appendingPathComponent("knowpic", isDirectory: true)
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    var url = dataDir
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 偏好导出密钥通道：用插件注册表拿 messenger，不依赖 viewController 的创建时机
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SecureKeyPlugin") {
      SecureKeyChannel.register(with: registrar.messenger())
    }
  }
}

/// 偏好导出密钥的钥匙串存储。
/// 用 WhenUnlockedThisDeviceOnly：不进 iCloud/ iTunes 备份，也不随新设备迁移，
/// 重装 App 后旧的加密导出文件自然失效（隐私优先，代价是迁移要重新导出）。
final class SecureKeyStore {
  static let shared = SecureKeyStore()

  private let service = "com.knowpic.preference"
  private let account = "pref-export-key"
  private let keyBytes = 32 // AES-256

  /// 取回已有密钥，没有就生成一个新的（Base64 字符串）
  func getOrCreateBase64Key() -> String? {
    if let existing = read() { return existing }
    var bytes = [UInt8](repeating: 0, count: keyBytes)
    guard SecRandomCopyBytes(kSecRandomDefault, keyBytes, &bytes) == errSecSuccess else {
      return nil
    }
    let key = Data(bytes).base64EncodedString()
    guard write(key) else { return nil }
    return read() // 以钥匙串里真正存下来的值为准
  }

  func delete() {
    SecItemDelete(baseQuery() as CFDictionary)
  }

  private func baseQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func read() -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  @discardableResult
  private func write(_ key: String) -> Bool {
    delete() // 覆盖写：先删旧项
    var query = baseQuery()
    query[kSecValueData as String] = Data(key.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
  }
}

/// knowpic/secure 通道：Dart 侧 SecureKeyService 通过它拿密钥。
enum SecureKeyChannel {
  static let name = "knowpic/secure"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getOrCreateKey":
        if let key = SecureKeyStore.shared.getOrCreateBase64Key() {
          result(key)
        } else {
          result(
            FlutterError(
              code: "KEY_UNAVAILABLE",
              message: "无法访问钥匙串",
              details: nil))
        }
      case "deleteKey":
        SecureKeyStore.shared.delete()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
