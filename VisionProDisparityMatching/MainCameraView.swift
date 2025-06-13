/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the left main camera frame from Apple Vision Pro.
*/

import ARKit
import RealityKit
import SwiftUI
import CoreML
import Accelerate

struct MainCameraView: View {
    @State private var arkitSession = ARKitSession()
    @State private var pixelBuffer: CVPixelBuffer?
    
    @State private var pixelBufferPool: CVPixelBufferPool?
    @State private var stackedBufferPool: CVPixelBufferPool?
    private let ciContext = CIContext()
    
    private var model : RaftStereo512?;
    
    private func rescaleImage(pixelBuffer: CVPixelBuffer) -> (CVPixelBuffer, Float, Int, Int)? {
        if (pixelBufferPool == nil) {
            // Allocate said pool
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 512,
                kCVPixelBufferHeightKey as String: 512,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pixelBufferPool);
        }
        
        guard let pool = pixelBufferPool else {
            return nil;
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let cropSize = min(sourceWidth, sourceHeight)
        let cropX = (sourceWidth - cropSize) / 2
        let cropY = (sourceHeight - cropSize) / 2
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropSize, height: cropSize)
        let croppedImage = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: cropRect)

        // Translate to origin BEFORE scaling
        let scale = 512.0 / CGFloat(cropSize)
        let translate = CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

        let ciImage = croppedImage.transformed(by: translate.concatenating(scaleTransform))
        
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        
        guard let output = outputBuffer else {
            print("Failed to allocate CVPixelBuffer from CVPixelBufferPool")
            return nil
        }
        
        ciContext.render(ciImage, to: output, bounds: CGRect(x: 0, y: 0, width: 512, height: 512), colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return (output, 512.0 / Float(cropSize), cropX, cropY);
    }
    
    private func findMinMax(of multiArray: MLMultiArray) -> (Float, Float)? {
        guard multiArray.dataType == .float32 else {
            print("Unsupported MLMultiArray type")
            return nil
        }

        let count = multiArray.count
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
        let buffer = UnsafeBufferPointer(start: ptr, count: count)

        var minVal: Float = 0
        var maxVal: Float = 0

        vDSP_minv(buffer.baseAddress!, 1, &minVal, vDSP_Length(count))
        vDSP_maxv(buffer.baseAddress!, 1, &maxVal, vDSP_Length(count))

        return (minVal, maxVal)
    }
    
    func multiArrayToRGBA(_ multiArray: MLMultiArray) -> CVPixelBuffer? {
        if (pixelBufferPool == nil) {
            // Allocate said pool
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 512,
                kCVPixelBufferHeightKey as String: 512,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pixelBufferPool);
        }
        
        guard let pool = pixelBufferPool else {
            return nil;
        }
        
        guard multiArray.dataType == .float32,
              multiArray.shape.count == 4,
              multiArray.shape[0].intValue == 1,
              multiArray.shape[1].intValue == 1 else {
            print("Unsupported shape or type")
            return nil
        }

        let height = multiArray.shape[2].intValue
        let width = multiArray.shape[3].intValue
        let count = width * height

        // Bind to float32 pointer
        let floatPtr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
        let buffer = UnsafeBufferPointer(start: floatPtr, count: count)

        // Find min/max
        var minVal: Float = 0
        var maxVal: Float = 0
        vDSP_minv(floatPtr, 1, &minVal, vDSP_Length(count))
        vDSP_maxv(floatPtr, 1, &maxVal, vDSP_Length(count))

        let range = maxVal - minVal
        if range == 0 {
            print("Uniform values — cannot scale")
            return nil
        }

        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

        guard let bufferOut = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(bufferOut, [])
        defer { CVPixelBufferUnlockBaseAddress(bufferOut, []) }

        let outBase = CVPixelBufferGetBaseAddress(bufferOut)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(bufferOut)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let value = buffer[i]

                // Normalize to [0, 1]
                let norm = (value - minVal) / range
                let scaled = UInt8(clamping: Int(norm * 255))

                let pixelPtr = outBase + y * bytesPerRow + x * 4
                pixelPtr[0] = scaled     // R
                pixelPtr[1] = scaled     // G
                pixelPtr[2] = scaled     // B
                pixelPtr[3] = 255        // A (fully opaque)
            }
        }

        return bufferOut
    }


    
    private func ensureStackedBufferPool(width: Int, height: Int) {
        if stackedBufferPool != nil { return }

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]

        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        stackedBufferPool = pool
    }
    
    private func stackPixelBuffers(left: CVPixelBuffer, right: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(left) + CVPixelBufferGetWidth(right)
        let height = CVPixelBufferGetHeight(left)

        ensureStackedBufferPool(width: width, height: height)

        guard let pool = stackedBufferPool else { return nil }

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)

        guard status == kCVReturnSuccess, let output = outputBuffer else {
            print("Failed to allocate from stackedBufferPool")
            return nil
        }

        
        CVPixelBufferLockBaseAddress(left, .readOnly)
        CVPixelBufferLockBaseAddress(right, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])

        defer {
            CVPixelBufferUnlockBaseAddress(left, .readOnly)
            CVPixelBufferUnlockBaseAddress(right, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        let leftBase = CVPixelBufferGetBaseAddress(left)!
        let rightBase = CVPixelBufferGetBaseAddress(right)!
        let outBase = CVPixelBufferGetBaseAddress(output)!
        
        let leftBytesPerRow = CVPixelBufferGetBytesPerRow(left)
        let rightBytesPerRow = CVPixelBufferGetBytesPerRow(right)
        let outBytesPerRow = CVPixelBufferGetBytesPerRow(output)

        for row in 0..<height {
            let leftRow = leftBase.advanced(by: row * leftBytesPerRow)
            let rightRow = rightBase.advanced(by: row * rightBytesPerRow)
            let outRow = outBase.advanced(by: row * outBytesPerRow)
            
            memcpy(outRow, leftRow, leftBytesPerRow)
            memcpy(outRow.advanced(by: leftBytesPerRow), rightRow, rightBytesPerRow)
        }

        return output
    }
    
    let emptyImage = Image(systemName: "camera")

    var body: some View {
        let image = pixelBuffer?.image ?? emptyImage
        
        image
        .resizable()
        .scaledToFit()
        .task {
            
            // Check whether there's support for camera access; otherwise, handle this case.
            guard CameraFrameProvider.isSupported else {
                print("CameraFrameProvider is not supported.")
                
                return
            }
            
            let cameraFrameProvider = CameraFrameProvider()

            try? await arkitSession.run([cameraFrameProvider])
            
            // Read the video formats that the left main camera supports.
            let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left, .right])
            for format in formats {
                print(format)
            }
        
            var chosenFormat : CameraVideoFormat?
            // Find the highest resolution format.
            for format in formats {
                if format.cameraRectification == .stereoCorrected {
                    chosenFormat = format
                    break
                }
            }

            // Request an asynchronous sequence of camera frames.
            guard let chosenFormat,
                  let cameraFrameUpdates = cameraFrameProvider.cameraFrameUpdates(for: chosenFormat) else {
                return
            }
            
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndGPU  // or .gpuOnly, see below
            
            guard let mlModel = model ?? (try? RaftStereo512(configuration: config)) else {
                return
            }

            
            for await cameraFrame in cameraFrameUpdates {
                if let lSample = cameraFrame.sample(for: .left), let rSample = cameraFrame.sample(for: .right) {
                    let lRescaled = rescaleImage(pixelBuffer: lSample.pixelBuffer)
                    let rRescaled = rescaleImage(pixelBuffer: rSample.pixelBuffer)
                    
                    guard let pred = try? await mlModel.prediction(input: RaftStereo512Input(left_: lRescaled!.0, right_: rRescaled!.0)) else {
                        print("Could not make inference")
                        continue
                    }
                    guard let depth = multiArrayToRGBA(pred.var_4967) else {
                        print("Could not convert!")
                        continue
                    }
                    let stacked = stackPixelBuffers(left: lRescaled!.0, right: depth)
                    pixelBuffer = stacked;
                }

            }
        }
    }
}
