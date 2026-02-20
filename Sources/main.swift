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
        }
    }
}
