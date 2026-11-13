namespace FlyyLink.Plugins;

/// MIME types for the file kinds people usually send.
internal static class MimeTypes
{
    private static readonly Dictionary<string, string> Known = new(StringComparer.OrdinalIgnoreCase)
    {
        [".png"] = "image/png",
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".gif"] = "image/gif",
        [".webp"] = "image/webp",
        [".heic"] = "image/heic",
        [".bmp"] = "image/bmp",
        [".mp4"] = "video/mp4",
        [".mov"] = "video/quicktime",
        [".mp3"] = "audio/mpeg",
        [".m4a"] = "audio/mp4",
        [".pdf"] = "application/pdf",
        [".txt"] = "text/plain",
        [".zip"] = "application/zip",
        [".apk"] = "application/vnd.android.package-archive",
    };

    public static string Of(string name) => Known.GetValueOrDefault(Path.GetExtension(name), "application/octet-stream");
}
