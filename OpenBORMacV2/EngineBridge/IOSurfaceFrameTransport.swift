import Foundation
import CoreVideo
import IOSurface
import Darwin

final class IOSurfaceFrameTransport: EngineFrameTransport {
    private let lock = NSLock()
    private let frameInfoURL = V2LaunchConfigurationFactory.bridgeFrameInfoURL()
    private let frameDataURL = V2LaunchConfigurationFactory.bridgeFrameDataURL()
    private(set) var descriptor: FrameTransportDescriptor = FrameTransportDescriptor(
        mode: .ioSurface,
        name: "IOSurface (planned)",
        details: [:]
    )

    private var latestFrame: EngineFramePacket?
    private var surface: IOSurfaceRef?
    private var surfaceID: IOSurfaceID = 0
    private var videoFormat: EngineVideoFormat?
    private var frameInfoLastModifiedAt: Date?
    private var mappedFramePointer: UnsafeMutableRawPointer?
    private var mappedFrameSize: Int = 0
    private var mappedFrameDescriptor: (device: UInt32, inode: UInt64, size: Int)?

    func prepareProducerSide(videoFormat: EngineVideoFormat) throws {
        lock.lock()
        defer { lock.unlock() }

        try? FileManager.default.removeItem(at: frameInfoURL)
        try? FileManager.default.removeItem(at: frameDataURL)
        self.videoFormat = videoFormat
        latestFrame = nil
        surface = makeSurface(width: max(1, videoFormat.width),
                              height: max(1, videoFormat.height),
                              bytesPerElement: max(1, videoFormat.bytesPerPixel))
        surfaceID = surface.map(IOSurfaceGetID) ?? 0
        frameInfoLastModifiedAt = nil
        descriptor = FrameTransportDescriptor(
            mode: .ioSurface,
            name: "IOSurface Bridge",
            details: [
                "surfaceID": "\(surfaceID)",
                "pixelFormat": videoFormat.pixelFormatName,
                "width": "\(videoFormat.width)",
                "height": "\(videoFormat.height)"
            ]
        )
    }

    func publish(_ frame: EngineFramePacket) throws {
        lock.lock()
        defer { lock.unlock() }

        if needsSurfaceRebuild(for: frame.videoFormat) {
            videoFormat = frame.videoFormat
            surface = makeSurface(width: frame.videoFormat.width,
                                  height: frame.videoFormat.height,
                                  bytesPerElement: frame.videoFormat.bytesPerPixel)
            surfaceID = surface.map(IOSurfaceGetID) ?? 0
            descriptor = FrameTransportDescriptor(
                mode: .ioSurface,
                name: "IOSurface Bridge",
                details: [
                    "surfaceID": "\(surfaceID)",
                    "pixelFormat": frame.videoFormat.pixelFormatName,
                    "width": "\(frame.videoFormat.width)",
                    "height": "\(frame.videoFormat.height)"
                ]
            )
        }

        latestFrame = frame

        guard let surface else { return }

        IOSurfaceLock(surface, [], nil)
        defer { IOSurfaceUnlock(surface, [], nil) }

        let destination = IOSurfaceGetBaseAddress(surface)

        frame.bytes.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress else { return }
            let bytesPerRow = frame.videoFormat.width * frame.videoFormat.bytesPerPixel
            let copySize = min(frame.bytes.count, bytesPerRow * frame.videoFormat.height)
            memcpy(destination, sourceBase, copySize)
        }
    }

    func consumeLatestFrame() -> EngineFramePacket? {
        lock.lock()
        refreshVideoFormatFromBridgeInfoLocked()
        refreshLatestFrameFromSharedFileLocked()
        defer { lock.unlock() }
        return latestFrame
    }

    func consumeIOSurfaceFrame() -> IOSurfaceFrameSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        refreshVideoFormatFromBridgeInfoLocked()
        // The allocated bootstrap surface is blank until the producer has
        // published frame metadata; it must not signal that startup is ready.
        guard frameInfoLastModifiedAt != nil || latestFrame != nil else { return nil }
        guard let surface, let videoFormat else { return nil }
        return IOSurfaceFrameSnapshot(surface: surface, videoFormat: videoFormat)
    }

    func reset() {
        lock.lock()
        latestFrame = nil
        surface = nil
        surfaceID = 0
        videoFormat = nil
        frameInfoLastModifiedAt = nil
        closeMappedFrameLocked()
        descriptor = FrameTransportDescriptor(
            mode: .ioSurface,
            name: "IOSurface (planned)",
            details: [:]
        )
        lock.unlock()
        try? FileManager.default.removeItem(at: frameInfoURL)
        try? FileManager.default.removeItem(at: frameDataURL)
    }

    func currentSurfaceID() -> IOSurfaceID {
        lock.lock()
        defer { lock.unlock() }
        return surfaceID
    }

    func frameInfoPath() -> String? {
        frameInfoURL.path
    }

    func frameDataPath() -> String? {
        frameDataURL.path
    }

    private func makeSurface(width: Int, height: Int, bytesPerElement: Int) -> IOSurfaceRef? {
        let pixelFormat: UInt32 = bytesPerElement == 4 ? UInt32(kCVPixelFormatType_32BGRA) : UInt32(kCVPixelFormatType_32RGBA)
        let properties: [CFString: Any] = [
            kIOSurfaceWidth: width,
            kIOSurfaceHeight: height,
            kIOSurfaceBytesPerElement: bytesPerElement,
            kIOSurfaceBytesPerRow: width * bytesPerElement,
            kIOSurfaceIsGlobal: true,
            kIOSurfacePixelFormat: pixelFormat
        ]

        return IOSurfaceCreate(properties as CFDictionary)
    }

    private func needsSurfaceRebuild(for videoFormat: EngineVideoFormat) -> Bool {
        guard let currentFormat = self.videoFormat, let surface else {
            return true
        }

        return currentFormat != videoFormat ||
            IOSurfaceGetWidth(surface) != videoFormat.width ||
            IOSurfaceGetHeight(surface) != videoFormat.height
    }

    private func refreshVideoFormatFromBridgeInfoLocked() {
        let resourceValues = try? frameInfoURL.resourceValues(forKeys: [.contentModificationDateKey])
        if let modifiedAt = resourceValues?.contentModificationDate,
           modifiedAt == frameInfoLastModifiedAt {
            return
        }
        guard let contents = try? String(contentsOf: frameInfoURL, encoding: .utf8) else { return }

        let parts = contents
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard parts.count >= 4,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              let bytesPerPixel = Int(parts[2]),
              width > 0,
              height > 0
        else {
            return
        }

        videoFormat = EngineVideoFormat(
            width: width,
            height: height,
            bytesPerPixel: bytesPerPixel,
            pixelFormatName: parts[3]
        )
        frameInfoLastModifiedAt = resourceValues?.contentModificationDate ?? Date()
    }

    private func refreshLatestFrameFromSharedFileLocked() {
        guard let videoFormat else { return }
        let expectedSize = videoFormat.width * videoFormat.height * videoFormat.bytesPerPixel
        guard expectedSize > 0 else { return }
        guard let frameData = mappedFrameDataLocked(expectedSize: expectedSize) else { return }
        latestFrame = EngineFramePacket(
            videoFormat: videoFormat,
            timestamp: Date().timeIntervalSinceReferenceDate,
            bytes: frameData
        )
    }

    private func mappedFrameDataLocked(expectedSize: Int) -> Data? {
        var fileStats = stat()
        guard stat(frameDataURL.path, &fileStats) == 0 else {
            closeMappedFrameLocked()
            return nil
        }

        let fileSize = Int(fileStats.st_size)
        guard fileSize >= expectedSize else { return nil }

        let device = UInt32(fileStats.st_dev)
        let inode = UInt64(fileStats.st_ino)
        let descriptor = (device: device, inode: inode, size: fileSize)

        let needsRemap = mappedFrameDescriptor?.device != descriptor.device ||
            mappedFrameDescriptor?.inode != descriptor.inode ||
            mappedFrameDescriptor?.size != descriptor.size ||
            mappedFramePointer == nil ||
            mappedFrameSize < expectedSize

        if needsRemap {
            closeMappedFrameLocked()

            let fd = open(frameDataURL.path, O_RDONLY)
            guard fd >= 0 else { return nil }
            defer { close(fd) }

            let protection = PROT_READ
            let flags = MAP_SHARED
            guard let pointer = mmap(nil, fileSize, protection, flags, fd, 0), pointer != MAP_FAILED else {
                return nil
            }

            mappedFramePointer = pointer
            mappedFrameSize = fileSize
            mappedFrameDescriptor = descriptor
        }

        guard let mappedFramePointer else { return nil }
        return Data(bytes: mappedFramePointer, count: expectedSize)
    }

    private func closeMappedFrameLocked() {
        if let mappedFramePointer, mappedFrameSize > 0 {
            munmap(mappedFramePointer, mappedFrameSize)
        }
        mappedFramePointer = nil
        mappedFrameSize = 0
        mappedFrameDescriptor = nil
    }
}
