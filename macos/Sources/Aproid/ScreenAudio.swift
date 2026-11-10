import AVFoundation
import AproidKit
import os

/// Plays the phone's sound while mirroring. The stream carries 16-bit PCM, which goes straight to the
/// output with only a small queue, so the sound stays close to the picture.
final class ScreenAudio: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var format: AVAudioFormat?
    private var configObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.toneflix.aproid.app", category: "screen-audio")

    /// Buffers waiting to play. Kept apart from `lock`, because stopping the player calls their handlers.
    private let counter = NSLock()
    private var queued = 0

    /// More than this many 20 ms pieces waiting means the sound has fallen behind, so new ones are dropped.
    private static let maxQueued = 8

    var isMuted = false {
        didSet { player.volume = isMuted ? 0 : 1 }
    }

    init() {
        engine.attach(player)

        // The engine stops when the output changes, such as when headphones connect.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in self?.restart() }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Gets ready for a stream with this sound format.
    func start(rate: Int64, channels: Int64) {
        lock.withLock {
            stopLocked()

            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(rate),
                channels: AVAudioChannelCount(channels),
                interleaved: false
            ) else { return }

            engine.connect(player, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
                player.volume = isMuted ? 0 : 1
                player.play()
                self.format = format
            } catch {
                log.error("Could not start sound: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        lock.withLock { stopLocked() }
    }

    /// Queues one piece of interleaved little-endian 16-bit sound.
    func play(_ frame: ScreenFrame) {
        lock.withLock {
            guard let format, engine.isRunning else { return }
            guard counter.withLock({ queued }) < Self.maxQueued else { return }

            let channels = Int(format.channelCount)
            let count = frame.data.count / (2 * channels)
            guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let outputs = buffer.floatChannelData else { return }

            buffer.frameLength = AVAudioFrameCount(count)
            frame.data.withUnsafeBytes { raw in
                for channel in 0..<channels {
                    let output = outputs[channel]
                    for index in 0..<count {
                        let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: (index * channels + channel) * 2, as: Int16.self))
                        output[index] = Float(sample) / 32_768
                    }
                }
            }

            counter.withLock { queued += 1 }
            player.scheduleBuffer(buffer) { [weak self] in
                guard let self else { return }
                self.counter.withLock { self.queued = max(0, self.queued - 1) }
            }
        }
    }

    /// Call with `lock` held.
    private func stopLocked() {
        guard format != nil else { return }

        format = nil
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        counter.withLock { queued = 0 }
    }

    private func restart() {
        lock.withLock {
            guard format != nil, !engine.isRunning else { return }

            do {
                try engine.start()
                player.play()
            } catch {
                log.error("Could not restart sound: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
