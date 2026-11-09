using System.Text.Json;
using System.Text.Json.Nodes;

namespace Aproid.Core;

/// Reads typed values out of free-form packet JSON, accepting the loose number forms other clients send.
public static class JsonValues
{
    public static string? AsString(this JsonNode? node) =>
        node is JsonValue value && value.TryGetValue(out string? text) ? text : null;

    public static bool? AsBool(this JsonNode? node) =>
        node is JsonValue value && value.TryGetValue(out bool flag) ? flag : null;

    public static long? AsLong(this JsonNode? node)
    {
        if (node is not JsonValue value) return null;
        if (value.TryGetValue(out long whole)) return whole;
        if (value.TryGetValue(out int small)) return small;

        var real = value.AsDouble();
        if (real is double d && Math.Floor(d) == d && d is >= long.MinValue and <= long.MaxValue) return (long)d;

        return null;
    }

    public static double? AsDouble(this JsonNode? node)
    {
        if (node is not JsonValue value) return null;
        if (value.TryGetValue(out double real)) return real;
        if (value.TryGetValue(out long whole)) return whole;
        if (value.TryGetValue(out int small)) return small;
        if (value.TryGetValue(out float single)) return single;

        return null;
    }

    public static IReadOnlyList<string> AsStringList(this JsonNode? node) =>
        node is JsonArray array ? array.Select(item => item.AsString()).OfType<string>().ToList() : [];

    /// Writes `node` with object keys sorted at every level, as the other apps do.
    public static void WriteSorted(Utf8JsonWriter writer, JsonNode? node)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                break;
            case JsonObject obj:
                writer.WriteStartObject();
                foreach (var (key, child) in obj.OrderBy(pair => pair.Key, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(key);
                    WriteSorted(writer, child);
                }
                writer.WriteEndObject();
                break;
            case JsonArray array:
                writer.WriteStartArray();
                foreach (var child in array) WriteSorted(writer, child);
                writer.WriteEndArray();
                break;
            default:
                node.WriteTo(writer);
                break;
        }
    }
}
