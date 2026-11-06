import AppKit
import SwiftUI

struct WindowSwitcherView: View {
    @ObservedObject var controller: WindowSwitcherController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("창 전환", systemImage: "macwindow.on.rectangle").font(.headline)
                Spacer()
                Text("⌥Tab / ⇧⌥Tab").foregroundStyle(.secondary)
            }
            if controller.selection.isLoading {
                ProgressView("열린 창을 찾는 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.windows.isEmpty {
                Text("현재 화면에서 전환할 수 있는 창이 없습니다.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(controller.windows) { window in
                                HStack(spacing: 12) {
                                    Image(nsImage: NSRunningApplication(processIdentifier: window.pid)?.icon
                                        ?? NSImage(named: NSImage.applicationIconName)!)
                                        .resizable().frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(window.title).lineLimit(1).font(.body.weight(.medium))
                                        Text(window.appName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(controller.selection.selectedID == window.id ? Color.accentColor.opacity(0.22) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(controller.selection.selectedID == window.id ? [.isSelected] : [])
                                .id(window.id)
                            }
                        }
                    }
                    .onChange(of: controller.selection.selectedID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            if let warning = controller.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
            Text("Option을 놓으면 선택 · Esc 취소 · 방향키 이동 · Enter 선택")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 580, height: 420)
    }
}
