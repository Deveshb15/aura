import SwiftUI

/// The selected library tab: everything, or a specific user collection.
enum CategoryTab: Equatable, Hashable {
    case all
    case collection(String) // collection id
}

/// Horizontal tab bar: "All" + the user's collections, with item counts, a "+"
/// to create a collection, and right-click rename/delete on each collection.
struct CategoryTabBar: View {
    @Environment(DataStore.self) private var store
    @Binding var selection: CategoryTab
    let count: (CategoryTab) -> Int

    @State private var showingNew = false
    @State private var newName = ""
    @State private var renaming: ItemCollection?
    @State private var renameName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tab(.all, label: "All", symbol: "square.grid.2x2")

                ForEach(store.collections) { collection in
                    tab(.collection(collection.id), label: collection.name, symbol: collection.symbol ?? "folder")
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                renaming = collection
                                renameName = collection.name
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.deleteCollection(collection)
                            }
                        }
                }

                addButton
            }
            .padding(.vertical, 1)
        }
        .alert("New Collection", isPresented: $showingNew) {
            TextField("Name", text: $newName)
            Button("Create") { store.createCollection(name: newName); newName = "" }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .alert("Rename Collection", isPresented: renamingBinding) {
            TextField("Name", text: $renameName)
            Button("Save") {
                if let collection = renaming { store.renameCollection(collection, to: renameName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func tab(_ value: CategoryTab, label: String, symbol: String) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
                Text("\(count(value))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background((isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.06)), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.gray.opacity(0.12)), in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            newName = ""
            showingNew = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.gray.opacity(0.12), in: Circle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help("New collection")
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
