import Foundation

struct CleanupModel: Equatable {
    let name: String
    let timeout: Duration

    static let chain = [
        CleanupModel(name: "gemma4:latest", timeout: .seconds(6)),
        CleanupModel(name: "gemma4:cloud", timeout: .seconds(3)),
    ]
}
