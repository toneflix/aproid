using FlyyLink.Core;
using PowerManager = Windows.System.Power.PowerManager;
using PowerSupplyStatus = Windows.System.Power.PowerSupplyStatus;

namespace FlyyLink.Shell;

/// This PC's own battery, so paired computers can show it.
internal sealed class SystemBattery
{
    /// Called on a background thread when the charge or the power source changes.
    public Action? OnChange { get; set; }

    /// Null on a PC without a battery.
    public static BatteryStatus? Current()
    {
        if (PowerManager.BatteryStatus == Windows.System.Power.BatteryStatus.NotPresent) return null;

        var pluggedIn = PowerManager.PowerSupplyStatus != PowerSupplyStatus.NotPresent;

        return BatteryStatus.Of(Math.Clamp(PowerManager.RemainingChargePercent, 0, 100), pluggedIn);
    }

    public void Start()
    {
        PowerManager.RemainingChargePercentChanged += (_, _) => OnChange?.Invoke();
        PowerManager.PowerSupplyStatusChanged += (_, _) => OnChange?.Invoke();
        PowerManager.BatteryStatusChanged += (_, _) => OnChange?.Invoke();
    }
}
