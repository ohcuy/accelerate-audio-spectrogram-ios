// Copyright © 2024 Apple Inc.

import AVFoundation

extension AudioSpectrogram: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &audioBufferList, bufferListSize: MemoryLayout.stride(ofValue: audioBufferList), blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer)

        guard let data = audioBufferList.mBuffers.mData else { return }

        if nyquistFrequency == nil {
            let duration = Float(CMSampleBufferGetDuration(sampleBuffer).value)
            let timescale = Float(CMSampleBufferGetDuration(sampleBuffer).timescale)
            let numsamples = Float(CMSampleBufferGetNumSamples(sampleBuffer))
            nyquistFrequency = 0.5 / (duration / timescale / numsamples)
        }

        if rawAudioData.count < AudioSpectrogram.sampleCount * 2 {
            let actualSampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
            let pointer = data.bindMemory(to: Int16.self, capacity: actualSampleCount)
            let buffer = UnsafeBufferPointer(start: pointer, count: actualSampleCount)
            rawAudioData.append(contentsOf: Array(buffer))
        }

        while rawAudioData.count >= AudioSpectrogram.sampleCount {
            let dataToProcess = Array(rawAudioData[0 ..< AudioSpectrogram.sampleCount])
            rawAudioData.removeFirst(AudioSpectrogram.hopCount)
            processData(values: dataToProcess)
        }

        DispatchQueue.main.async {
            self.outputImage = self.makeAudioSpectrogramImage()
        }
    }

    func configureCaptureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    fatalError("App requires microphone access.")
                } else {
                    self.configureCaptureSession()
                    self.sessionQueue.resume()
                }
            }
            return
        default:
            fatalError("App requires microphone access.")
        }

        captureSession.beginConfiguration()

        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        } else {
            fatalError("Can't add audioOutput.")
        }

        guard let microphone = AVCaptureDevice.default(for: .audio),
              let microphoneInput = try? AVCaptureDeviceInput(device: microphone) else {
            fatalError("Can't access microphone.")
        }

        if captureSession.canAddInput(microphoneInput) {
            captureSession.addInput(microphoneInput)
        }

        captureSession.commitConfiguration()
    }

    func startRunning() {
        sessionQueue.async {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                self.captureSession.startRunning()
            }
        }
    }
}
