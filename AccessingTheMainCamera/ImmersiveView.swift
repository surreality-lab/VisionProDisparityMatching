/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An empty immersive view.
*/

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    var body: some View {
        VStack {
            // empty
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
