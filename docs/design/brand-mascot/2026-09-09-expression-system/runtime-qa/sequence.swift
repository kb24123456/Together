import Foundation
import Metal
import AppKit
import ImageIO
import UniformTypeIdentifiers
import RiveRuntime
import AVFoundation
import CryptoKit

struct Story: Decodable {
    var name: String
    var artboard: String?
    var stateMachine: String?
    var viewModel: String?
    var fps: Int?
    var frames: Int
    var width: Int?
    var height: Int?
    var pngEvery: Int?
    var pngFrames: [Int]?
    var video: Bool?
    var backgroundARGB: String?
    var events: [Event]
}
struct Event: Codable {
    var frame: Int
    var label: String?
    var numbers: [String: Float]?
    var booleans: [String: Bool]?
    var triggers: [String]?
    var colors: [String: String]?
}
struct ProbeFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ProbeFailure(message: message) }
}
func hex(_ string: String) throws -> UInt32 {
    let trimmed = string.replacingOccurrences(of: "#", with: "")
    guard let value = UInt32(trimmed, radix: 16), trimmed.count == 8 else {
        throw ProbeFailure(message: "Expected 8 hex ARGB digits: \(string)")
    }
    return value
}
func writeJSON(_ object: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

@main struct SequenceProbe {
    @MainActor static func main() async throws {
        try require(CommandLine.arguments.count == 4, "Usage: render-sequence asset.riv story.json output-directory")
        let assetURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let storyURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try require(!FileManager.default.fileExists(atPath: outputURL.path), "Output directory already exists; choose a fresh path: \(outputURL.path)")
        let assetData = try Data(contentsOf: assetURL)
        let storyData = try Data(contentsOf: storyURL)
        let story = try JSONDecoder().decode(Story.self, from: storyData)
        let fps = story.fps ?? 60
        let width = story.width ?? 512
        let height = story.height ?? width
        let pngEvery = story.pngEvery ?? 30
        let artboardName = story.artboard ?? "TogetherSphere"
        let machineName = story.stateMachine ?? "Mascot"
        let modelName = story.viewModel ?? "TogetherSphereModel"
        let background = try hex(story.backgroundARGB ?? "FFFAFAFA")
        try require(fps > 0 && fps <= 240 && story.frames > 0 && width > 0 && height > 0 && pngEvery >= 0, "Invalid size, fps, frames or pngEvery")
        try require(story.events.allSatisfy { $0.frame >= 0 && $0.frame < story.frames }, "An event frame lies outside the sequence")
        let eventsByFrame = Dictionary(grouping: story.events, by: \.frame)

        // A second, official inspection instance provides state-change traces.
        // It is intentionally identified separately from the rendered instance:
        // independent random choices can differ between the two native instances.
        let inspectionFile = try RiveFile(data: assetData, loadCdn: false)
        let inspectionBoard = try inspectionFile.artboard(fromName: artboardName)
        let inspectionMachine = try inspectionBoard.stateMachine(fromName: machineName)
        guard let inspectionModel = inspectionFile.viewModelNamed(modelName),
              let inspectionInstance = inspectionModel.createDefaultInstance() else {
            throw ProbeFailure(message: "Missing view model or default instance: \(modelName)")
        }
        inspectionBoard.bind(viewModelInstance: inspectionInstance)
        inspectionMachine.bind(viewModelInstance: inspectionInstance)
        for event in story.events {
            for key in event.numbers?.keys ?? Dictionary<String,Float>().keys {
                try require(inspectionInstance.numberProperty(fromPath: key) != nil, "Missing Number property: \(key)")
            }
            for key in event.booleans?.keys ?? Dictionary<String,Bool>().keys {
                try require(inspectionInstance.booleanProperty(fromPath: key) != nil, "Missing Bool property: \(key)")
            }
            for key in event.triggers ?? [] {
                try require(inspectionInstance.triggerProperty(fromPath: key) != nil, "Missing Trigger property: \(key)")
            }
            for (key, value) in event.colors ?? [:] {
                try require(inspectionInstance.colorProperty(fromPath: key) != nil, "Missing Color property: \(key)")
                _ = try hex(value)
            }
        }

        let device = MTLCreateSystemDefaultDevice()!
        let worker = Worker(device: device)
        let file = try await RiveRuntime.File(source: .data(assetData), worker: worker)
        let board = try await file.createArtboard(artboardName)
        let machine = try await board.createStateMachine(machineName)
        let instance = try await file.createViewModelInstance(.viewModelDefault(from: .name(modelName)))
        let rive = try await Rive(file: file, artboard: board, stateMachine: machine,
            dataBind: .instance(instance), backgroundColor: RiveRuntime.Color(background))
        let renderer = rive.makeRenderer()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw ProbeFailure(message: "Cannot allocate Metal texture") }
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try storyData.write(to: outputURL.appendingPathComponent("story.json"))

        var writer: AVAssetWriter?
        var videoInput: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        if story.video ?? true {
            try require(width % 2 == 0 && height % 2 == 0, "H264 video dimensions must be even")
            writer = try AVAssetWriter(outputURL: outputURL.appendingPathComponent("preview.mov"), fileType: .mov)
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
            videoInput!.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput!, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
            writer!.add(videoInput!)
            try require(writer!.startWriting(), writer!.error?.localizedDescription ?? "Cannot start video writer")
            writer!.startSession(atSourceTime: .zero)
        }
        var pixelFrames: [[String: Any]] = []
        var pngPaths: [String] = []
        var drawCount = 0
        var skipCount = 0
        for frame in 0..<story.frames {
            for event in eventsByFrame[frame] ?? [] {
                for (key,value) in event.numbers ?? [:] { instance.setValue(of: NumberProperty(path: key), to: value) }
                for (key,value) in event.booleans ?? [:] { instance.setValue(of: BoolProperty(path: key), to: value) }
                for (key,value) in event.colors ?? [:] { instance.setValue(of: ColorProperty(path: key), to: RiveRuntime.Color(try hex(value))) }
                for key in event.triggers ?? [] { instance.fire(trigger: TriggerProperty(path: key)) }
            }
            machine.advance(by: 1.0 / Double(fps))
            var configuration = RiveUIRendererConfiguration(rive: rive, drawableSize: CGSize(width: width, height: height))
            configuration.pixelFormat = texture.pixelFormat
            let drawn = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                renderer.draw(configuration, to: texture, from: device, onDraw: { buffer in
                    buffer.addCompletedHandler { completed in
                        if let error = completed.error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: true) }
                    }
                }, onSkipped: { continuation.resume(returning: false) }, onError: { continuation.resume(throwing: $0) })
            }
            try require(frame != 0 || drawn, "First frame was skipped before the texture was initialized")
            if drawn { drawCount += 1 } else { skipCount += 1 }
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let data = Data(bytes)
            pixelFrames.append(["frame":frame,"timeAfterAdvance":Double(frame+1)/Double(fps),"gpuDrawn":drawn,"pixelSHA256":hash(data)])
            if let writer, let videoInput, let adaptor {
                while !videoInput.isReadyForMoreMediaData {
                    try require(writer.status == .writing, writer.error?.localizedDescription ?? "Video writer stopped")
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                var pixelBuffer: CVPixelBuffer?
                try require(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer) == kCVReturnSuccess, "Pixel buffer allocation failed")
                let pixels = pixelBuffer!
                CVPixelBufferLockBaseAddress(pixels, [])
                let stride = CVPixelBufferGetBytesPerRow(pixels)
                let target = CVPixelBufferGetBaseAddress(pixels)!
                data.withUnsafeBytes { source in
                    for row in 0..<height { target.advanced(by: row*stride).copyMemory(from: source.baseAddress!.advanced(by: row*width*4), byteCount: width*4) }
                }
                CVPixelBufferUnlockBaseAddress(pixels, [])
                try require(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))), writer.error?.localizedDescription ?? "Cannot append video frame")
            }
            let explicitFrames = story.pngFrames ?? []
            if (pngEvery > 0 && frame % pngEvery == 0) || explicitFrames.contains(frame) || frame == story.frames-1 {
                let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                    provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
                let name = String(format:"frame-%05d.png",frame)
                let url = outputURL.appendingPathComponent(name)
                let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(destination,image,nil)
                try require(CGImageDestinationFinalize(destination),"Cannot write PNG")
                pngPaths.append(name)
            }
        }
        if let writer, let videoInput {
            videoInput.markAsFinished()
            await writer.finishWriting()
            try require(writer.status == .completed,writer.error?.localizedDescription ?? "Video finalization failed")
        }
        var stateChanges: [[String:Any]] = []
        for frame in 0..<story.frames {
            for event in eventsByFrame[frame] ?? [] {
                for (key,value) in event.numbers ?? [:] { inspectionInstance.numberProperty(fromPath:key)!.value=value }
                for (key,value) in event.booleans ?? [:] { inspectionInstance.booleanProperty(fromPath:key)!.value=value }
                for (key,value) in event.colors ?? [:] {
                    let argb=try hex(value)
                    inspectionInstance.colorProperty(fromPath:key)!.value=NSColor(srgbRed:CGFloat((argb>>16)&255)/255,
                        green:CGFloat((argb>>8)&255)/255,blue:CGFloat(argb&255)/255,alpha:CGFloat((argb>>24)&255)/255)
                }
                for key in event.triggers ?? [] { inspectionInstance.triggerProperty(fromPath:key)!.trigger() }
            }
            _ = inspectionMachine.advance(by:1.0/Double(fps))
            let changes=inspectionMachine.stateChanges()
            if !changes.isEmpty { stateChanges.append(["frame":frame,"timeAfterAdvance":Double(frame+1)/Double(fps),"states":changes]) }
            inspectionMachine.viewModelInstance?.updateListeners()
        }
        let eventData=try JSONEncoder().encode(story.events)
        let eventObjects=try JSONSerialization.jsonObject(with:eventData)
        try writeJSON([
            "story":story.name,"asset":assetURL.path,"assetSHA256":hash(assetData),"runtime":"Rive Apple Runtime 6.25.1",
            "artboard":artboardName,"stateMachine":machineName,"viewModel":modelName,"fps":fps,"frames":story.frames,
            "width":width,"height":height,"gpuDrawnFrames":drawCount,"gpuSkippedUnchangedFrames":skipCount,
            "distinctPixelFrames":Set(pixelFrames.compactMap{$0["pixelSHA256"] as? String}).count,
            "renderedInstanceInputEvents":eventObjects,"renderedInstancePixelFrames":pixelFrames,"pngs":pngPaths,
            "inspectionReplayStateChanges":stateChanges,
            "traceBoundary":"The official new Metal Worker API does not expose stateChanges. inspectionReplayStateChanges comes from a separate official legacy inspection instance replaying the same inputs. Random branches may differ. It is not the rendered instance's state trace.",
            "limits":["Offline native rendering proves actual frame content and transitions, not wall-clock performance.","No iOS Simulator or device used.","No automatic visual-quality or new-animation pass claim is made."]
        ],to:outputURL.appendingPathComponent("evidence.json"))
        print("Rendered \(story.frames) native frames, \(pngPaths.count) PNGs, \(drawCount) GPU draws, \(skipCount) unchanged skips: \(outputURL.path)")
    }
}
