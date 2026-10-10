import Flutter
import UIKit

/// Studio-only QA channel (`com.chic.audiovisualCreator/qa`): the launch
/// arguments, a device snapshot for the energy probe and the idle timer.
/// Observational: it never touches the compositor or its sessions.
final class SceneCompositorHostQaChannel: NSObject, FlutterPlugin {
  static let channelName = "com.chic.audiovisualCreator/qa"

  private weak var registrar: FlutterPluginRegistrar?

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = SceneCompositorHostQaChannel(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "launchArguments":
      result(ProcessInfo.processInfo.arguments)
    case "deviceSnapshot":
      result(deviceSnapshot())
    case "setIdleTimerDisabled":
      guard let arguments = call.arguments as? [String: Any],
        let disabled = arguments["disabled"] as? Bool
      else {
        result(
          FlutterError(
            code: "bad_arguments", message: "setIdleTimerDisabled needs {disabled: Bool}.",
            details: nil))
        return
      }
      UIApplication.shared.isIdleTimerDisabled = disabled
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func deviceSnapshot() -> [String: Any] {
    let process = ProcessInfo.processInfo
    let device = UIDevice.current
    // Level is -1 and state .unknown until monitoring is on; both reported raw.
    device.isBatteryMonitoringEnabled = true
    var snapshot: [String: Any] = [
      "thermalState": Self.thermalName(process.thermalState),
      "lowPowerMode": process.isLowPowerModeEnabled,
      "batteryLevel": Double(device.batteryLevel),
      "brightness": Double(screen().brightness),
      "batteryState": Self.batteryName(device.batteryState),
      "charging": device.batteryState == .charging || device.batteryState == .full,
      "displayHz": screen().maximumFramesPerSecond,
      "model": Self.hardwareModel(),
      "systemName": device.systemName,
      "systemVersion": device.systemVersion,
      "isPhysical": Self.isPhysical,
    ]
    if let footprint = Self.physicalFootprint() {
      snapshot["memoryBytes"] = footprint
    }
    return snapshot
  }

  /// The screen the studio window is on; the main screen when no window yet.
  private func screen() -> UIScreen {
    registrar?.viewController?.view.window?.windowScene?.screen ?? UIScreen.main
  }

  static var isPhysical: Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      return true
    #endif
  }

  static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  static func batteryName(_ state: UIDevice.BatteryState) -> String {
    switch state {
    case .unknown: return "unknown"
    case .unplugged: return "unplugged"
    case .charging: return "charging"
    case .full: return "full"
    @unknown default: return "unknown"
    }
  }

  /// `utsname.machine`, e.g. `iPhone15,2`; the simulator reports its host.
  static func hardwareModel() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
        String(cString: $0)
      }
    }
  }

  /// `TASK_VM_INFO.phys_footprint` of this process, in bytes.
  static func physicalFootprint() -> Int? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard status == KERN_SUCCESS else { return nil }
    return Int(min(info.phys_footprint, UInt64(Int.max)))
  }
}
