// A tiny synth so the pets can honk, quack, meow and purr without any audio files.

import AVFoundation

final class Synth {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var bufs: [String: AVAudioPCMBuffer] = [:]
    private var stopWork: DispatchWorkItem?
    var enabled = true

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.55
        let tau = 2 * Double.pi
        bufs["honk"] = honk(0.2, 520)
        bufs["squawk"] = honk(0.12, 720)
        bufs["honk2"] = concat([honk(0.16, 560), silence(0.05), honk(0.2, 500)])
        bufs["quack"] = concat([honk(0.09, 760), silence(0.03), honk(0.12, 700)])
        var ph = 0.0
        bufs["meow"] = make(0.42) { _, p in
            ph += (560 + 360 * pow(sin(Double.pi * p), 0.8)) / 44100
            let x = 0.6 * sin(tau * ph) + 0.3 * sin(2 * tau * ph) * sin(Double.pi * p) + 0.12 * sin(3 * tau * ph)
            return x * pow(sin(Double.pi * p), 0.5) * (1 - pow(p, 4)) * 0.2
        }
        ph = 0
        bufs["mrrp"] = make(0.2) { t, p in
            ph += (620 + 120 * p) / 44100
            return sin(tau * ph) * (0.6 + 0.4 * sin(tau * 32 * t)) * sin(Double.pi * p) * 0.18
        }
        var lpw = 0.0
        ph = 0
        bufs["woof"] = make(0.17) { t, p in
            ph += (300 - 130 * p) / 44100
            ph -= floor(ph)
            lpw += (Double.random(in: -1...1) - lpw) * 0.3
            let x = (ph < 0.45 ? 1.0 : -1.0) * 0.55 + lpw * 0.6
            return x * min(1, t / 0.008) * (1 - p) * (1 - p) * 0.3
        }
        ph = 0
        bufs["dook"] = make(0.3) { t, p in
            let k = (t / 0.075).truncatingRemainder(dividingBy: 1)
            ph += (980 - 250 * k) / 44100
            return sin(2 * Double.pi * ph) * (k < 0.6 ? sin(Double.pi * k / 0.6) : 0) * (1 - p * 0.5) * 0.17
        }
        var lp = 0.0
        bufs["purr"] = make(0.9) { t, p in
            lp += (Double.random(in: -1...1) - lp) * 0.05
            return lp * (0.55 + 0.45 * sin(tau * 24 * t)) * sin(Double.pi * p) * 2.2
        }
        lp = 0
        bufs["hiss"] = make(0.5) { _, p in
            let n = Double.random(in: -1...1)
            lp += (n - lp) * 0.3
            return (n - lp) * sin(Double.pi * min(1, p * 3)) * (1 - p) * 0.3
        }
        ph = 0
        bufs["pop"] = make(0.05) { _, p in
            ph += (700 + 900 * p) / 44100
            return sin(tau * ph) * exp(-p * 4) * 0.25
        }
        lp = 0
        bufs["chomp"] = make(0.07) { _, p in
            lp += (Double.random(in: -1...1) - lp) * 0.2
            return lp * (1 - p) * 1.2
        }
        ph = 0
        bufs["boing"] = make(0.28) { t, p in
            ph += (160 + 260 * p + 25 * sin(tau * 14 * t)) / 44100
            return sin(tau * ph) * (1 - p) * 0.3
        }
        bufs["chime"] = concat([tone(988, 0.1), tone(1319, 0.18)])
        ph = 0
        bufs["chirp"] = make(0.16) { _, p in
            ph += (1100 + 700 * sin(Double.pi * p)) / 44100
            return sin(tau * ph) * sin(Double.pi * p) * 0.16
        }
        ph = 0
        bufs["kick"] = make(0.09) { _, p in
            ph += (150 - 90 * p) / 44100
            return sin(tau * ph) * (1 - p) * 0.45 + Double.random(in: -1...1) * 0.04 * (1 - p)
        }
        ph = 0; lp = 0
        bufs["yawn"] = make(0.7) { t, p in
            ph += (330 - 140 * p + 6 * sin(tau * 5 * t)) / 44100
            lp += (Double.random(in: -1...1) - lp) * 0.1
            return (0.7 * sin(tau * ph) + 0.6 * lp) * sin(Double.pi * p) * 0.14
        }
        lp = 0
        bufs["poof"] = make(0.18) { _, p in
            lp += (Double.random(in: -1...1) - lp) * 0.45
            return lp * (1 - p) * (1 - p) * 0.5
        }
        lp = 0
        bufs["whoosh"] = make(0.25) { _, p in
            lp += (Double.random(in: -1...1) - lp) * (0.05 + 0.3 * p)
            return lp * sin(Double.pi * p) * 0.9
        }
    }

    private func make(_ dur: Double, _ f: (Double, Double) -> Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(dur * 44100)
        let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
        b.frameLength = n
        let d = b.floatChannelData![0]
        for i in 0..<Int(n) {
            let t = Double(i) / 44100
            d[i] = Float(f(t, t / dur))
        }
        return b
    }

    private func honk(_ dur: Double, _ f0: Double) -> AVAudioPCMBuffer {
        var ph = 0.0, lp = 0.0
        return make(dur) { t, p in
            let f = f0 * (1 - 0.22 * p) * (1 + 0.03 * sin(2 * Double.pi * 28 * t))
            ph += f / 44100
            ph -= floor(ph)
            let x = 0.55 * (2 * ph - 1) + 0.45 * (ph < 0.42 ? 1 : -1)
            lp += (x - lp) * 0.28
            return lp * min(1, t / 0.012) * (p > 0.75 ? (1 - p) / 0.25 : 1) * 0.32
        }
    }

    private func tone(_ f: Double, _ dur: Double) -> AVAudioPCMBuffer {
        make(dur) { t, p in sin(2 * Double.pi * f * t) * exp(-p * 3) * 0.2 }
    }

    private func silence(_ dur: Double) -> AVAudioPCMBuffer { make(dur) { _, _ in 0 } }

    private func concat(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer {
        let total = parts.reduce(0) { $0 + $1.frameLength }
        let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: total)!
        b.frameLength = total
        var off = 0
        for p in parts {
            for i in 0..<Int(p.frameLength) { b.floatChannelData![0][off + i] = p.floatChannelData![0][i] }
            off += Int(p.frameLength)
        }
        return b
    }

    func play(_ name: String) {
        guard enabled, let b = bufs[name] else { return }
        // The engine only runs while something plays, so it never keeps the Mac awake.
        if !engine.isRunning { do { try engine.start() } catch { return } }
        player.scheduleBuffer(b, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
        stopWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.player.stop()
            self?.engine.stop()
        }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }
}
