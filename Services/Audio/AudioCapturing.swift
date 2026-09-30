import Foundation

protocol AudioCapturing: AnyObject {
    var levelHandler: ((Float) -> Void)? { get set }
    func start() throws
    func stop() -> [Float]
}

nonisolated enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone available"
        case .unsupportedFormat: "Microphone format not supported"
        }
    }
}
