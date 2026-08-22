import ComposableArchitecture
import SwiftUI

struct CommandLineToolSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var isAskAgentHelpPresented = false

  var body: some View {
    Form {
      Section("Installation") {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            switch store.cliInstallStatus {
            case .installed(let path):
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Installed")
              Text("Installed at \(path)")
            case .installedDifferentSource(let path):
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityLabel("Different version")
              Text("A different version exists at \(path)")
            case .notInstalled:
              Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not installed")
              Text("Not installed")
            }
          }
          .font(.callout)

          Text("Install the prowl command to let terminals and coding agents control Prowl.")
            .foregroundStyle(.secondary)
            .font(.callout)

          HStack(spacing: 8) {
            switch store.cliInstallStatus {
            case .notInstalled:
              Button("Install") {
                store.send(.installCLIButtonTapped())
              }
              .help("Install prowl command line tool to /usr/local/bin")
              .buttonStyle(.bordered)
            case .installed:
              Button("Uninstall") {
                store.send(.uninstallCLIButtonTapped)
              }
              .help("Remove prowl command line tool from /usr/local/bin")
              .buttonStyle(.bordered)
            case .installedDifferentSource:
              Button("Reinstall") {
                store.send(.installCLIButtonTapped())
              }
              .help("Replace the existing prowl command with the version bundled in this app")
              .buttonStyle(.bordered)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
          store.send(.refreshCLIInstallStatus)
        }
      }

      Section("Connection") {
        LabeledContent("Socket") {
          Text(ProwlSocket.defaultPath)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Text("prowl connects to the running app through this local Unix socket.")
          .foregroundStyle(.secondary)
          .font(.callout)
      }

      Section("Ask Your Agent") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Give your coding agent a prompt that points it at Prowl's bundled documentation.")
            .foregroundStyle(.secondary)
            .font(.callout)
          Button("Ask Agent About Prowl…") {
            isAskAgentHelpPresented = true
          }
          .help("Copy a prompt that points your coding agent at Prowl's bundled docs")
          .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .sheet(isPresented: $isAskAgentHelpPresented) {
      AskAgentHelpView {
        isAskAgentHelpPresented = false
      }
    }
  }
}
