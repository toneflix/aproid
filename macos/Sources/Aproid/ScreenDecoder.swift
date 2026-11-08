import AppKit
import AVFoundation
import CoreMedia
import AproidKit

/// Turns the phone's H.264 stream into pictures on a display layer, using the Mac's hardware decoder.
final class ScreenDecoder: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()

    /// Called on a network thread when the picture size changes, such as when the phone rotates.
    var onSize: ((CGSize) -> Void)?

    private var sps: Data?
    private var pps: Data?
    private var format: CMVideoFormatDescription?
    private let lock = NSLock()

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
    }

    /// Forgets the old stream's settings and clears the picture.
    func reset() {
        lock.withLock {
            sps = nil
            pps = nil
            format = nil
        }
        DispatchQueue.main.async { self.layer.flushAndRemoveImage() }
    }

    /// Takes one frame from the stream. Frames from one stream arrive in order on one thread.
    func decode(_ frame: ScreenFrame) {
        var pictures: [Data] = []

        let sample: CMSampleBuffer? = lock.withLock {
            var changed = false
            for unit in Self.units(frame.data) {
                guard let header = unit.first else { continue }

                switch header & 0x1F {
                case 7 where unit != sps:
                    sps = unit
                    changed = true
                case 8 where unit != pps:
                    pps = unit
                    changed = true
                case 7, 8:
                    break
                default:
                    pictures.append(unit)
                }
            }

            if changed { makeFormat() }
            guard let format, !pictures.isEmpty else { return nil }

            return Self.sample(pictures, format: format)
        }

        guard let sample else { return }
        DispatchQueue.main.async {
            if self.layer.status == .failed { self.layer.flush() }
            self.layer.enqueue(sample)
        }
    }

    /// Builds the decoder settings from the stream's SPS and PPS. Call with the lock held.
    private func makeFormat() {
        guard let sps, let pps else { return }

        var created: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers = [
                    spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBytes.bindMemory(to: UInt8.self).baseAddress!,
                ]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: [sps.count, pps.count],
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &created
                )
            }
        }
        guard status == noErr, let created else { return }

        format = created
        let dimensions = CMVideoFormatDescriptionGetDimensions(created)
        onSize?(CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height)))
    }

    /// One picture, its NAL units given 4 byte lengths as Core Media expects, shown as soon as it is decoded.
    private static func sample(_ units: [Data], format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var data = Data()
        for unit in units {
            withUnsafeBytes(of: UInt32(unit.count).bigEndian) { data.append(contentsOf: $0) }
            data.append(unit)
        }

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &block
        ) == noErr, let block else { return nil }

        let copied = data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == noErr else { return nil }

        var sample: CMSampleBuffer?
        var size = data.count
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                first,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sample
    }

    /// Splits Annex B data at its 00 00 01 start codes into NAL units.
    static func units(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(code: Int, body: Int)] = []
        var index = 0

        while index + 2 < bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                let code = index > 0 && bytes[index - 1] == 0 ? index - 1 : index
                starts.append((code, index + 3))
                index += 3
            } else {
                index += 1
            }
        }

        guard !starts.isEmpty else { return bytes.isEmpty ? [] : [data] }

        return starts.indices.map { position in
            let end = position + 1 < starts.count ? starts[position + 1].code : bytes.count
            return Data(bytes[starts[position].body..<end])
        }
    }
}
