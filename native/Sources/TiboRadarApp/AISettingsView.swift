import SwiftUI

struct AISettingsView: View {
  @EnvironmentObject private var model: RadarViewModel
  let onDone: () -> Void

  @State private var provider = AIProvider.deepSeek
  @State private var modelName = AIProvider.deepSeek.defaultModel
  @State private var apiKey = ""
  @State private var showingDeleteConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("AI 模型设置")
            .font(.system(size: 16, weight: .bold))
          Text("使用你自己的 API Key")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "lock.shield.fill")
          .foregroundStyle(.green)
      }

      Picker("模型服务", selection: $provider) {
        ForEach(AIProvider.allCases) { provider in
          Text(provider.displayName).tag(provider)
        }
      }
      .pickerStyle(.segmented)

      VStack(alignment: .leading, spacing: 7) {
        Text("模型名称")
          .font(.caption.weight(.semibold))
        TextField(provider.defaultModel, text: $modelName)
          .textFieldStyle(.roundedBorder)
      }

      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("API Key")
            .font(.caption.weight(.semibold))
          Spacer()
          if model.keyIsSaved(for: provider) {
            Label("钥匙串已保存", systemImage: "checkmark.circle.fill")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.green)
          }
        }
        SecureField(
          model.keyIsSaved(for: provider) ? "留空表示继续使用已保存 Key" : "粘贴 API Key",
          text: $apiKey
        )
        .textFieldStyle(.roundedBorder)
      }

      Text(provider.capabilityNote)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

      if let message = model.settingsMessage {
        Label(
          message,
          systemImage: message.contains("成功") || message.contains("已保存")
            ? "checkmark.circle" : "info.circle"
        )
        .font(.caption)
        .foregroundStyle(
          message.contains("成功") || message.contains("已保存") ? .green : .orange
        )
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      HStack {
        if model.keyIsSaved(for: provider) {
          Button("删除 Key", role: .destructive) {
            showingDeleteConfirmation = true
          }
          .buttonStyle(.borderless)
          .font(.caption)
        }
        Spacer()
        Button("保存") {
          _ = model.saveSettings(
            provider: provider,
            model: modelName,
            newAPIKey: apiKey
          )
          apiKey = ""
        }
        .buttonStyle(.bordered)

        Button {
          Task {
            await model.saveAndTest(
              provider: provider,
              model: modelName,
              newAPIKey: apiKey
            )
            apiKey = ""
          }
        } label: {
          if model.isTestingConnection {
            ProgressView().controlSize(.small)
          } else {
            Text("保存并测试")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isTestingConnection)
      }

      HStack {
        Text("Key 只存于本机 macOS 钥匙串，不写入缓存或日志。")
          .font(.system(size: 9))
          .foregroundStyle(.tertiary)
        Spacer()
        Button("完成") { onDone() }
          .buttonStyle(.borderless)
          .font(.caption.weight(.semibold))
      }
    }
    .padding(15)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
    .onAppear {
      provider = model.selectedProvider
      modelName = model.modelName(for: provider)
    }
    .onChange(of: provider) { newProvider in
      modelName = model.modelName(for: newProvider)
      apiKey = ""
    }
    .confirmationDialog(
      "从 macOS 钥匙串删除 \(provider.displayName) API Key？",
      isPresented: $showingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("删除 API Key", role: .destructive) {
        model.deleteAPIKey(for: provider)
      }
      Button("取消", role: .cancel) {}
    }
  }
}
