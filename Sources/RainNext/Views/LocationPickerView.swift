import RainNextKit
import SwiftUI

/// Current location plus a short preset list. Custom/favourite locations are
/// still an open question in BD-105.
struct LocationPickerView: View {
    @EnvironmentObject private var state: AppState
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Location")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }

            Divider()

            if let current = state.locationService.currentLocation {
                row(for: current, symbol: "location.fill")
            } else {
                Button {
                    state.locationService.requestAuthorization()
                } label: {
                    Label(currentLocationPrompt, systemImage: "location")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            Divider()

            ForEach(WeatherLocation.presets) { preset in
                row(for: preset, symbol: "mappin")
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var currentLocationPrompt: String {
        state.locationService.isAuthorized ? "Locating…" : "Use current location"
    }

    private func row(for location: WeatherLocation, symbol: String) -> some View {
        Button {
            state.select(location)
            onDismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(location.name)
                    .font(.system(size: 12))
                Spacer()
                if location.id == state.selectedLocation.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
