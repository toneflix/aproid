using Aproid.Core;
using Aproid.Model;
using Microsoft.UI.Dispatching;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;
using static Aproid.Shell.NativeMethods;
using DataClipboard = Windows.ApplicationModel.DataTransfer.Clipboard;

namespace Aproid.Plugins;

/// Shares the clipboard with paired phones both ways: text, pictures and copied files.
/// Reading and writing the Windows clipboard happens on the UI thread.
internal sealed class ClipboardPlugin(DeviceRegistry devices, DispatcherQueue ui) : IPlugin
{
    private readonly string folder = Directory.CreateDirectory(Path.Combine(AppPaths.Cache, "Clipboard")).FullName;

    /// The clipboard sequence number after our own last write, which must not be sent back.
    private uint ownSequence;

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Clipboard, PacketType.ClipboardConnect, PacketType.ClipboardFile };

    /// Called on the UI thread whenever something goes either way.
    public Action? OnSync { get; set; }

    /// Something was copied on this PC. Call on the UI thread.
    public void Changed()
    {
        if (GetClipboardSequenceNumber() == ownSequence) return;

        var paired = devices.Paired;
        if (paired.Count > 0) _ = SendAsync(paired);
    }

    /// Sends what is on the clipboard now, even if it was sent before. Call on the UI thread.
    public Task<bool> SendAsync(Device device) => SendAsync([device]);

    /// Puts text on the clipboard without sending it back. Safe from any thread.
    public void WriteText(string text) => ui.TryEnqueue(() =>
    {
        var package = new DataPackage();
        package.SetText(text);
        Write(package);
    });

    public void OnPaired(Device device) => ui.TryEnqueue(async () =>
    {
        if (await ReadTextAsync() is { Length: > 0 } text)
            device.Send(Core.Clipboard.ConnectPacket(text, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()));
    });

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (Core.Clipboard.File(packet) is ClipboardFile file)
        {
            _ = ReceiveAsync(file, packet, device);
            return;
        }

        if (Core.Clipboard.Content(packet) is not string text) return;

        ui.TryEnqueue(async () =>
        {
            if (await ReadTextAsync() == text) return;

            var package = new DataPackage();
            package.SetText(text);
            Write(package);
        });
    }

    // Reading this PC's clipboard

    private async Task<bool> SendAsync(IReadOnlyList<Device> targets)
    {
        DataPackageView view;
        try
        {
            view = DataClipboard.GetContent();
        }
        catch (Exception)
        {
            return false;
        }

        // Copied files come first, since Explorer also puts their names on the clipboard as text.
        if (view.Contains(StandardDataFormats.StorageItems))
        {
            var files = (await view.GetStorageItemsAsync()).OfType<StorageFile>().Select(f => f.Path).ToList();
            if (files.Count == 0) return false;

            _ = Task.Run(() => files.ForEach(path => targets.ToList().ForEach(device => Offer(path, device))));
        }
        else if (view.Contains(StandardDataFormats.Text))
        {
            var text = await view.GetTextAsync();
            if (text.Length == 0) return false;

            foreach (var device in targets) device.Send(Core.Clipboard.Packet(text));
        }
        else if (view.Contains(StandardDataFormats.Bitmap))
        {
            var path = await SavePngAsync(await view.GetBitmapAsync());
            if (path is null) return false;

            _ = Task.Run(() => targets.ToList().ForEach(device => Offer(path, device)));
        }
        else
        {
            return false;
        }

        OnSync?.Invoke();

        return true;
    }

    private static async Task<string?> ReadTextAsync()
    {
        try
        {
            var view = DataClipboard.GetContent();

            return view.Contains(StandardDataFormats.Text) ? await view.GetTextAsync() : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// Copied pictures arrive as bitmaps in whatever format the app chose, so they are saved as PNG to send.
    private async Task<string?> SavePngAsync(RandomAccessStreamReference bitmap)
    {
        try
        {
            using var stream = await bitmap.OpenReadAsync();
            var decoder = await BitmapDecoder.CreateAsync(stream);
            var pixels = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);

            var path = Path.Combine(Path.GetTempPath(), $"Copied image {DateTime.Now:yyyy-MM-dd 'at' HH.mm.ss}.png");
            using (var output = File.Create(path).AsRandomAccessStream())
            {
                var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, output);
                encoder.SetSoftwareBitmap(pixels);
                await encoder.FlushAsync();
            }

            return path;
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static void Offer(string path, Device device)
    {
        FileInfo info;
        FileStream source;
        try
        {
            info = new FileInfo(path);
            if (info.Length > Core.Clipboard.FileLimit) return;

            source = File.OpenRead(path);
        }
        catch (IOException)
        {
            return;
        }

        device.SendWithPayload(Core.Clipboard.FilePacket(info.Name, MimeTypes.Of(info.Name)), info.Length, source, completion: _ => source.Dispose());
    }

    // Writing to this PC's clipboard

    private async Task ReceiveAsync(ClipboardFile file, NetworkPacket packet, Device device)
    {
        // A fresh folder each time, so a pasted file keeps its own name.
        var target = Path.Combine(Directory.CreateDirectory(Path.Combine(folder, Guid.NewGuid().ToString("N"))).FullName, file.SafeName);

        try
        {
            await using (var sink = File.Create(target))
            {
                await device.ReceivePayloadAsync(packet, sink);
            }
        }
        catch (Exception)
        {
            File.Delete(target);
            return;
        }

        ui.TryEnqueue(async () => await PasteAsync(target, file.MimeType));
    }

    /// Pictures go on the clipboard as pictures, so they paste into any app; other files as files.
    private async Task PasteAsync(string path, string mimeType)
    {
        var storageFile = await StorageFile.GetFileFromPathAsync(path);
        var package = new DataPackage();
        package.SetStorageItems([storageFile]);
        if (mimeType.StartsWith("image/", StringComparison.Ordinal)) package.SetBitmap(RandomAccessStreamReference.CreateFromFile(storageFile));

        Write(package);
    }

    private void Write(DataPackage package)
    {
        try
        {
            DataClipboard.SetContent(package);
            DataClipboard.Flush();
            ownSequence = GetClipboardSequenceNumber();
            OnSync?.Invoke();
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Clipboard write failed: {e.Message}");
        }
    }
}
