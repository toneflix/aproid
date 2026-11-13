using System.Threading.Channels;

namespace FlyyLink.Core;

/// A payload written while it is sent, such as a shared screen. Hand it to `Device.SendWithPayload` with
/// `PayloadTransfer.Stream` as the size, then `Push` whole pieces to it and `Complete` it at the end.
/// When the peer falls behind, the oldest waiting pieces are dropped, so each piece must stand on its own.
/// Mirrors PayloadStream in PayloadTransfer.swift.
public sealed class LiveStream(int backlog = 2) : Stream
{
    private readonly Channel<byte[]> pieces = Channel.CreateBounded<byte[]>(new BoundedChannelOptions(backlog)
    {
        FullMode = BoundedChannelFullMode.DropOldest,
        SingleReader = true,
    });

    private byte[] current = [];
    private int offset;
    private volatile bool reading;

    /// True once the peer has connected and started reading.
    public bool IsOpen => reading && !IsCompleted;

    public bool IsCompleted { get; private set; }

    public override bool CanRead => true;

    public override bool CanSeek => false;

    public override bool CanWrite => false;

    public override long Length => throw new NotSupportedException();

    public override long Position
    {
        get => throw new NotSupportedException();
        set => throw new NotSupportedException();
    }

    /// Queues one whole piece. Returns false once the stream has ended.
    public bool Push(byte[] piece) => !IsCompleted && pieces.Writer.TryWrite(piece);

    /// Ends the stream; the peer sees it close once it has read what is queued.
    public void Complete()
    {
        IsCompleted = true;
        pieces.Writer.TryComplete();
    }

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        reading = true;

        while (offset >= current.Length)
        {
            if (!await pieces.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false)) return 0;

            if (pieces.Reader.TryRead(out var next))
            {
                current = next;
                offset = 0;
            }
        }

        var count = Math.Min(buffer.Length, current.Length - offset);
        current.AsMemory(offset, count).CopyTo(buffer);
        offset += count;

        return count;
    }

    public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
        ReadAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();

    public override int Read(byte[] buffer, int offset, int count) => ReadAsync(buffer, offset, count).GetAwaiter().GetResult();

    public override void Flush()
    {
    }

    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

    public override void SetLength(long value) => throw new NotSupportedException();

    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    protected override void Dispose(bool disposing)
    {
        if (disposing) Complete();

        base.Dispose(disposing);
    }
}
