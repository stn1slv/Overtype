import SwiftUI

public struct SettingsWindow: View {
    public init() {}
    
    public var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            Text("Actions Configuration (Coming Soon)")
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
            
            Text("Providers Configuration (Coming Soon)")
                .tabItem {
                    Label("Providers", systemImage: "network")
                }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}
