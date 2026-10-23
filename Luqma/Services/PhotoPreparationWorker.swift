import UIKit
import os

/// Serial CPU work away from MainActor. Original input, analysis resolution,
/// JPEG quality and the approved artwork remain unchanged. Cancellation before
/// and after each noninterruptible codec call rejects obsolete photo results.
actor PhotoPreparationWorker {
    static let shared=PhotoPreparationWorker()
    private let signposter=OSSignposter(subsystem:"app.luqma.diary",category:"PhotoPreparation")
    func preview(_ data:Data)throws->UIImage {
        try Task.checkCancellation()
        let span=signposter.beginInterval("PreviewPreparation")
        defer{signposter.endInterval("PreviewPreparation",span)}
        let image=UIImage(cgImage:try PhotoAnalyzer.image(data,maxPixels:640))
        let prepared=image.preparingForDisplay() ?? image
        try Task.checkCancellation()
        return prepared
    }
    func cameraJPEG(_ image:UIImage)throws->Data? {
        try Task.checkCancellation()
        let span=signposter.beginInterval("CameraJPEG")
        defer{signposter.endInterval("CameraJPEG",span)}
        let data=image.jpegData(compressionQuality:0.85)
        try Task.checkCancellation()
        return data
    }
}
