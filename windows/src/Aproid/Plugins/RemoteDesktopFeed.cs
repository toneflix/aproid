using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Aproid.Plugins;

/// Turns the JPEG pictures from another computer into bitmaps. Pictures arrive on a network thread; while one is
/// still being decoded, newer ones replace the waiting one, so a slow PC skips pictures instead of falling behind.
internal sealed class RemoteDesktopFeed
{
    private readonly object gate = new();
    private byte[]? waiting;
    private bool busy;

    /// Called on a background thread with each picture to show, in BGRA with premultiplied alpha.
    public Action<SoftwareBitmap>? OnPicture { get; set; }

    public void Push(byte[] jpeg)
    {
        lock (gate)
        {
            waiting = jpeg;
            if (busy) return;

            busy = true;
        }

        _ = Task.Run(DrainAsync);
    }

    private async Task DrainAsync()
    {
        while (true)
        {
            byte[]? jpeg;
            lock (gate)
            {
                jpeg = waiting;
                waiting = null;
                if (jpeg is null)
                {
                    busy = false;
                    return;
                }
            }

            try
            {
                using var stream = new InMemoryRandomAccessStream();
                await stream.WriteAsync(jpeg.AsBuffer());
                stream.Seek(0);
                var decoder = await BitmapDecoder.CreateAsync(BitmapDecoder.JpegDecoderId, stream);
                OnPicture?.Invoke(await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied));
            }
            catch (Exception e) when (e is not OutOfMemoryException)
            {
                System.Diagnostics.Debug.WriteLine($"Could not show a picture: {e.Message}");
            }
        }
    }
}
