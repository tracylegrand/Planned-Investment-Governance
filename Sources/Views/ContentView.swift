import SwiftUI

struct ContentView: View {
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    @State private var isLoadingInitialData = true
    
    var body: some View {
        ZStack {
            if isLoadingInitialData {
                LoadingView(cacheProgress: dataService.cacheProgress)
            } else {
                TabView(selection: $navigationState.selectedTab) {
                    DashboardView(navigationState: navigationState)
                        .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                        .tag(0)
                    
                    InvestmentRequestsView(navigationState: navigationState)
                        .tabItem { Label("Requests", systemImage: "list.bullet.rectangle.fill") }
                        .tag(1)
                }
                .padding(.top, 8)
            }
        }
        .onAppear {
            dataService.loadInitialData {
                withAnimation {
                    isLoadingInitialData = false
                }
            }
        }
    }
}

struct LoadingView: View {
    let cacheProgress: CacheProgress
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle())
            
            Text("Planned Investment Governance")
                .font(.title)
                .fontWeight(.semibold)
            
            if cacheProgress.totalSteps > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(cacheProgress.stepsCompleted), total: Double(cacheProgress.totalSteps))
                        .frame(width: 200)
                    
                    Text(cacheProgress.message.isEmpty ? "Loading..." : cacheProgress.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(cacheProgress.message.isEmpty ? "Initializing..." : cacheProgress.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
