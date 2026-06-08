import SwiftUI

/// The main library window: search, category tabs, and the bento grid.
struct LibraryWindowView: View {
    @Environment(DataStore.self) private var store
    @State private var query = ""
    @State private var filter: LibraryFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            header
            CategoryTabBar(selection: $filter)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            Divider()
            if filteredItems.isEmpty {
                emptyState
            } else {
                BentoGridView(items: filteredItems)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill").foregroundStyle(.tint)
            Text("Aura").font(.system(size: 16, weight: .bold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1), in: Capsule())
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(store.libraryItems.isEmpty ? "Nothing saved yet" : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Drop things into the notch or copy something to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredItems: [Item] {
        store.libraryItems.filter { item in
            filter.matches(item) &&
            (query.isEmpty || item.searchText.localizedCaseInsensitiveContains(query))
        }
    }
}
