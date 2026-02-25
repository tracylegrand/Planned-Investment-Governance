import SwiftUI

struct ContentView: View {
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    @State private var isLoadingInitialData = true
    @State private var showActAsSheet = false
    
    var body: some View {
        ZStack {
            if isLoadingInitialData {
                LoadingView(cacheProgress: dataService.cacheProgress, lastError: dataService.lastError) {
                    dataService.retryCacheRefresh {
                        if dataService.lastError == nil {
                            withAnimation {
                                isLoadingInitialData = false
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    if dataService.impersonationStatus.active {
                        HStack {
                            Image(systemName: "theatermasks.fill")
                                .foregroundColor(.white)
                            Text("Acting as: \(dataService.impersonationStatus.displayName ?? "Unknown") (\(dataService.impersonationStatus.title ?? ""))")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                    }
                    
                    TabView(selection: $navigationState.selectedTab) {
                        DashboardView(navigationState: navigationState)
                            .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                            .tag(0)
                        
                        InvestmentRequestsView(navigationState: navigationState)
                            .tabItem { Label("Requests", systemImage: "list.bullet.rectangle.fill") }
                            .tag(1)
                        
                        FinancialsView(navigationState: navigationState)
                            .tabItem { Label("Financials", systemImage: "dollarsign.circle.fill") }
                            .tag(2)
                    }
                    .padding(.top, 8)
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        if dataService.currentUser?.isAdmin == true {
                            Button(action: { showActAsSheet = true }) {
                                Label("Act As", systemImage: dataService.impersonationStatus.active ? "theatermasks.fill" : "theatermasks")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showActAsSheet) {
                    ActAsSheet(isPresented: $showActAsSheet)
                        .environmentObject(dataService)
                }
            }
        }
        .onAppear {
            dataService.loadInitialData {
                if dataService.lastError == nil {
                    withAnimation {
                        isLoadingInitialData = false
                    }
                }
                dataService.checkImpersonationStatus()
            }
        }
    }
}

struct ActAsSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataService: DataService
    @State private var searchText = ""
    @State private var searchResults: [WorkdayEmployee] = []
    @State private var isSearching = false
    @State private var searchRequestId: Int = 0
    @State private var debounceTask: DispatchWorkItem?
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Act As Employee")
                    .font(.headline)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
            }
            
            TextField("Search by name...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchText) { _, newValue in
                    debounceTask?.cancel()
                    guard newValue.count >= 2 else {
                        searchResults = []
                        isSearching = false
                        return
                    }
                    isSearching = true
                    let currentId = searchRequestId + 1
                    searchRequestId = currentId
                    let task = DispatchWorkItem {
                        dataService.searchEmployees(query: newValue) { results in
                            guard searchRequestId == currentId else { return }
                            searchResults = results
                            isSearching = false
                        }
                    }
                    debounceTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
                }
            
            if isSearching {
                ProgressView()
            }
            
            List(searchResults) { employee in
                VStack(alignment: .leading, spacing: 4) {
                    Text(employee.name)
                        .fontWeight(.medium)
                    HStack {
                        Text(employee.title ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let mgr = employee.managerName {
                            Text("Reports to: \(mgr)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    dataService.impersonate(employeeId: employee.employeeId) { success in
                        if success {
                            isPresented = false
                        }
                    }
                }
            }
            .frame(minHeight: 200)
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct LoadingView: View {
    let cacheProgress: CacheProgress
    let lastError: String?
    var onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            if lastError != nil || cacheProgress.status == "error" {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                
                Text("Planned Investment Governance")
                    .font(.title)
                    .fontWeight(.semibold)
                
                VStack(spacing: 8) {
                    Text(lastError ?? cacheProgress.message)
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            } else {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
