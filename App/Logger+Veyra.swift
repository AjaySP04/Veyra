import os

nonisolated extension Logger {
    static let audio = Logger(subsystem: "com.ajaysparmar.Veyra", category: "audio")
    static let dictation = Logger(subsystem: "com.ajaysparmar.Veyra", category: "dictation")
    static let cleanup = Logger(subsystem: "com.ajaysparmar.Veyra", category: "cleanup")
    static let agent = Logger(subsystem: "com.ajaysparmar.Veyra", category: "agent")
}
