import Flutter
import UIKit

/// What Athena asks the phone: its memory and model, where to keep models, the free space there.
/// The decision engine itself is AthenaEngine.framework, called from Dart over FFI.
public class AthenaNativePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "athena_native", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(AthenaNativePlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "deviceFacts":
            var u = utsname()
            uname(&u)
            let machine = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            result([
                "platform": "ios",
                "machine": machine, // "iPhone14,5"; Dart turns it into "iPhone 13"
                "name": UIDevice.current.model,
                "ramBytes": Int(ProcessInfo.processInfo.physicalMemory),
                "osVersion": UIDevice.current.systemVersion,
            ])
        case "modelsDir":
            do {
                // Application Support, excluded from iCloud and iTunes backups: a model is a download, not data
                var dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
                    .appendingPathComponent("models", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try dir.setResourceValues(values)
                result(dir.path)
            } catch {
                result(FlutterError(code: "models_dir", message: error.localizedDescription, details: nil))
            }
        case "freeBytes":
            let url = URL(fileURLWithPath: args["path"] as? String ?? NSHomeDirectory())
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            result(values?.volumeAvailableCapacityForImportantUsage.map { Int($0) })
        case "launchArguments":
            result(Array(ProcessInfo.processInfo.arguments.dropFirst()))
        case "keepScreenOn":
            UIApplication.shared.isIdleTimerDisabled = args["on"] as? Bool ?? false
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
