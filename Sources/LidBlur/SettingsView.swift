import SwiftUI
import LidBlurCore

/// What the Settings window shows. AppDelegate keeps it in sync; the view only reads it and calls back into the app.
@MainActor @Observable
final class SettingsModel {
    enum Tone { case active, idle, attention }
    var state = ""
    var detail = ""
    var tone = Tone.idle
    var angle: Int?
    var supported = true
    var enabled = true
    var launchAtLogin = false
    var loginNeedsApproval = false
    var showMenuBarIcon = true
    var startAngle = EngineConstants.defaultStartAngle
}

struct SettingsView: View {
    let app: AppDelegate
    let model: SettingsModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section("General") {
                    Toggle("Enable LidBlur", isOn: binding(\.enabled, app.setEnabled))
                        .disabled(!model.supported)
                    Toggle(isOn: binding(\.launchAtLogin, app.setLaunchAtLogin)) {
                        Text("Launch at login")
                        if model.loginNeedsApproval {
                            Text("Approve LidBlur in System Settings › General › Login Items.")
                        }
                    }
                    Toggle(isOn: binding(\.showMenuBarIcon, app.setShowMenuBarIcon)) {
                        Text("Show icon in menu bar")
                        Text("When hidden, LidBlur keeps running. Open it again from Applications to return here.")
                    }
                }
                Section {
                    LabeledContent("Blur starts at") {
                        Text("\(Int(model.startAngle))°").monospacedDigit()
                    }
                    Slider(value: binding(\.startAngle, { app.setStartAngle($0.rounded()) }),
                           in: EngineConstants.startAngleRange) {
                        Text("Blur starts at")
                    } minimumValueLabel: {
                        Text("\(Int(EngineConstants.startAngleRange.lowerBound))°")
                    } maximumValueLabel: {
                        Text("\(Int(EngineConstants.startAngleRange.upperBound))°")
                    }
                    .labelsHidden()
                    HStack {
                        Button(model.angle.map { "Use Current Angle (\($0)°)" } ?? "Use Current Angle") {
                            if let a = model.angle { app.setStartAngle(Double(a)) }
                        }
                        .disabled(model.angle == nil)
                        Spacer()
                        Button("Preview Effect", action: app.startPreview)
                    }
                } header: {
                    Text("Effect")
                } footer: {
                    Text("A higher angle starts the blur earlier as the lid closes.")
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.supported)
                Section {
                    LabeledContent("Quit instantly") {
                        Text("⌃ ⌥ ⌘ B")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel("Control Option Command B")
                    }
                } header: {
                    Text("Safety")
                } footer: {
                    Text("Moving the pointer or pressing a key also clears the blur. LidBlur is a visual effect, not a privacy tool.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            footer
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("LidBlur").font(.title2.weight(.semibold))
                Text("Blurs your MacBook's screen in step with the lid.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle().fill(toneColor).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(statusLine).monospacedDigit()
                }
                .font(.callout)
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack {
            Button(copied ? "Copied" : "Copy Diagnostics") {
                app.copyDiagnostics()
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            }
            Button("Check for Updates…") { NSWorkspace.shared.open(SettingsWindowController.releasesURL) }
            Spacer()
            Button("Quit LidBlur") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var statusLine: String {
        [model.state, model.detail, model.angle.map { "Lid \($0)°" } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var toneColor: Color {
        switch model.tone {
        case .active: .green
        case .idle: .secondary
        case .attention: .orange
        }
    }

    /// Reads from the model; writes go to the app, which updates the model.
    private func binding<T>(_ keyPath: KeyPath<SettingsModel, T>, _ set: @escaping @MainActor (T) -> Void) -> Binding<T> {
        Binding(get: { model[keyPath: keyPath] }, set: { value in MainActor.assumeIsolated { set(value) } })
    }
}
