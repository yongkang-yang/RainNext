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
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField

            if isSearching {
                searchResults
            } else {
                places
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .contentShape(Capsule())
                    .glassSurface(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search for a place", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
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
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.searchHeight)
        .glassSurface(in: Capsule())
    }

    // MARK: - Search

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = state.placeSearch.message {
                note(message)
            }

            // Ten results would push the popover past its own height; they
            // scroll inside the card instead of growing the window.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.placeSearch.results) { result in
                        PlaceRow(
                            symbol: state.isSaved(result) ? "checkmark.circle.fill" : "plus.circle",
                            name: result.name
                        ) { add(result) }
                    }
                }
            }
            .frame(maxHeight: Metrics.rowHeight * 7)
            .fixedSize(horizontal: false, vertical: true)

            if !state.canAddFavourite && !state.placeSearch.results.isEmpty {
                note("Saved list is full — remove one first.")
            }
        }
        .padding(Metrics.rowInset)
        .card()
    }

    // MARK: - Places

    /// Current location and the saved list share one card, split by section
    /// labels rather than hairline dividers.
    private var places: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Current location")
            currentLocation

            sectionLabel("Saved")
                .padding(.top, 6)
            saved
        }
        .padding(Metrics.rowInset)
        .card()
    }

    @ViewBuilder
    private var currentLocation: some View {
        if let current = state.locationService.currentLocation, state.currentLocationIsCovered {
            PlaceRow(
                symbol: "location.fill",
                name: current.name,
                isSelected: current.id == state.selectedLocation.id
            ) { state.select(current); onDismiss() }
        } else if !state.currentLocationIsCovered {
            note("Your location is outside Buienradar's coverage", symbol: "location.slash")
        } else {
            PlaceRow(
                symbol: "location",
                name: state.locationService.isAuthorized ? "Locating…" : "Use current location"
            ) { state.locationService.requestAuthorization() }
        }
    }

    @ViewBuilder
    private var saved: some View {
        if state.favourites.isEmpty {
            note("No saved places. Search above to add one.")
        } else {
            List {
                ForEach(state.favourites) { location in
                    PlaceRow(
                        symbol: "mappin",
                        name: location.name,
                        isSelected: location.id == state.selectedLocation.id
                    ) { state.select(location); onDismiss() }
                    .contextMenu {
                        Button("Remove", role: .destructive) { remove(location) }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { state.moveFavourites(from: $0, to: $1) }
                .onDelete { state.removeFavourites(at: $0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, Metrics.rowHeight)
            .frame(height: CGFloat(state.favourites.count) * Metrics.rowHeight)
            // The table under a macOS List insets every row by about 8 pt a
            // side, ignoring listRowInsets and contentMargins. Without this
            // the saved places sit indented from the current location.
            .padding(.horizontal, -Metrics.listInset)
            .scrollDisabled(true)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }

    private func note(_ text: String, symbol: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .frame(width: 16)
            }
            Text(text)
                .lineLimit(2)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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

/// One place: a symbol, a name, and a checkmark on the one showing. The hover
/// fill is the row's only chrome, with corners concentric to the card.
private struct PlaceRow: View {
    let symbol: String
    let name: String
    var isSelected = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 16)
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Metrics.rowHeight)
            .background(
                Color.primary.opacity(isHovered ? 0.07 : 0),
                in: RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
