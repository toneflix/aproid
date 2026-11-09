import AppKit
import MapKit
import SwiftUI
import AproidKit

/// Where the phone is, on a small map, after asking it to ring.
struct FindCard: View {
    let deviceName: String
    let location: PhoneLocation
    let close: () -> Void

    private struct Pin: Identifiable {
        let id = 0
        let coordinate: CLLocationCoordinate2D
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var region: MKCoordinateRegion {
        // Show at least a few streets around the pin, more when the fix is rough.
        let span = max(location.accuracy * 6, 400)
        return MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(deviceName, lucide: .mapPin, size: 13)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Spacer()
                Button(action: close) {
                    Image(lucide: .circleX).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide the map")
            }

            Map(coordinateRegion: .constant(region), interactionModes: [.zoom, .pan], annotationItems: [Pin(coordinate: coordinate)]) { pin in
                MapAnnotation(coordinate: pin.coordinate) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.2)).frame(width: 34, height: 34)
                        Circle().fill(Theme.accent).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    }
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open in Maps", action: openInMaps)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .card(padding: 12)
    }

    private var detail: String {
        let when = location.time > 0 ? RelativeTime.text(Date(timeIntervalSince1970: TimeInterval(location.time) / 1000)) : "just now"
        return "Within \(Int(location.accuracy.rounded())) m · \(when)"
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = deviceName
        item.openInMaps(launchOptions: nil)
    }
}
