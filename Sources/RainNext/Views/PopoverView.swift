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
            StatusSummaryView(status: state.status, observation: state.observation, now: state.now)
            RainTimelineView(forecast: state.forecast, now: state.now)
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if state.notifications.authorizationDenied {
                // Silence would look like a broken button. macOS refuses
                // notifications outright for an unsigned build, without ever
                // asking the user, so say so instead of failing quietly.
                Label("macOS refused notifications for this build", systemImage: "bell.slash")
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
        HStack(spacing: 4) {
            Text(lastUpdated)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            attribution
            Spacer()
            Button {
                state.setNotificationsEnabled(!state.notifications.isEnabled)
            } label: {
                Image(systemName: state.notifications.isEnabled ? "bell.fill" : "bell.slash")
            }
            .buttonStyle(.plain)
            .help(state.notifications.isEnabled
                  ? "Rain alerts on — you'll hear about rain about 30 minutes ahead"
                  : "Turn on rain alerts")

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
        guard let fetchedAt = state.forecast?.fetchedAt else { return "Not updated yet ·" }
        return "Updated \(RainPhrasing.clock(fetchedAt)) ·"
    }

    /// Buienradar's terms for the free weather data ask for this exact form:
    /// "bronvermelding (Buienradar.nl) met hyperlink naar
    /// https://www.buienradar.nl". The name and the working link are the
    /// requirement, so neither is decoration.
    private var attribution: some View {
        // One step brighter than the timestamp beside it: a hyperlink nobody
        // can tell is a hyperlink does not really satisfy the requirement.
        Link("Buienradar.nl", destination: URL(string: "https://www.buienradar.nl")!)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .help("Weather data by Buienradar.nl")
    }
}
