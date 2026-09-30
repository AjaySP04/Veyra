protocol TextProcessing {
    func process(_ text: String, mode: DictationMode) async throws -> String
}

struct PassthroughTextProcessor: TextProcessing {
    func process(_ text: String, mode: DictationMode) async throws -> String { mode.finalize(text) }
}
