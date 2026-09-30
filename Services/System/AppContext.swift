struct AppContext: Equatable {
    let bundleIdentifier: String?
    let windowTitle: String?
}

protocol AppContextProviding {
    func current() -> AppContext
}
