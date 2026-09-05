//
//  AudioRecorder.swift
//  Veyra
//
//  Created by Ajay Singh Parmar on 01/09/2026.
//

import AVFoundation

final class AudioRecorder {
    
    private let audioEngine: AVAudioEngine
    private var audioFile: AVAudioFile?
    
    init() {
        self.audioEngine = AVAudioEngine()
//        self.audioFile = AVAudioFile()
    }
    
    func startRecording() throws {
        let inputNode = audioEngine.inputNode

        let inputFormat = inputNode.inputFormat(forBus: 0)

        print("Sample rate: \(inputFormat.sampleRate)")
        print("Channels: \(inputFormat.channelCount)")

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat
        ) {
            buffer, _ in
            print("🔊 Received audio buffer")
            print("Frames: \(buffer.frameLength)")
        }
        
        
        try audioEngine.start()
        
        print("🎙️ Recording started...")
        
    }
    
    func stopRecording() {
        let inputNode = audioEngine.inputNode
        
        inputNode.removeTap(onBus: 0)
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        print("🛑 Audio engine stopped")
    }
}
