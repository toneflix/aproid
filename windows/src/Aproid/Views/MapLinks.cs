using System.Globalization;
using Aproid.Core;

namespace Aproid.Views;

/// OpenStreetMap and Google Maps links for a phone's location.
internal static class MapLinks
{
    /// A small embeddable map around the phone with a pin on it. Shows at least a few streets, more when the fix is rough.
    public static string Embed(PhoneLocation location)
    {
        var span = Math.Max(location.Accuracy * 6, 400);
        var latitude = span / 2 / 111_320;
        var longitude = latitude / Math.Max(Math.Cos(location.Latitude * Math.PI / 180), 0.01);

        return Invariant(
            $"https://www.openstreetmap.org/export/embed.html?bbox={location.Longitude - longitude},{location.Latitude - latitude},{location.Longitude + longitude},{location.Latitude + latitude}&layer=mapnik&marker={location.Latitude},{location.Longitude}");
    }

    public static string Search(PhoneLocation location) =>
        Invariant($"https://www.google.com/maps/search/?api=1&query={location.Latitude},{location.Longitude}");

    private static string Invariant(FormattableString text) => text.ToString(CultureInfo.InvariantCulture);
}
