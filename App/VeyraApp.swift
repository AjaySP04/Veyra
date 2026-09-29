//
//  VeyraApp.swift
//  Veyra
//
//  Created by Ajay Singh Parmar on 31/08/2026.
//

import SwiftUI
import AppKit

@main
struct VeyraApp: App {
    var body: some Scene {
        
        let appTitle: String = "Veyra"
        
        MenuBarExtra(appTitle, systemImage: "mic") {
            
            let closeButtonLabel: String = "Quit Veyra"
            Button(closeButtonLabel) {
                NSApplication.shared.terminate(nil)
            }
            
        }

    }
}
