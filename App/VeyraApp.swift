import SwiftUI

@main
struct VeyraApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: dependencies.coordinator, permissions: dependencies.permissions)
        } label: {
            switch dependencies.coordinator.state.menuBarIcon {
            case .mark: Image(nsImage: VeyraMark.image(tilt: dependencies.iconAnimator.tilt))
            case .symbol(let name): Image(systemName: name)
            }
        }
    }
}
