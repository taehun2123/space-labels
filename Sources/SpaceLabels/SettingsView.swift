import SwiftUI
import SpaceLabelsCore

struct SettingsView: View {
    @ObservedObject var app: AppController
    @State private var drafts: [String: String] = [:]
    @State private var recoverySelection: [UUID: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("공간 이름").font(.title2.bold())
                    Spacer()
                    Button("새로고침") { app.refresh() }
                }
                Text("Mission Control에서 상단 공간이나 아래의 개별 앱 창을 우클릭하면 이름을 바로 편집할 수 있습니다.")
                    .foregroundStyle(.secondary)

                if let error = app.lastError {
                    Text(error).foregroundStyle(.red)
                }

                ForEach(Array((app.snapshot?.displays ?? []).enumerated()), id: \.offset) { displayIndex, display in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(app.displayTitle(display, number: displayIndex + 1)).font(.headline)
                        ForEach(Array(display.spaces.enumerated()), id: \.offset) { index, space in
                            HStack(spacing: 10) {
                                Text(app.spaceTitle(space, in: display, index: index))
                                    .frame(width: 160, alignment: .leading)
                                if let uuid = space.uuid {
                                    TextField("이름", text: binding(for: uuid))
                                        .accessibilityLabel("\(app.spaceTitle(space, in: display, index: index)) 이름")
                                    Button("저장") { app.saveName(drafts[uuid] ?? app.name(for: uuid) ?? "", uuid: uuid, display: display.identifier) }
                                    Button("초기화") {
                                        drafts.removeValue(forKey: uuid)
                                        app.clearName(uuid: uuid)
                                    }
                                    .disabled(app.name(for: uuid) == nil)
                                } else {
                                    Text("식별자를 확인할 수 없습니다.").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }

                if !app.orphanedNames.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("연결 확인이 필요한 이름").font(.headline)
                        Text("공간이 삭제되거나 식별자가 바뀐 이름입니다. 대상을 선택해 다시 연결하십시오.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(app.orphanedNames) { record in
                            HStack {
                                Text(record.name).frame(maxWidth: .infinity, alignment: .leading)
                                Picker("연결할 공간", selection: recoveryBinding(for: record.id)) {
                                    Text("선택하십시오").tag("")
                                    ForEach(app.recoveryTargets, id: \.uuid) { target in
                                        Text(target.title).tag(target.uuid)
                                    }
                                }
                                .frame(width: 220)
                                Button("연결") { app.reassign(recordID: record.id, to: recoverySelection[record.id] ?? "") }
                                    .disabled((recoverySelection[record.id] ?? "").isEmpty)
                            }
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }

                if !app.savedWindowNames.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("저장한 앱 창 이름").font(.headline)
                        Text("앱과 원래 창 제목이 같을 때 이름을 다시 표시합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(app.savedWindowNames.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(app.windowDescription(for: key))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(app.savedWindowNames[key] ?? "")
                                    .lineLimit(1)
                                Button("초기화") { app.clearWindowName(key: key) }
                            }
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }

                Divider()
                Toggle("Mission Control에 이름 표시", isOn: Binding(
                    get: { app.overlayEnabled }, set: { app.setOverlayEnabled($0) }
                ))
                if !app.accessibilityGranted {
                    HStack {
                        Text("Mission Control에서 공간과 창을 찾으려면 접근성 권한이 필요합니다.").foregroundStyle(.secondary)
                        Button("권한 설정 열기") { app.requestAccessibility() }
                    }
                }
                Text(app.lastScanSummary).font(.caption).foregroundStyle(.secondary)
                Text(app.lastClickSummary).font(.caption).foregroundStyle(.secondary)
                Toggle("로그인 시 실행", isOn: Binding(
                    get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }
                ))
            }
            .padding(20)
        }
        .frame(minWidth: 660, minHeight: 420)
    }

    private func binding(for uuid: String) -> Binding<String> {
        Binding(get: { drafts[uuid] ?? app.name(for: uuid) ?? "" }, set: { drafts[uuid] = $0 })
    }

    private func recoveryBinding(for recordID: UUID) -> Binding<String> {
        Binding(get: { recoverySelection[recordID] ?? "" }, set: { recoverySelection[recordID] = $0 })
    }
}
