import AppKit
import SwiftUI

enum V2LaunchConfigurationFactory {
    static func rewindDirectoryURL() -> URL {
        URL(fileURLWithPath: "/tmp/openbor-rewind-preview-test")
    }
}

@main
struct RewindTimelineTest {
    static func main() throws {
        let directory = V2LaunchConfigurationFactory.rewindDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "300 200\n2 1 200\n1 0 100\n3 -1 50\n".write(to: directory.appendingPathComponent("index.txt"), atomically: true, encoding: .utf8)
        for slot in 0...1 {
            let path = directory.appendingPathComponent(String(format: "frame-%02d", slot)).path
            try "2 2 4 BGRA8\n".write(toFile: path + ".info", atomically: true, encoding: .utf8)
            try Data([30, 60, 120, 0, 30, 60, 120, 0, 30, 60, 120, 0, 30, 60, 120, 0])
                .write(to: URL(fileURLWithPath: path + ".preview"))
        }
        let checkpoints = RewindCheckpoint.loadHistory()
        precondition(checkpoints.count == 2 && checkpoints[0].age == 1 && checkpoints[1].age == 0.5,
                     "Oldest checkpoint must be on the left, newest on the right")
        let image = checkpoints[0].image!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let pixel = NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        precondition(abs(pixel.redComponent - 120.0 / 255) < 0.02 && pixel.alphaComponent == 1,
                     "Unused alpha must not hide OpenBOR previews")
        let model = RewindTimelineModel()
        precondition(model.showsEmptyHistory)
        model.isLoadingHistory = true
        precondition(!model.showsEmptyHistory, "Loading is not an empty history")
        var prematureSelection: UInt64?
        model.selectedID = checkpoints.last?.id
        model.onSelect = { prematureSelection = $0 }
        model.applySelected()
        precondition(prematureSelection == nil, "Opening must not apply a stale selection")
        model.isLoadingHistory = false
        let cue = RewindMenuSound.make(duration: 0.09, start: 740, end: 980)
        precondition(cue != nil && abs(cue!.duration - 0.09) < 0.01, "Navigation cue must be a valid short audio clip")
        model.playsSounds = false
        model.checkpoints = checkpoints
        precondition(!model.showsEmptyHistory)
        model.selectedID = checkpoints[0].id
        model.move(1)
        precondition(model.selectedID == checkpoints[1].id)
        var selected: UInt64?
        model.onSelect = { selected = $0 }
        model.select(checkpoints[0].id)
        precondition(selected == nil && model.selectedCheckpoint?.id == checkpoints[0].id,
                     "Preview selection must not apply a rewind")
        model.move(1)
        model.applySelected()
        precondition(selected == checkpoints[1].id)
        model.isApplying = true
        model.move(-1)
        precondition(model.selectedID == checkpoints[1].id)
        print("PASS: chronological rail, opaque previews, non-destructive selection and guarded confirmation.")
    }
}
