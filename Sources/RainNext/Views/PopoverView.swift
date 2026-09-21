// SPDX-License-Identifier: GPL-3.0-or-later
import RainNextKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var state: AppState
    @State private var isPickingLocation = false

    var body: some View {
        Group {
            if isPickingLocation {
                LocationPickerView { isPickingLocation = false }
            } else {
                main
            }
        }
        .onAppear {
            // BD-105: refresh when the popover opens.
            state.refresh(minimumAge: AppState.openRefreshInterval)
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 12) {
            locationButton
            StatusSummaryView(status: state.status, now: state.now)
            RainTimelineView(forecast: state.forecast, now: state.now)
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var locationButton: some View {
        Button {
            isPickingLocation = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.selectedLocation.isCurrentLocation ? "location.fill" : "mappin")
                    .font(.system(size: 10))
                Text(state.selectedLocation.name)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text(lastUpdated)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                state.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .opacity(state.isRefreshing ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(state.isRefreshing)
            .help("Refresh now")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit RainNext")
        }
        .foregroundStyle(.secondary)
    }

    private var lastUpdated: String {
        guard let fetchedAt = state.forecast?.fetchedAt else { return "Not updated yet" }
        return "Updated \(RainPhrasing.clock(fetchedAt)) · Data: Buienradar"
    }
}
