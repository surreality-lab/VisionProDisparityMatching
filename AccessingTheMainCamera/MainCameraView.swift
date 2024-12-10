/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the left main camera frame from Apple Vision Pro.
*/

import ARKit
import RealityKit
import SwiftUI

struct MainCameraView: View {
    @State private var arkitSession = ARKitSession()
    @State private var pixelBuffer: CVPixelBuffer?
    
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
            let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left])
        
            // Find the highest resolution format.
            let highResolutionFormat = formats.max { $0.frameSize.height < $1.frameSize.height }

            // Request an asynchronous sequence of camera frames.
            guard let highResolutionFormat,
                  let cameraFrameUpdates = cameraFrameProvider.cameraFrameUpdates(for: highResolutionFormat) else {
                return
            }
            
            for await cameraFrame in cameraFrameUpdates {
                if let sample = cameraFrame.sample(for: .left) {
                    
                    // Update the `pixelBuffer` to render the frame's image.
                    pixelBuffer = sample.pixelBuffer

                }

            }
        }
    }
}
