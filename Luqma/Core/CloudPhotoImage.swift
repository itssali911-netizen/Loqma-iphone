#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CloudPhotoImage {
    /// Apply orientation and encode a new JPEG without source EXIF/GPS/IPTC/TIFF.
    static func jpeg(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else {
            throw AppError.invalid("تعذّر فتح الصورة. اختر JPEG أو PNG أو HEIC أصغر من ٤٠ ميجابايت.",
                                   "Could not open the photo. Choose a JPEG, PNG or HEIC smaller than 40 MB.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw GeminiMeal.invalid }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= GeminiMeal.maxImageBytes else { throw GeminiMeal.invalid }
        return output as Data
    }
}
#endif
