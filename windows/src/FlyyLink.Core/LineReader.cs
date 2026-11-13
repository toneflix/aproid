namespace FlyyLink.Core;

/// Splits a stream into "\n"-terminated lines.
internal sealed class LineReader(Stream stream)
{
    private const int MaxLine = 16 * 1024 * 1024;

    private readonly byte[] chunk = new byte[64 * 1024];
    private readonly MemoryStream pending = new();

    /// The next line without its newline, or null once the stream ends.
    public async Task<byte[]?> ReadLineAsync(CancellationToken cancellation = default)
    {
        while (true)
        {
            if (TakeLine() is byte[] line) return line;

            var read = await stream.ReadAsync(chunk, cancellation).ConfigureAwait(false);
            if (read == 0) return null;

            pending.Write(chunk, 0, read);
            if (pending.Length > MaxLine) throw new ProtocolException("line too long");
        }
    }

    /// Reads one line a byte at a time, so nothing after it is consumed. Used before TLS starts on the same socket.
    public static async Task<byte[]> ReadPlainLineAsync(Stream stream, int maxLength, CancellationToken cancellation)
    {
        var line = new MemoryStream();
        var one = new byte[1];

        while (true)
        {
            var read = await stream.ReadAsync(one, cancellation).ConfigureAwait(false);
            if (read == 0) throw new ProtocolException("connection closed before identity");
            if (one[0] == (byte)'\n') return line.ToArray();

            line.WriteByte(one[0]);
            if (line.Length > maxLength) throw new ProtocolException("identity too long");
        }
    }

    private byte[]? TakeLine()
    {
        var buffer = pending.GetBuffer();
        var length = (int)pending.Length;
        var newline = Array.IndexOf(buffer, (byte)'\n', 0, length);
        if (newline < 0) return null;

        var line = buffer.AsSpan(0, newline).ToArray();
        var rest = buffer.AsSpan(newline + 1, length - newline - 1).ToArray();
        pending.SetLength(0);
        pending.Write(rest);

        return line;
    }
}
