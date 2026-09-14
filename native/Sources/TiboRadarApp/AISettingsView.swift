import SwiftUI

struct AISettingsView: View {
  @EnvironmentObject private var model: RadarViewModel

  @State private var provider = AIProvider.deepSeek
  @State private var modelName = AIProvider.deepSeek.defaultModel
  @State private var apiKey = ""
  @State private var showingDeleteConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        fieldLabel("模型服务")
        providerSelector
      }

      Spacer()
        .frame(height: 26)

      VStack(alignment: .leading, spacing: 4) {
        fieldLabel("模型名称")
        TextField(provider.defaultModel, text: $modelName)
          .font(.system(size: 13))
          .textFieldStyle(.roundedBorder)
          .controlSize(.regular)
          .frame(height: 30)
      }

      Spacer()
        .frame(height: 26)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          fieldLabel("API Key")
          Spacer()
          if model.keyIsSaved(for: provider) {
            Label("已保存", systemImage: "checkmark.circle.fill")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.green)
          }
        }
        SecureField(
          model.keyIsSaved(for: provider) ? "留空继续使用已保存 Key" : "粘贴 API Key",
          text: $apiKey
        )
        .font(.system(size: 13))
        .textFieldStyle(.roundedBorder)
        .controlSize(.regular)
        .frame(height: 30)
      }

      if let message = model.settingsMessage {
        Label(
          message,
          systemImage: message.contains("成功") || message.contains("已保存")
            ? "checkmark.circle" : "info.circle"
        )
        .font(.system(size: 11))
        .foregroundStyle(
          message.contains("成功") || message.contains("已保存") ? .green : .orange
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
      }

      Spacer()
        .frame(height: 26)

      Divider()

      HStack(spacing: 8) {
        if model.keyIsSaved(for: provider) {
          Button("删除 Key", role: .destructive) {
            showingDeleteConfirmation = true
          }
          .buttonStyle(.plain)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        }

        Spacer()

        Button("仅保存") {
          _ = model.saveSettings(
            provider: provider,
            model: modelName,
            newAPIKey: apiKey
          )
          apiKey = ""
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 28)

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
            ProgressView()
              .controlSize(.small)
              .frame(minWidth: 64)
          } else {
            Text("保存并测试")
              .font(.system(size: 12, weight: .medium))
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(.green)
        .disabled(model.isTestingConnection)
      }
      .padding(.top, 10)
    }
    .padding(.horizontal, 18)
    .padding(.top, 14)
    .padding(.bottom, 14)
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

  private func fieldLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.secondary)
  }

  private var providerSelector: some View {
    HStack(spacing: 2) {
      ForEach(AIProvider.allCases) { option in
        Button {
          provider = option
        } label: {
          Text(option.displayName)
            .font(.system(size: 13, weight: provider == option ? .semibold : .regular))
            .foregroundStyle(provider == option ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
              provider == option ? Color.green : Color.clear,
              in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(provider == option ? .isSelected : [])
      }
    }
    .padding(2)
    .frame(height: 30)
    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    .overlay {
      RoundedRectangle(cornerRadius: 9)
        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
    }
    .animation(.easeInOut(duration: 0.12), value: provider)
  }
}
