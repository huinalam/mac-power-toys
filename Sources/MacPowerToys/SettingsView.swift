import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("앱 바로 전환", systemImage: "command.square.fill")
                        .font(.title2.bold())
                    Text("단축키 한 번으로 앱을 실행하거나 앞으로 가져오세요.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { store.addApplications() }) {
                    Label("앱 추가", systemImage: "plus")
                }
                .keyboardShortcut("o")
            }
            .padding(24)

            if store.isPaused {
                Label("모든 앱 단축키가 일시 정지되어 있습니다.", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24).padding(.bottom, 16)
            }
            Divider()
            if store.entries.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "app.badge.checkmark").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("자주 쓰는 앱부터 추가하세요").font(.headline)
                    Text("앱을 선택하고 단축키를 입력하면 바로 사용할 수 있습니다.")
                        .foregroundStyle(.secondary)
                    Button("앱 선택…", action: { store.addApplications() }).buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.entries) { entry in
                            appRow(entry)
                            Divider().padding(.leading, 76)
                        }
                    }.padding(.vertical, 8)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("단축키 일시 정지", isOn: $store.isPaused)
                    Spacer()
                    Toggle("로그인 시 실행", isOn: Binding(
                        get: { store.loginEnabled }, set: { store.setLoginEnabled($0) }
                    ))
                }
                if store.loginNeedsApproval {
                    HStack {
                        Text("로그인 항목 승인이 필요합니다.").foregroundStyle(.secondary)
                        Button("시스템 설정 열기") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Text("이미 활성화된 앱은 유지합니다. 창 복원 및 다른 Space로의 이동은 macOS와 대상 앱의 동작을 따릅니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .frame(minWidth: 680, minHeight: 440)
        .alert("확인이 필요합니다", isPresented: Binding(
            get: { store.message != nil }, set: { if !$0 { store.message = nil } }
        )) {
            Button("확인") { store.message = nil }
        } message: { Text(store.message ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLoginStatus()
        }
    }

    private func appRow(_ entry: AppEntry) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: store.resolvedURL(for: entry)?.path ?? entry.path))
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(.headline)
                if let error = store.launchErrors[entry.id] {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(entry.bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            KeyboardShortcuts.Recorder(for: entry.shortcutName) { _ in
                store.shortcutChanged(for: entry)
            }
            .shortcutValidation { store.validate($0, for: entry) }
            .frame(width: 150)
            .accessibilityLabel("\(entry.name) 단축키")
            Toggle("활성화", isOn: Binding(
                get: { entry.isEnabled }, set: { store.setEnabled($0, for: entry) }
            )).labelsHidden().help("이 앱의 단축키 활성화")
            Button { store.launch(entry) } label: { Image(systemName: "play.fill") }
                .help("\(entry.name) 실행 또는 전환").accessibilityLabel("\(entry.name) 실행")
            Button(role: .destructive) { store.remove(entry) } label: { Image(systemName: "trash") }
                .help("목록에서 제거").accessibilityLabel("\(entry.name) 제거")
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }
}
