import AVFoundation
import Cocoa
import PhononTTS

// Speaks with Phonon on the Neural Engine. The model ships in the app's Resources and is copied to Application Support
// on the first launch, where Core ML compiles it (several seconds, once); later launches load it in about half a second.
// Audio plays as it's generated, through a time-pitch unit that sets the speed without changing the voice.
// Its state is only touched on the main thread: chunks from the generating task arrive through the main queue.
final class Speaker: @unchecked Sendable {
    var voice = PHONON_VOICES[0]
    var speed = SPEECH_SPEEDS[DEFAULT_SPEED_INDEX]
    // Called with what the pop-up should say about speech: the first launch's preparation or an error; nil when it works.
    var onNote: ((String?) -> Void)?
    private var note: String? {
        didSet { if note != oldValue { onNote?(note) } }
    }
    // Called when audio starts and when it ends or stops.
    var onPlaying: ((Bool) -> Void)?
    private var playing = false {
        didSet { if playing != oldValue { onPlaying?(playing) } }
    }
    private var phonon: Task<Phonon, Error>?
    private var generation: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Phonon.sampleRate, channels: 1)!
    private var request = 0
    private var samples: [Float] = []
    // Kept without the speed, which only changes playback.
    private var cached: (key: String, samples: [Float])?

    init() {
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    // Starts loading the model with the current voice, so the first word doesn't wait for it.
    func load() {
        let voice = voice
        let installed = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(SUPPORT_FOLDER).appendingPathComponent(MODELS_FOLDER)
        if !PhononModels.isInstalled(at: installed) || Phonon.needsCompiling(installed) { note = PREPARING_VOICE_NOTE }
        let phonon = Task.detached {
            guard let bundled = Bundle.main.url(forResource: MODELS_FOLDER, withExtension: nil) else {
                throw PhononError(description: "the app has no \(MODELS_FOLDER) folder; build it with build.sh")
            }
            let phonon = try await Phonon.load(models: PhononModels.install(bundled: bundled, to: installed), language: .english)
            try await phonon.setVoice(voice)
            return phonon
        }
        self.phonon = phonon
        Task { @MainActor [weak self] in
            if case .failure(let error) = await phonon.result { self?.fail(error) } else { self?.note = nil }
        }
    }

    // Beeps when the model can't load or speak.
    func speak(_ text: String) {
        stop()
        let current = request
        let key = "\(voice)|\(text)"
        if let cached, cached.key == key {
            enqueue(cached.samples, for: current)
            finish(key: key, for: current)
            return
        }
        guard let phonon else { return NSSound.beep() }

        let voice = voice
        generation = Task.detached { [weak self] in
            do {
                let phonon = try await phonon.value
                if phonon.voice != voice { try await phonon.setVoice(voice) }
                try await phonon.speak(text) { chunk in
                    DispatchQueue.main.async { self?.enqueue(chunk, for: current) }
                }
                DispatchQueue.main.async { self?.finish(key: key, for: current) }
            } catch {
                DispatchQueue.main.async { if self?.request == current { self?.fail(error) } }
            }
        }
    }

    // Also invalidates the running request, so chunks still on their way are dropped.
    func stop() {
        request += 1
        generation?.cancel()
        generation = nil
        samples = []
        node.stop()
        playing = false
    }

    private func fail(_ error: Error) {
        NSLog("Phonon failed: %@", String(describing: error))
        note = "Can't speak: \(error)"
        NSSound.beep()
    }

    private func enqueue(_ chunk: [Float], for current: Int) {
        guard request == current, let buffer = buffer(chunk) else { return }
        samples += chunk
        playing = true
        timePitch.rate = speed.rate
        if !engine.isRunning { try? engine.start() }
        node.scheduleBuffer(buffer)
        if !node.isPlaying { node.play() }
    }

    // Caches the finished utterance and pauses the engine once it has played, so the idle app doesn't keep audio running.
    private func finish(key: String, for current: Int) {
        guard request == current, let marker = buffer([Float](repeating: 0, count: END_MARKER_SAMPLES)) else { return }
        cached = (key, samples)
        note = nil
        node.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.request == current else { return }
                self.engine.pause()
                self.playing = false
            }
        }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
