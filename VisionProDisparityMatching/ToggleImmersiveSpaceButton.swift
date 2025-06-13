/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A button to open and dismiss an immersive space.
*/

import SwiftUI

struct ToggleImmersiveSpaceButton: View {
    @Environment(AppModel.self) private var appModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.immersiveSpaceState {
                    case .open:
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        // Don't set `immersiveSpaceState` to `.closed` because there
                        // are multiple paths to `ImmersiveView.onDisappear()`.
                        // Only set `.closed` in `ImmersiveView.onDisappear()`.

                    case .closed:
                        appModel.immersiveSpaceState = .inTransition
                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                            case .opened:
                                // Don't set `immersiveSpaceState` to `.open` because there
                                // may be multiple paths to `ImmersiveView.onAppear()`.
                                // Only set `.open` in `ImmersiveView.onAppear()`.
                                break

                            case .userCancelled, .error:
                                // On error, mark the immersive space
                                // as closed because it failed to open.
                                fallthrough
                            @unknown default:
                                // On unknown response, assume the immersive space didn't open.
                                appModel.immersiveSpaceState = .closed
                        }

                    case .inTransition:
                        // This case can't ever happen because the button is disabled for this case.
                        break
                }
            }
        } label: {
            Text(appModel.immersiveSpaceState == .open ? "Hide Immersive Space" : "Show Immersive Space")
        }
        .disabled(appModel.immersiveSpaceState == .inTransition)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
    }
}
