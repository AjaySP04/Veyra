//
//  ContentView.swift
//  Veyra
//
//  Created by Ajay Singh Parmar on 31/08/2026.
//

import SwiftUI

struct ContentView: View {
    
    private let audioRecorder = AudioRecorder()
    
    var body: some View {
        
        VStack(spacing: 16) {
            
            Image(systemName: "waveform")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            
            Text("Veyra")
                .font(.title)
            
            Button("Start Recording") {
                do {
                    try audioRecorder.startRecording()
                } catch {
                    print("Failed to start recording: \(error)")
                }
            }
            
            Button("Stop Recording") {
                audioRecorder.stopRecording()
            }
            
        }
        .padding(40)
        .frame(width: 300, height: 250)
    }
}

#Preview {
    ContentView()
}
