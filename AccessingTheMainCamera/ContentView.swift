/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An view that displays the main camera feed from Apple Vision Pro in a window.
*/

import SwiftUI
import RealityKit

struct ContentView: View {
    @Environment(AppModel.self) var appModel
    
    var body: some View {
        VStack {
            Text("Main camera access is only available in an immersive space.")
            
            if appModel.immersiveSpaceState == .open {
                MainCameraView()
            } else {
                Image(systemName: "camera")
                    .resizable()
                    .scaledToFit()
            }
            
            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
