import SwiftUI

struct EqualizerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let eq = player.equalizer
        NavigationStack {
            Form {
                Section {
                    Toggle("Эквалайзер", isOn: Binding(
                        get: { eq.isEnabled },
                        set: { eq.setEnabled($0) }
                    ))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(EqualizerPreset.all) { preset in
                                Button {
                                    eq.apply(preset: preset)
                                } label: {
                                    Text(preset.name)
                                        .font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            eq.currentPresetID == preset.id ? Color.indigo : Color.secondary.opacity(0.15),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(eq.currentPresetID == preset.id ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Пресеты")
                }

                Section {
                    ForEach(Array(EqualizerPreset.bandFrequencies.enumerated()), id: \.offset) { index, frequency in
                        BandSlider(
                            label: formatFrequency(frequency),
                            gain: Binding(
                                get: { eq.customGains[index] },
                                set: { eq.setGain($0, at: index) }
                            )
                        )
                    }
                } header: {
                    Text("Полосы")
                } footer: {
                    Text("Настройки применяются на лету. Эквалайзер работает для нативных треков Sonify (AVAudioUnitEQ).")
                }
            }
            .navigationTitle("Эквалайзер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func formatFrequency(_ hz: Float) -> String {
        hz >= 1000 ? String(format: "%g k", hz / 1000) : String(format: "%g", hz)
    }
}

private struct BandSlider: View {
    let label: String
    @Binding var gain: Float

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption.monospacedDigit())
                .frame(width: 52, alignment: .leading)
            Slider(value: Binding(
                get: { Double(gain) },
                set: { gain = Float($0) }
            ), in: -12...12, step: 0.5)
            .tint(gain >= 0 ? .indigo : .orange)
            Text(String(format: "%+.1f dB", gain))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}
