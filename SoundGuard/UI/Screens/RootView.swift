import SwiftUI

@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var alarmEpoch = 0

    var body: some View {
        let alarm = model.coordinator.presentsAlarm
        ZStack {
            TabView {
                MonitorView()
                    .tabItem { Label("LISTEN", systemImage: "waveform") }
                SoundsView()
                    .tabItem { Label("TARGETS", systemImage: "dot.radiowaves.left.and.right") }
                EventsView()
                    .tabItem { Label("LOG", systemImage: "list.bullet.rectangle") }
                SettingsView()
                    .tabItem { Label("SYS", systemImage: "slider.horizontal.3") }
            }
            .tint(SGTheme.cyan)
            .toolbar(alarm ? .hidden : .visible, for: .tabBar)
            .toolbarBackground(SGTheme.panel, for: .tabBar)
            if alarm {
                // In the window hierarchy, not a cover. A cover requested while
                // the phone is locked never appears, and it stays missing after unlock.
                AlarmView()
                    .id(alarmEpoch)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SGTheme.bg.ignoresSafeArea())
                    .contentShape(Rectangle())
                    .zIndex(1)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.coordinator.presentsAlarm {
                alarmEpoch += 1
            }
        }
        .alert("SOUNDGUARD", isPresented: Binding(
            get: {
                !model.coordinator.phase.isAlarmSurface
                    && (model.banner != nil || model.coordinator.lastError != nil)
            },
            set: { open in
                if !open {
                    model.banner = nil
                    model.coordinator.consumeError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                model.banner = nil
                model.coordinator.consumeError()
            }
        } message: {
            Text(model.banner ?? model.coordinator.lastError ?? "")
        }
    }
}
