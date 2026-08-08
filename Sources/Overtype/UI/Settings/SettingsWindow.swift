import SwiftUI

public struct SettingsWindow: View {
  // The shared draft, not a per-window @StateObject (finding C5): two Settings
  // windows (the scene reachable via Cmd+comma plus the AppDelegate's own
  // window) each held an independent full-config draft, and saving in one
  // silently reverted what the other had saved. The shared model outlives any
  // window, which is exactly the ObservedObject contract.
  @ObservedObject private var viewModel: SettingsViewModel

  public init(viewModel: SettingsViewModel = .shared) {
    self.viewModel = viewModel
  }

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
    .frame(width: 640, height: 520)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      viewModel.reloadFromDisk()
    }
  }
}
