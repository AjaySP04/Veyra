import SwiftUI

@main
struct VeyraApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: dependencies.coordinator, permissions: dependencies.permissions)
        } label: {
            Image(systemName: dependencies.coordinator.state.menuBarSymbol)
        }
    }
}
