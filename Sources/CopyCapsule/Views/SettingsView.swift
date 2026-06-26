import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let viewModel: ClipHistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { viewModel.showSettings = false } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("返回").font(.system(size: 13))
                    }
                }.buttonStyle(.plain)
                Spacer()
                Text("设置").font(.system(size: 16, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text("返回").font(.system(size: 13))
                }.opacity(0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            VStack(spacing: 0) {
                // 历史保留
                HStack {
                    Text("历史保留:").font(.system(size: 13))
                    Spacer()
                    Picker("", selection: Binding(get: { settings.retentionDays }, set: { settings.retentionDays = $0 })) {
                        Text("1 天").tag(1)
                        Text("3 天").tag(3)
                        Text("5 天").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                // 开机启动
                HStack {
                    Text("开机启动").font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: Binding(get: { settings.autoStartEnabled }, set: {
                        settings.autoStartEnabled = $0
                        LoginItemManager.syncWithSetting($0)
                    }))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                Divider().padding(.vertical, 6)

                // 快捷键分组标签
                Text("快捷键")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                ShortcutRecorder(label: "标签弹窗:", shortcut: settings.tagShortcut) {
                    settings.tagShortcut = $0
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                ShortcutRecorder(label: "窗口开关:", shortcut: settings.windowShortcut) {
                    settings.windowShortcut = $0
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            Divider()
            HStack {
                Image(systemName: "clipboard").foregroundColor(.clipAccent)
                Text("CopyCapsule v2.0").font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}
