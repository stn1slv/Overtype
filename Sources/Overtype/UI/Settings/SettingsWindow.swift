import SwiftUI

public struct SettingsWindow: View {
  @StateObject private var viewModel = SettingsViewModel()

  public init() {}

  public var body: some View {
    TabView {
      GeneralTab(viewModel: viewModel)
        .tabItem {
          Label("General", systemImage: "gear")
        }

      ActionsTab(viewModel: viewModel)
        .tabItem {
          Label("Actions", systemImage: "bolt.fill")
        }

      ProvidersTab(viewModel: viewModel)
        .tabItem {
          Label("Providers", systemImage: "network")
        }
    }
    .padding()
    .frame(width: 550, height: 450)
  }
}
