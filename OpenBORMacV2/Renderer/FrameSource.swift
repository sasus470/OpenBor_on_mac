import Foundation

struct FramebufferImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]
}

protocol FrameSource {
    func makeFrame(time: TimeInterval, drawableWidth: Int, drawableHeight: Int) -> FramebufferImage
}
