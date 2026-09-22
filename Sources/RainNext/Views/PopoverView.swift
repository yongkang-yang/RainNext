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
        .background(PopoverWindowShape(cornerRadius: Metrics.popoverRadius))
        .onAppear {
            // BD-105: refresh when the popover opens.
            state.refresh(minimumAge: AppState.openRefreshInterval)
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            locationButton
            StatusSummaryView(status: state.status, observation: state.observation, now: state.now)
            RainTimelineView(
                forecast: state.forecast,
                hourly: state.hourly,
                span: $state.span,
                now: state.now
            )
            .padding(Metrics.cardPadding)
            .card()
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
            footer
        }
        .padding(Metrics.popoverPadding)
        .frame(width: Metrics.popoverWidth)
    }

    private var locationButton: some View {
        Button {
            isPickingLocation = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state.selectedLocation.isCurrentLocation ? "location.fill" : "mappin")
                    .font(.system(size: 10))
                Text(state.selectedLocation.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
            .glassSurface(in: Capsule(), interactive: true)
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
            GlassGroup {
                HStack(spacing: 6) {
                    GlassIconButton(
                        symbol: state.notifications.isEnabled ? "bell.fill" : "bell.slash",
                        help: state.notifications.isEnabled
                            ? "Rain alerts on — you'll hear about rain about 30 minutes ahead"
                            : "Turn on rain alerts"
                    ) {
                        state.setNotificationsEnabled(!state.notifications.isEnabled)
                    }
                    GlassIconButton(symbol: "arrow.clockwise", help: "Refresh now", dimmed: state.isRefreshing) {
                        state.refresh()
                    }
                    .disabled(state.isRefreshing)
                    GlassIconButton(symbol: "power", help: "Quit RainNext") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
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
