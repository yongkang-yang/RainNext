// SPDX-License-Identifier: GPL-3.0-or-later
import RainNextKit
import SwiftUI

/// Current location, a search field, and the saved list.
///
/// Saved places are reordered by dragging and removed from the context menu —
/// no edit mode, because a five-row list in a menu bar popover should not have
/// a state you can get stuck in.
struct LocationPickerView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            searchField

            if isSearching {
                searchResults
            } else {
                currentLocationSection
                savedSection
            }
        }
        .padding(Metrics.popoverPadding)
        .frame(width: Metrics.popoverWidth)
        .onDisappear { state.placeSearch.clear() }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var header: some View {
        HStack {
            Text("Location")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Capsule())
                    .glassSurface(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Search for a place", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onChange(of: query) { _, new in state.placeSearch.search(new) }
                .onSubmit { if let first = state.placeSearch.results.first { add(first) } }

            if state.placeSearch.isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    state.placeSearch.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassSurface(in: Capsule())
    }

    @ViewBuilder
    private var searchResults: some View {
        if let message = state.placeSearch.message {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(state.placeSearch.results) { result in
                Button {
                    add(result)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.isSaved(result) ? "checkmark.circle" : "plus.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(result.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        if !state.canAddFavourite && !state.placeSearch.results.isEmpty {
            Text("Saved list is full — remove one first.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var currentLocationSection: some View {
        Divider()

        if let current = state.locationService.currentLocation, state.currentLocationIsCovered {
            row(for: current, symbol: "location.fill") { state.select(current); onDismiss() }
        } else if !state.currentLocationIsCovered {
            Label("Your location is outside Buienradar's coverage", systemImage: "location.slash")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else {
            Button {
                state.locationService.requestAuthorization()
            } label: {
                Label(
                    state.locationService.isAuthorized ? "Locating…" : "Use current location",
                    systemImage: "location"
                )
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        Divider()

        if state.favourites.isEmpty {
            Text("No saved places. Search above to add one.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            List {
                ForEach(state.favourites) { location in
                    row(for: location, symbol: "mappin") { state.select(location); onDismiss() }
                        .contextMenu {
                            Button("Remove", role: .destructive) { remove(location) }
                        }
                }
                .onMove { state.moveFavourites(from: $0, to: $1) }
                .onDelete { state.removeFavourites(at: $0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(state.favourites.count) * 24 + 8, 190))
        }
    }

    private func row(for location: WeatherLocation, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(location.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                if location.id == state.selectedLocation.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        .listRowSeparator(.hidden)
    }

    private func add(_ location: WeatherLocation) {
        state.addFavourite(location)
        query = ""
        state.placeSearch.clear()
        onDismiss()
    }

    private func remove(_ location: WeatherLocation) {
        guard let index = state.favourites.firstIndex(where: { $0.id == location.id }) else { return }
        state.removeFavourites(at: IndexSet(integer: index))
    }
}
