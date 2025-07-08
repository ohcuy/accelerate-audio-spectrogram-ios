//
//  ContentView.swift
//  accelerate-audio-spectrogram-ios
//
//  Created by 조유진 on 7/8/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioSpectrogram: AudioSpectrogram

    var body: some View {
        VStack {
            Image(decorative: audioSpectrogram.outputImage, scale: 1, orientation: .left)
                .resizable()

            VStack {
                // 주파수 도메인에서 데시벨 값에 곱해져서 시각적으로 얼마나 밝게/강하게 표현할지를 조절하는 스케일 계수 = 이미지 밝기 조절
                Text("Gain")
                Slider(value: $audioSpectrogram.gain, in: 0.01 ... 0.04)
                Divider().frame(height: 40)
                // vDSP.convert에 사용되는 0dB 기준값, 신호를 데시벨(dB) 스케일로 변환할 때 기준이 되는 참조값 = 음성의 상대 세기 비교 기준
                Text("Zero Ref")
                Slider(value: $audioSpectrogram.zeroReference, in: 10 ... 2500)
                Divider().frame(height: 40)
                Picker("Mode", selection: $audioSpectrogram.mode) {
                    ForEach(AudioSpectrogram.Mode.allCases) { mode in
                        Text(mode.rawValue.capitalized)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding()
        }
    }
}
