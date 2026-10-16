import SwiftUI
import AVFoundation

// MARK: - System voice editor
//
// [T-tts-services 09-11] The System (Apple) row's gear sheet. Previously the
// on-device voice's pitch/volume lived in Enhanced Background settings and the
// voice roster only inside the Model Output picker — two unrelated places for
// "tune my voice". This editor gives the built-in engine the same treatment as
// any cloud service: pick a voice, set speed/pitch/volume, test-listen.
//
// The chosen voice identifier is stored in SystemVoicePreferences.selectedVoiceId
// and honoured by VoiceProviderResolver.resolvedSystemOutputVoiceId() (which
// already reads selection overrides / group members — this adds a direct
// selection without touching the Model-Group machinery).

// MARK: - Preference storage

enum SystemVoiceEditorPreferences {
    private static let voiceKey = "systemVoice.selectedIdentifier"
    private static let rateKey = "systemVoice.rateMultiplier"

    /// Pinned AVSpeechSynthesisVoice identifier; nil = auto by language.
    static var selectedVoiceId: String? {
        get { UserDefaults.standard.string(forKey: voiceKey) }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: voiceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: voiceKey)
            }
        }
    }

    /// Utterance rate multiplier (0.4–0.62 → AVSpeech 0–1 scale). Default 1.0.
    /// Stored as the AVSpeechUtterance.rate value directly for simplicity.
    static var utteranceRate: Float {
        get {
            let v = UserDefaults.standard.object(forKey: rateKey) as? Float
            return v ?? 0.5
        }
        set { UserDefaults.standard.set(newValue, forKey: rateKey) }
    }
}

// MARK: - Editor view

struct SystemVoiceEditorView: View {

    @Environment(\.dismiss) private var dismiss

    /// The filtered roster; refreshed when the system voice list changes
    /// (downloaded packs etc.).
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var selectedVoiceId: String? = SystemVoiceEditorPreferences.selectedVoiceId
    @State private var rate: Float = SystemVoiceEditorPreferences.utteranceRate
    @State private var pitch: Float = SystemVoicePreferences.pitch
    @State private var volume: Float = SystemVoicePreferences.volume
    @State private var testing = false
    @State private var testError: String?
    /// [batch9-voice/3 · VT-C2] 保存时"切到系统语音"确认框。
    @State private var showSwitchConfirm = false

    var body: some View {
        Form {
            voiceSection
            tuningSection
            testSection
        }
        .scrollContentBackground(.hidden)
        .background(MinisTheme.canvas)
        .navigationTitle("System Voice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    persist()
                    // [batch9-voice/3 · VT-C2] 选用系统音色且当前有选中的云服务：
                    // 不再静默改路由——交给确认框由用户决定。
                    if needsVoiceSwitchConfirm {
                        showSwitchConfirm = true
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog("把发声切换为系统语音吗？", isPresented: $showSwitchConfirm, titleVisibility: .visible) {
            Button("切换为系统语音") {
                switchVoiceToSystem()
                dismiss()
            }
            Button("保持当前服务", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("你选定了系统音色。切换后朗读用系统声音；随时可在 设置 › 语音服务 切回。")
        }
        .onAppear(perform: loadVoices)
        // Roster refresh via the shared observer (iOS 17+; on older systems the
        // list still rebuilds on open). UnifiedModelPicker uses the same hook.
        .onAppear { SystemVoiceCatalog.startObservingVoiceChanges() }
        .onReceive(SystemVoiceRoster.shared.$revision) { _ in
            loadVoices()
        }
    }

    // MARK: Sections

    private var voiceSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { selectedVoiceId == nil },
                set: { if $0 { selectedVoiceId = nil } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto by language")
                    Text("Each reply uses the voice matching its language")
                        .font(.caption)
                        .foregroundStyle(MinisTheme.secondaryText)
                }
            }

            ForEach(voices, id: \.identifier) { voice in
                let isPinned = selectedVoiceId == voice.identifier
                Button {
                    selectedVoiceId = voice.identifier
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.name)
                                .foregroundStyle(MinisTheme.primaryText)
                            Text("\(voice.language) \(SystemVoiceCatalog.qualityStars(voice.quality))")
                                .font(.caption)
                                .foregroundStyle(MinisTheme.secondaryText)
                        }
                        Spacer()
                        if isPinned {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(MinisTheme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Download more voices in Settings › Accessibility › Spoken Content › Voices. Premium voices sound best.")
        }
    }

    private var tuningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(rateLabel).foregroundStyle(MinisTheme.secondaryText).font(.caption)
                }
                Slider(value: $rate, in: 0.3...0.65, step: 0.05)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pitch")
                    Spacer()
                    Text(String(format: "%.1f×", pitch)).foregroundStyle(MinisTheme.secondaryText).font(.caption)
                }
                Slider(value: $pitch, in: 0.5...2.0, step: 0.1)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text(String(format: "%.0f%%", volume * 100)).foregroundStyle(MinisTheme.secondaryText).font(.caption)
                }
                Slider(value: $volume, in: 0.0...1.0, step: 0.05)
            }
        } header: {
            Text("Tuning")
        } footer: {
            Text("速度基准：最终播放速度 = 此处 Speed × 语音设置里的播放倍速。")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                runTest()
            } label: {
                HStack {
                    if testing { ProgressView().padding(.trailing, 4) }
                    Label("Play test sentence", systemImage: "speaker.wave.2")
                    Spacer()
                }
            }
            .disabled(testing)
            if let err = testError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(MinisTheme.destructive)
                    .font(.caption)
            }
        } header: {
            Text("Test")
        } footer: {
            Text("Plays with the CURRENT sliders — save with Done.")
        }
    }

    // MARK: Helpers

    private func loadVoices() {
        voices = SystemVoiceCatalog.filteredAndSortedVoices()
    }

    private var rateLabel: String {
        // Map AVSpeech rate to a human-friendly multiplier (0.5 ≈ 1×).
        let mult = rate / 0.5
        return String(format: "%g×", mult)
    }

    private func persist() {
        SystemVoiceEditorPreferences.selectedVoiceId = selectedVoiceId
        SystemVoiceEditorPreferences.utteranceRate = rate
        SystemVoicePreferences.pitch = pitch
        SystemVoicePreferences.volume = volume
        // [batch9-voice/3 · VT-C2] 不再静默清掉已选服务——路由切换由 Done 时
        // 的确认框决定（needsVoiceSwitchConfirm → confirmationDialog）。
    }

    /// 保存时是否要用户确认"把发声切换到系统语音"：选定了系统音色，且当前有
    /// 显式选中的云服务（清服务 = 发声路由从云服务变回模型组/系统）。
    private var needsVoiceSwitchConfirm: Bool {
        selectedVoiceId != nil && TTSServiceStore.shared.selectedServiceId != nil
    }

    /// 确认后切换路由（用户点"切换为系统语音"→ 清除云服务选择）。
    private func switchVoiceToSystem() {
        TTSServiceStore.shared.setSelectedServiceId(nil)
        MinisToast.show("已切换为系统语音发声", systemImage: "waveform")
    }

    private func runTest() {
        testing = true
        testError = nil
        let voiceId = selectedVoiceId
        Task { @MainActor in
            defer { testing = false }
            do {
                let utterance = AVSpeechUtterance(string: "你好，这是系统语音的试听。")
                utterance.rate = rate
                utterance.pitchMultiplier = pitch
                utterance.volume = volume
                if let id = voiceId, let v = AVSpeechSynthesisVoice(identifier: id) {
                    utterance.voice = v
                }
                // Live preview through the shared synthesizer (not the WAV
                // write path — that's for pipeline synthesis, not previews).
                SystemVoicePreviewPlayer.shared.speak(utterance)
            }
        }
    }
}

// MARK: - Preview player

/// Simple shared synthesizer for editor previews: speaks the latest utterance,
/// stopping whatever was playing (the editor only ever previews one sentence).
@MainActor
final class SystemVoicePreviewPlayer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SystemVoicePreviewPlayer()
    private let synthesizer = AVSpeechSynthesizer()
    /// The utterance the current `.replyTTS` intent belongs to. Delegate
    /// callbacks hop through a Task, so a stale didCancel/didFinish for a
    /// replaced utterance can land after a new preview has begun; only the
    /// current utterance's callback may release the intent (same identity
    /// guard as TTSPreviewPlayer).
    private var currentUtterance: AVSpeechUtterance?
    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ utterance: AVSpeechUtterance) {
        AudioSessionCoordinator.shared.begin(.replyTTS)
        currentUtterance = utterance
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            AudioSessionCoordinator.shared.end(.replyTTS)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            AudioSessionCoordinator.shared.end(.replyTTS)
        }
    }
}
