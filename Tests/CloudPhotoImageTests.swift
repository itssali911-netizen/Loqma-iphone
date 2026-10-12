#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LuqmaCore

final class CloudPhotoImageTests: XCTestCase {
    func testUploadImageHasAppliedOrientationLimitedResolutionAndNoSourceLocation() throws {
        let width = 1800, height = 900
        let pixels = [UInt8](repeating: 180, count: width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                         bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let original = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 21.5, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 39.2, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Private source comment"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Private source author"]
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(original as Data as CFData, nil))
        let before = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary])
        let jpeg = try CloudPhotoImage.jpeg(original as Data)
        let upload = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let after = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(upload, 0, nil) as? [CFString: Any])
        XCTAssertNil(after[kCGImagePropertyGPSDictionary])
        XCTAssertNil((after[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment])
        XCTAssertNil((after[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFArtist])
        let resized = try XCTUnwrap(CGImageSourceCreateImageAtIndex(upload, 0, nil))
        XCTAssertLessThanOrEqual(max(resized.width, resized.height), 1600)
        XCTAssertGreaterThan(resized.height, resized.width)
        XCTAssertLessThanOrEqual(jpeg.count, GeminiMeal.maxImageBytes)
    }
    func testEmptyCorruptAndOversizedSourceImagesAreRejected() {
        for data in [Data(), Data("not an image".utf8), Data(repeating: 0, count: 40 * 1024 * 1024 + 1)] {
            XCTAssertThrowsError(try CloudPhotoImage.jpeg(data))
        }
    }
}
#endif
