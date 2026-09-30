protocol TextProcessing {
    func process(_ text: String) async throws -> String
}

struct PassthroughTextProcessor: TextProcessing {
    func process(_ text: String) async throws -> String { text }
}
