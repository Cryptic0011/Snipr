import Foundation

enum ImagePresentationGeometry {
    static func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale

        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func imagePoint(from viewPoint: CGPoint, imageSize: CGSize, displayRect: CGRect) -> CGPoint? {
        guard displayRect.contains(viewPoint), imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        return CGPoint(
            x: (viewPoint.x - displayRect.minX) / displayRect.width * imageSize.width,
            y: (viewPoint.y - displayRect.minY) / displayRect.height * imageSize.height
        )
    }

    static func viewPoint(from imagePoint: CGPoint, imageSize: CGSize, displayRect: CGRect) -> CGPoint {
        CGPoint(
            x: displayRect.minX + imagePoint.x / imageSize.width * displayRect.width,
            y: displayRect.minY + imagePoint.y / imageSize.height * displayRect.height
        )
    }

    static func viewRect(from imageRect: CGRect, imageSize: CGSize, displayRect: CGRect) -> CGRect {
        let origin = viewPoint(from: imageRect.origin, imageSize: imageSize, displayRect: displayRect)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: imageRect.width / imageSize.width * displayRect.width,
            height: imageRect.height / imageSize.height * displayRect.height
        )
    }
}
