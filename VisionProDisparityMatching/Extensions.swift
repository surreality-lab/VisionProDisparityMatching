/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An extension to convert a `CVPixelBuffer` to a SwiftUI `Image`.
*/

import SwiftUI

extension CVPixelBuffer {
    var image: Image? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext(options: nil)
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)

        return Image(uiImage: uiImage)
    }
}
