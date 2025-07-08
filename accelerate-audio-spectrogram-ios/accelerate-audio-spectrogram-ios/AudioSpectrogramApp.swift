//
//  AudioSpectrogramApp.swift
//  accelerate-audio-spectrogram-ios
//
//  Created by 조유진 on 7/8/25.
//

import SwiftUI

@main
struct AudioSpectrogramApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let audioSpectrogram = AudioSpectrogram()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioSpectrogram)
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Task(priority: .userInitiated) {
                            audioSpectrogram.startRunning()
                        }
                    }
                }
        }
    }
}
