using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Security.Cryptography;
using Aproid.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;

namespace Aproid.Shell;

/// Finds a paired phone over Bluetooth LE when Wi-Fi discovery fails, and asks it where it is.
/// With `Hotspot` it also asks the phone to put its hotspot switch in front of the user.
internal sealed class NearbyFinder(string ownId, RSA privateKey)
{
    private static readonly TimeSpan SearchTime = TimeSpan.FromSeconds(20);

    private readonly object gate = new();
    private BluetoothLEAdvertisementWatcher? watcher;
    private BluetoothLEDevice? device;
    private GattCharacteristic? answer;
    private Nearby.Want want;
    private int search;

    /// Called on a background thread with the phone's opened answer.
    public Action<Nearby.Answer>? OnAnswer { get; set; }

    /// Called on a background thread when a phone is in range, or with false when a search ends with nothing.
    public Action<bool>? OnNearby { get; set; }

    /// Looks for a phone for about 20 seconds.
    public void Search(Nearby.Want wanted)
    {
        int current;
        lock (gate)
        {
            want = wanted;
            current = ++search;
            if (watcher is not null) return;

            try
            {
                watcher = new BluetoothLEAdvertisementWatcher { ScanningMode = BluetoothLEScanningMode.Active };
                watcher.AdvertisementFilter.Advertisement.ServiceUuids.Add(Nearby.Service);
                watcher.Received += Received;
                watcher.Start();
            }
            catch (Exception e) when (e is COMException or UnauthorizedAccessException or ArgumentException)
            {
                // No Bluetooth adapter, or it's off.
                watcher = null;
                return;
            }
        }

        _ = Task.Delay(SearchTime).ContinueWith(_ => GiveUp(current), TaskScheduler.Default);
    }

    private void GiveUp(int which)
    {
        lock (gate)
        {
            if (which != search || watcher is null) return;
        }

        Finish();
        OnNearby?.Invoke(false);
    }

    private void Finish()
    {
        lock (gate)
        {
            watcher?.Stop();
            watcher = null;
            answer = null;
            device?.Dispose();
            device = null;
        }
    }

    private void Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args)
    {
        lock (gate)
        {
            if (device is not null || watcher != sender) return;

            sender.Stop();
        }

        OnNearby?.Invoke(true);
        _ = AskAsync(args.BluetoothAddress);
    }

    private async Task AskAsync(ulong address)
    {
        try
        {
            var found = await BluetoothLEDevice.FromBluetoothAddressAsync(address);
            if (found is null) return;

            lock (gate) device = found;

            var services = await found.GetGattServicesForUuidAsync(Nearby.Service, BluetoothCacheMode.Uncached);
            if (services.Status != GattCommunicationStatus.Success || services.Services.Count == 0) return;

            var service = services.Services[0];
            var request = (await service.GetCharacteristicsForUuidAsync(Nearby.RequestCharacteristic, BluetoothCacheMode.Uncached)).Characteristics.FirstOrDefault();
            var reply = (await service.GetCharacteristicsForUuidAsync(Nearby.AnswerCharacteristic, BluetoothCacheMode.Uncached)).Characteristics.FirstOrDefault();
            if (request is null || reply is null) return;

            lock (gate) answer = reply;
            reply.ValueChanged += AnswerChanged;
            await reply.WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue.Notify);

            Nearby.Want wanted;
            lock (gate) wanted = want;
            await request.WriteValueWithResultAsync(new Nearby.Request(ownId, wanted).Bytes().AsBuffer(), GattWriteOption.WriteWithResponse);
        }
        catch (Exception e) when (e is COMException or ObjectDisposedException or UnauthorizedAccessException)
        {
            System.Diagnostics.Debug.WriteLine($"Bluetooth ask failed: {e.Message}");
        }
    }

    private async void AnswerChanged(GattCharacteristic sender, GattValueChangedEventArgs args)
    {
        try
        {
            var value = args.CharacteristicValue.ToArray();

            // A one byte note says the answer is ready; then we read it, which may take several pieces.
            if (value.Length <= 1)
            {
                var read = await sender.ReadValueAsync(BluetoothCacheMode.Uncached);
                if (read.Status != GattCommunicationStatus.Success) return;

                value = read.Value.ToArray();
            }

            var opened = Nearby.Open(value, privateKey);
            Finish();
            OnAnswer?.Invoke(opened);
        }
        catch (Exception e) when (e is CryptographicException or ProtocolException or COMException or System.Text.Json.JsonException)
        {
            System.Diagnostics.Debug.WriteLine($"Could not read the phone's Bluetooth answer: {e.Message}");
        }
    }
}
