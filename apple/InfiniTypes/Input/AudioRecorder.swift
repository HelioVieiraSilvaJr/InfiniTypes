import AVFoundation
import Synchronization

/// Grava o microfone e entrega áudio em 16 kHz mono Float32, o formato que o Whisper espera.
/// O microfone só fica aberto entre `start()` e `stop()`.
final class AudioRecorder {
    nonisolated static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var sink: AudioSink?

    var isRecording: Bool { sink != nil }

    /// Nível atual do microfone, de 0 a 1, para o HUD.
    var level: Float { sink?.level ?? 0 }

    func start() throws {
        guard sink == nil else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }

        let sink = try AudioSink(inputFormat: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tapBlock(for: sink))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.sink = sink
    }

    /// Para a gravação e devolve as amostras capturadas.
    func stop() -> [Float] {
        guard let sink else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.sink = nil
        return sink.drain()
    }

    /// O bloco roda na thread de áudio, então é criado fora do isolamento da main thread.
    private nonisolated static func tapBlock(for sink: AudioSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.append(buffer) }
    }
}

enum RecorderError: LocalizedError {
    case noInputDevice
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "Nenhum microfone disponível"
        case .converterUnavailable: "Formato de áudio do microfone não suportado"
        }
    }
}

/// Converte e acumula os buffers do microfone. Recebe dados na thread de áudio e é lido na main thread.
nonisolated final class AudioSink: @unchecked Sendable {
    private static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: AudioRecorder.sampleRate,
                                                    channels: 1, interleaved: false)!

    private struct State {
        var samples: [Float] = []
        var level: Float = 0
    }

    /// Usado só na thread de áudio, em `append`.
    private let converter: AVAudioConverter
    private let state = Mutex(State())

    init(inputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter
    }

    var level: Float { state.withLock { $0.level } }

    func append(_ buffer: AVAudioPCMBuffer) {
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

        // O bloco de entrada roda de forma síncrona dentro de `convert`, nesta mesma thread.
        nonisolated(unsafe) let input = buffer
        nonisolated(unsafe) var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }

        let samples = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(samples.count, 1))
        let level = min(1, sqrt(meanSquare) * 8)
        state.withLock {
            $0.samples.append(contentsOf: samples)
            $0.level = level
        }
    }

    func drain() -> [Float] {
        state.withLock { state in
            defer { state.samples = [] }
            return state.samples
        }
    }
}
