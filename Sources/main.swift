import SwiftUI

@main
struct PlannedInvestmentGovernanceApp: App {
    @StateObject private var dataService = DataService.shared
    @StateObject private var navigationState = NavigationState()
    
    var body: some Scene {
        WindowGroup {
            ContentView(navigationState: navigationState)
                .environmentObject(dataService)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Investment Governance") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Investment Governance",
                        .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        .version: "February 21, 2026",
                        .credits: NSAttributedString(string: "Author: Tracy LeGrand\n\nPlanned investment request and approval governance tool for Professional Services.")
                    ])
                }
            }
        }
    }
}
