import Foundation
import IOKit.ps
import AproidKit

/// This Mac's own battery, read from IOKit, so paired computers can show it.
final class SystemBattery {
    /// Called on the main thread when the charge or the power source changes.
    var onChange: (() -> Void)?

    private var source: CFRunLoopSource?

    /// Nil on a Mac without a battery.
    static func current() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }

            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return .of(charge: min(capacity * 100 / maximum, 100), isCharging: pluggedIn)
        }

        return nil
    }

    func start() {
        guard source == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }

            Unmanaged<SystemBattery>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, context)
        guard let loopSource = created?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .defaultMode)
        source = loopSource
    }
}
