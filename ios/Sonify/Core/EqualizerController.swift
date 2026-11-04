import AVFoundation
import Foundation

/// 10-полосный эквалайзер на AVAudioUnitEQ с пресетами.
/// Значения в дБ, диапазон -12...+12.
struct EqualizerPreset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let gains: [Float]

    static let bandFrequencies: [Float] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let flat        = EqualizerPreset(id: "flat", name: "Flat", gains: Array(repeating: 0, count: 10))
    static let bass        = EqualizerPreset(id: "bass", name: "Bass", gains: [9, 7, 4, 1, 0, 0, 0, 0.5, 1, 1.5])
    static let vocal       = EqualizerPreset(id: "vocal", name: "Vocal", gains: [-2, -1, 0, 2, 5, 5, 3, 1, 0, -1])
    static let electronic  = EqualizerPreset(id: "electronic", name: "Electronic", gains: [6, 5, 2, 0, -2, 1, 3, 4, 5, 4])
    static let loFi        = EqualizerPreset(id: "lo-fi", name: "Lo-Fi", gains: [1, 2, 3, 1, 0, -1, -3, -5, -7, -9])

    static let all: [EqualizerPreset] = [.flat, .bass, .vocal, .electronic, .loFi]
}

/// Обёртка над AVAudioUnitEQ: применяет пресеты и пользовательские значения.
@MainActor
final class EqualizerController {
    let engine: AVAudioEngine
    let playerNode: AVAudioPlayerNode
    let eq: AVAudioUnitEQ
    private(set) var currentPresetID: String = EqualizerPreset.flat.id
    private(set) var customGains: [Float] = Array(repeating: 0, count: 10)
    private(set) var isEnabled: Bool = true

    init() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        eq = AVAudioUnitEQ(numberOfBands: EqualizerPreset.bandFrequencies.count)
        configureBands()
        engine.attach(playerNode)
        engine.attach(eq)
        // Явный формат: 44.1 кГц stereo, PCM float. AVAudioPlayerNode ресемплирует
        // файл любого sample rate (22.05/44.1/48 кГц) и канальности под этот граф.
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        try? AudioSessionController.activate()
    }

    private func configureBands() {
        for (index, freq) in EqualizerPreset.bandFrequencies.enumerated() {
            let band = eq.bands[index]
            band.filterType = index == 0 ? .lowShelf : (index == EqualizerPreset.bandFrequencies.count - 1 ? .highShelf : .parametric)
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    func apply(preset: EqualizerPreset) {
        currentPresetID = preset.id
        customGains = preset.gains
        for (index, gain) in preset.gains.enumerated() {
            eq.bands[index].gain = gain
        }
    }

    func setGain(_ gain: Float, at index: Int) {
        guard eq.bands.indices.contains(index) else { return }
        let clamped = min(max(gain, -12), 12)
        customGains[index] = clamped
        eq.bands[index].gain = clamped
        currentPresetID = "custom"
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        eq.bypass = !enabled
    }
}

/// Настройка аудиосессии и реакции на прерывания.
enum AudioSessionController {
    static let categoryOptions: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]

    @discardableResult
    static func activate() throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: categoryOptions)
        try session.setActive(true)
        return true
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
