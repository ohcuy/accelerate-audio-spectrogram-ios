// Copyright © 2024 Apple Inc.

import Accelerate
import Combine
import AVFoundation
import UIKit

class AudioSpectrogram: NSObject, ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case linear // 전형적인 FFT 결과를 기반, 기계적인 신호 분석에는 적합, 사람의 청각 특성을 반영하지 않음
        case mel // 주파수 축이 멜(Mel) 스케일로 변환, 저역대는 정밀하게, 고역대는 대략적으로 표현, 실제 주파수 정확도는 떨어짐 (물리적 주파수 값은 왜곡됨)
        var id: Self { self }
    }

    @Published var mode = Mode.linear
    @Published var gain: Double = 0.025
    @Published var zeroReference: Double = 1000
    @Published var outputImage = AudioSpectrogram.emptyCGImage

    override init() {
        super.init()
        configureCaptureSession()
        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
    }

    static let sampleCount = 1024
    static let bufferCount = 768
    static let hopCount = 512

    let captureSession = AVCaptureSession()
    let audioOutput = AVCaptureAudioDataOutput()
    let captureQueue = DispatchQueue(label: "captureQueue", qos: .userInitiated)
    let sessionQueue = DispatchQueue(label: "sessionQueue")

    let forwardDCT = vDSP.DCT(count: sampleCount, transformType: .II)!
    let hanningWindow = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: sampleCount, isHalfWindow: false)
    let dispatchSemaphore = DispatchSemaphore(value: 1)

    var nyquistFrequency: Float?
    var rawAudioData = [Int16]()
    var frequencyDomainValues = [Float](repeating: 0, count: bufferCount * sampleCount)

    let redBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: sampleCount, height: bufferCount)
    let greenBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: sampleCount, height: bufferCount)
    let blueBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: sampleCount, height: bufferCount)
    let rgbImageBuffer = vImage.PixelBuffer<vImage.InterleavedFx3>(width: sampleCount, height: bufferCount)

    let rgbImageFormat = vImage_CGImageFormat(bitsPerComponent: 32, bitsPerPixel: 96, colorSpace: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: kCGBitmapByteOrder32Host.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.none.rawValue))!

    var timeDomainBuffer = [Float](repeating: 0, count: sampleCount)
    var frequencyDomainBuffer = [Float](repeating: 0, count: sampleCount)
    lazy var melSpectrogram = MelSpectrogram(sampleCount: AudioSpectrogram.sampleCount)

    func processData(values: [Int16]) {
        vDSP.convertElements(of: values, to: &timeDomainBuffer)
        vDSP.multiply(timeDomainBuffer, hanningWindow, result: &timeDomainBuffer)
        forwardDCT.transform(timeDomainBuffer, result: &frequencyDomainBuffer)
        vDSP.absolute(frequencyDomainBuffer, result: &frequencyDomainBuffer)

        switch mode {
        case .linear:
            vDSP.convert(amplitude: frequencyDomainBuffer, toDecibels: &frequencyDomainBuffer, zeroReference: Float(zeroReference))
        case .mel:
            melSpectrogram.computeMelSpectrogram(values: &frequencyDomainBuffer)
            vDSP.convert(power: frequencyDomainBuffer, toDecibels: &frequencyDomainBuffer, zeroReference: Float(zeroReference))
        }

        vDSP.multiply(Float(gain), frequencyDomainBuffer, result: &frequencyDomainBuffer)

        if frequencyDomainValues.count > AudioSpectrogram.sampleCount {
            frequencyDomainValues.removeFirst(AudioSpectrogram.sampleCount)
        }
        frequencyDomainValues.append(contentsOf: frequencyDomainBuffer)
    }

    func makeAudioSpectrogramImage() -> CGImage {
        frequencyDomainValues.withUnsafeMutableBufferPointer {
            let planarImageBuffer = vImage.PixelBuffer(data: $0.baseAddress!, width: AudioSpectrogram.sampleCount, height: AudioSpectrogram.bufferCount, byteCountPerRow: AudioSpectrogram.sampleCount * MemoryLayout<Float>.stride, pixelFormat: vImage.PlanarF.self)

            AudioSpectrogram.multidimensionalLookupTable.apply(sources: [planarImageBuffer], destinations: [redBuffer, greenBuffer, blueBuffer], interpolation: .half)

            rgbImageBuffer.interleave(planarSourceBuffers: [redBuffer, greenBuffer, blueBuffer])
        }
        return rgbImageBuffer.makeCGImage(cgImageFormat: rgbImageFormat) ?? AudioSpectrogram.emptyCGImage
    }

    static var multidimensionalLookupTable: vImage.MultidimensionalLookupTable = {
        let entriesPerChannel = UInt8(32)
        let srcChannelCount = 1
        let destChannelCount = 3

        let tableData = (0 ..< entriesPerChannel).flatMap { i -> [UInt16] in
            let normalizedValue = CGFloat(i) / CGFloat(entriesPerChannel - 1)
            let hue = 0.6666 - (0.6666 * normalizedValue)
            let brightness = sqrt(normalizedValue)
            let color = UIColor(hue: hue, saturation: 1, brightness: brightness, alpha: 1)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: nil)
            let multiplier = CGFloat(UInt16.max)
            return [UInt16(green * multiplier), UInt16(red * multiplier), UInt16(blue * multiplier)]
        }

        return vImage.MultidimensionalLookupTable(entryCountPerSourceChannel: [entriesPerChannel], destinationChannelCount: destChannelCount, data: tableData)
    }()

    static var emptyCGImage: CGImage = {
        let buffer = vImage.PixelBuffer(pixelValues: [0], size: .init(width: 1, height: 1), pixelFormat: vImage.Planar8.self)
        let fmt = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8, colorSpace: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), renderingIntent: .defaultIntent)
        return buffer.makeCGImage(cgImageFormat: fmt!)!
    }()
}
