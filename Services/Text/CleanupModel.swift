import Foundation

struct CleanupModel: Equatable {
    let name: String
    let baseTimeout: Duration
    let timeoutPerWord: Duration

    func timeout(forWordCount wordCount: Int) -> Duration {
        baseTimeout + timeoutPerWord * wordCount
    }

    static let chain = [
        CleanupModel(name: "gemma4:latest", baseTimeout: .seconds(6), timeoutPerWord: .milliseconds(30)),
        CleanupModel(name: "gemma4:cloud", baseTimeout: .seconds(3), timeoutPerWord: .milliseconds(10)),
    ]
}
