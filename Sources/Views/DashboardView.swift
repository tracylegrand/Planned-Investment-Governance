import SwiftUI

class UserSettings: ObservableObject {
    static let shared = UserSettings()
    
    @Published var defaultTheater: String {
        didSet { UserDefaults.standard.set(defaultTheater, forKey: "defaultTheater") }
    }
    @Published var defaultPortfolios: Set<String> {
        didSet { UserDefaults.standard.set(Array(defaultPortfolios), forKey: "defaultPortfolios") }
    }
    @Published var defaultQuarterSelection: String {
        didSet { UserDefaults.standard.set(defaultQuarterSelection, forKey: "defaultQuarterSelection") }
    }
    @Published var showVerticalBars: Bool {
        didSet { UserDefaults.standard.set(showVerticalBars, forKey: "showVerticalBars") }
    }
    @Published var showHorizontalFlow: Bool {
        didSet { UserDefaults.standard.set(showHorizontalFlow, forKey: "showHorizontalFlow") }
    }
    @Published var showCompactPills: Bool {
        didSet { UserDefaults.standard.set(showCompactPills, forKey: "showCompactPills") }
    }
    @Published var showStepper: Bool {
        didSet { UserDefaults.standard.set(showStepper, forKey: "showStepper") }
    }
    @Published var showMiniBars: Bool {
        didSet { UserDefaults.standard.set(showMiniBars, forKey: "showMiniBars") }
    }
    
    private init() {
        self.defaultTheater = UserDefaults.standard.string(forKey: "defaultTheater") ?? "All"
        self.defaultPortfolios = Set(UserDefaults.standard.stringArray(forKey: "defaultPortfolios") ?? [])
        self.defaultQuarterSelection = UserDefaults.standard.string(forKey: "defaultQuarterSelection") ?? "Current Quarter"
        self.showVerticalBars = UserDefaults.standard.object(forKey: "showVerticalBars") as? Bool ?? true
        self.showHorizontalFlow = UserDefaults.standard.object(forKey: "showHorizontalFlow") as? Bool ?? true
        self.showCompactPills = UserDefaults.standard.object(forKey: "showCompactPills") as? Bool ?? true
        self.showStepper = UserDefaults.standard.object(forKey: "showStepper") as? Bool ?? true
        self.showMiniBars = UserDefaults.standard.object(forKey: "showMiniBars") as? Bool ?? true
    }
}

struct SettingsView: View {
    @ObservedObject var settings = UserSettings.shared
    @EnvironmentObject var dataService: DataService
    @Environment(\.dismiss) var dismiss
    
    @State private var tempDefaultTheater: String
    @State private var tempDefaultPortfolios: Set<String>
    @State private var tempDefaultQuarterSelection: String
    @State private var tempShowVerticalBars: Bool
    @State private var tempShowHorizontalFlow: Bool
    @State private var tempShowCompactPills: Bool
    @State private var tempShowStepper: Bool
    @State private var tempShowMiniBars: Bool
    @State private var showPortfolioPicker = false
    
    private var theaters: [String] {
        ["All"] + dataService.sfdcTheaters
    }
    private let quarterOptions = ["Current Quarter", "Current Fiscal Year", "All Quarters"]
    
    private var availableIndustries: [String] {
        if tempDefaultTheater == "All" {
            return dataService.sfdcIndustries
        }
        return dataService.sfdcIndustriesByTheater[tempDefaultTheater] ?? []
    }
    
    private var portfolioButtonLabel: String {
        if tempDefaultPortfolios.isEmpty {
            return "All"
        } else if tempDefaultPortfolios.count == 1 {
            return tempDefaultPortfolios.first!
        } else {
            return "\(tempDefaultPortfolios.count) selected"
        }
    }
    
    private var atLeastOneSelected: Bool {
        tempShowVerticalBars || tempShowHorizontalFlow || tempShowCompactPills || tempShowStepper || tempShowMiniBars
    }
    
    init() {
        let s = UserSettings.shared
        _tempDefaultTheater = State(initialValue: s.defaultTheater)
        _tempDefaultPortfolios = State(initialValue: s.defaultPortfolios)
        _tempDefaultQuarterSelection = State(initialValue: s.defaultQuarterSelection)
        _tempShowVerticalBars = State(initialValue: s.showVerticalBars)
        _tempShowHorizontalFlow = State(initialValue: s.showHorizontalFlow)
        _tempShowCompactPills = State(initialValue: s.showCompactPills)
        _tempShowStepper = State(initialValue: s.showStepper)
        _tempShowMiniBars = State(initialValue: s.showMiniBars)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 16)
                .padding(.bottom, 12)
            
            Divider()
            
            Form {
                Section("Default Filters") {
                    Picker("Default Theater", selection: $tempDefaultTheater) {
                        ForEach(theaters, id: \.self) { Text($0) }
                    }
                    .onChange(of: tempDefaultTheater) { _, _ in
                        tempDefaultPortfolios = tempDefaultPortfolios.filter { availableIndustries.contains($0) }
                    }
                    
                    HStack {
                        Text("Default Industry(s)")
                        Spacer()
                        Button(action: { showPortfolioPicker.toggle() }) {
                            HStack(spacing: 4) {
                                Text(portfolioButtonLabel)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showPortfolioPicker, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Button(action: {
                                        if tempDefaultPortfolios.count == availableIndustries.count {
                                            tempDefaultPortfolios.removeAll()
                                        } else {
                                            tempDefaultPortfolios = Set(availableIndustries)
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: tempDefaultPortfolios.count == availableIndustries.count ? "checkmark.square.fill" : "square")
                                                .foregroundColor(tempDefaultPortfolios.count == availableIndustries.count ? .blue : .secondary)
                                            Text("Select All")
                                                .fontWeight(.medium)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                    Button("Clear") {
                                        tempDefaultPortfolios.removeAll()
                                    }
                                    .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                
                                Divider()
                                
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(availableIndustries, id: \.self) { portfolio in
                                            Button(action: {
                                                if tempDefaultPortfolios.contains(portfolio) {
                                                    tempDefaultPortfolios.remove(portfolio)
                                                } else {
                                                    tempDefaultPortfolios.insert(portfolio)
                                                }
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: tempDefaultPortfolios.contains(portfolio) ? "checkmark.square.fill" : "square")
                                                        .foregroundColor(tempDefaultPortfolios.contains(portfolio) ? .blue : .secondary)
                                                    Text(portfolio)
                                                    Spacer()
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 4)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .frame(maxHeight: 200)
                            }
                            .frame(width: 200)
                        }
                    }
                    
                    Picker("Default Quarter(s) View", selection: $tempDefaultQuarterSelection) {
                        ForEach(quarterOptions, id: \.self) { Text($0) }
                    }
                }
                
                Section("Approval Pipeline Display Options") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Vertical Bars", isOn: $tempShowVerticalBars)
                        Toggle("Horizontal Flow", isOn: $tempShowHorizontalFlow)
                        Toggle("Compact Pills", isOn: $tempShowCompactPills)
                        Toggle("Stepper", isOn: $tempShowStepper)
                        Toggle("Mini Bars", isOn: $tempShowMiniBars)
                        
                        if !atLeastOneSelected {
                            Text("At least one pipeline style must be selected")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("OK") {
                    settings.defaultTheater = tempDefaultTheater
                    settings.defaultPortfolios = tempDefaultPortfolios
                    settings.defaultQuarterSelection = tempDefaultQuarterSelection
                    settings.showVerticalBars = tempShowVerticalBars
                    settings.showHorizontalFlow = tempShowHorizontalFlow
                    settings.showCompactPills = tempShowCompactPills
                    settings.showStepper = tempShowStepper
                    settings.showMiniBars = tempShowMiniBars
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!atLeastOneSelected)
            }
            .padding()
        }
        .frame(width: 450, height: 420)
    }
}

struct DashboardView: View {
    @ObservedObject var navigationState: NavigationState
    @ObservedObject var userSettings = UserSettings.shared
    @EnvironmentObject var dataService: DataService
    
    @State private var selectedTheater: String = "All"
    @State private var selectedIndustries: Set<String> = []
    @State private var selectedQuarters: Set<String> = []
    @State private var selectedStatus: String = "All"
    @State private var showQuarterPicker = false
    @State private var showIndustryPicker = false
    @State private var showSettings = false
    @State private var hasInitialized = false
    
    private var hasActiveFilters: Bool {
        selectedTheater != "All" || !selectedIndustries.isEmpty || !selectedQuarters.isEmpty || selectedStatus != "All"
    }
    
    private var filtersDescription: String {
        var parts: [String] = []
        
        if selectedTheater != "All" {
            parts.append(selectedTheater)
        } else {
            parts.append("All Theaters")
        }
        
        if !selectedIndustries.isEmpty {
            if selectedIndustries.count == 1 {
                parts.append(selectedIndustries.first!)
            } else {
                parts.append("\(selectedIndustries.count) Industries")
            }
        }
        
        if !selectedQuarters.isEmpty {
            let sortedQuarters = selectedQuarters.sorted()
            if selectedQuarters.count == 1 {
                parts.append(sortedQuarters.first!)
            } else if selectedQuarters.count <= 3 {
                parts.append(sortedQuarters.joined(separator: ", "))
            } else {
                parts.append("\(selectedQuarters.count) Quarters")
            }
        } else {
            parts.append("All Quarters")
        }
        
        return "Filters: " + parts.joined(separator: " • ")
    }
    
    private func clearAllFilters() {
        selectedTheater = "All"
        selectedIndustries = []
        selectedQuarters = []
        selectedStatus = "All"
    }
    
    private func initializeFilters() {
        guard !hasInitialized else { return }
        hasInitialized = true
        
        selectedTheater = userSettings.defaultTheater
        selectedIndustries = userSettings.defaultPortfolios
        
        switch userSettings.defaultQuarterSelection {
        case "Current Quarter":
            selectedQuarters = [currentFiscalQuarter]
        case "Current Fiscal Year":
            let fy = currentFiscalYearAndQuarter.year
            selectedQuarters = Set((1...4).map { "FY\(fy)-Q\($0)" })
        case "All Quarters":
            selectedQuarters = []
        default:
            selectedQuarters = [currentFiscalQuarter]
        }
    }
    
    private func navigateToRequests(status: String, pendingMyApproval: Bool = false, myRequests: Bool = false) {
        navigationState.passedStatus = status
        navigationState.passedQuarters = selectedQuarters
        navigationState.passedTheater = selectedTheater
        navigationState.passedIndustries = selectedIndustries
        navigationState.filterPendingMyApproval = pendingMyApproval
        navigationState.filterMyRequests = myRequests
        navigationState.selectedTab = 1
        navigationState.triggerNavigation()
    }
    
    private var currentFiscalQuarter: String {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        // Snowflake fiscal year: Q1=Feb-Apr, Q2=May-Jul, Q3=Aug-Oct, Q4=Nov-Jan
        // FY starts Feb 1, so Jan 2026 is still FY2026-Q4
        let (fiscalYear, quarter): (Int, Int)
        switch month {
        case 2, 3, 4:
            fiscalYear = year + 1
            quarter = 1
        case 5, 6, 7:
            fiscalYear = year + 1
            quarter = 2
        case 8, 9, 10:
            fiscalYear = year + 1
            quarter = 3
        case 11, 12:
            fiscalYear = year + 2
            quarter = 4
        case 1:
            fiscalYear = year + 1
            quarter = 4
        default:
            fiscalYear = year + 1
            quarter = 1
        }
        return "FY\(fiscalYear)-Q\(quarter)"
    }
    
    private var theaters: [String] {
        ["All"] + dataService.sfdcTheaters
    }
    
    private var availableIndustries: [String] {
        if selectedTheater == "All" {
            return dataService.sfdcIndustries
        }
        return dataService.sfdcIndustriesByTheater[selectedTheater] ?? []
    }
    private let statuses = ["All", "DRAFT", "SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED", "FINAL_APPROVED", "REJECTED"]
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var currentFiscalYearAndQuarter: (year: Int, quarter: Int) {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        switch month {
        case 2, 3, 4:
            return (year + 1, 1)
        case 5, 6, 7:
            return (year + 1, 2)
        case 8, 9, 10:
            return (year + 1, 3)
        case 11, 12:
            return (year + 2, 4)
        case 1:
            return (year + 1, 4)
        default:
            return (year + 1, 1)
        }
    }
    
    var quartersGroupedByYear: [(year: String, quarters: [String])] {
        let (currentFY, currentQ) = currentFiscalYearAndQuarter
        let previousFY = currentFY - 1
        
        var result: [(year: String, quarters: [String])] = []
        
        if currentQ == 4 {
            let nextFY = currentFY + 1
            result.append((year: "FY\(nextFY)", quarters: ["FY\(nextFY)-Q1", "FY\(nextFY)-Q2"]))
        }
        
        result.append((year: "FY\(currentFY)", quarters: ["FY\(currentFY)-Q1", "FY\(currentFY)-Q2", "FY\(currentFY)-Q3", "FY\(currentFY)-Q4"]))
        result.append((year: "FY\(previousFY)", quarters: ["FY\(previousFY)-Q1", "FY\(previousFY)-Q2", "FY\(previousFY)-Q3", "FY\(previousFY)-Q4"]))
        
        return result
    }
    
    var filteredRequests: [InvestmentRequest] {
        dataService.investmentRequests.filter { request in
            let matchesTheater = selectedTheater == "All" || request.theater == selectedTheater
            let matchesIndustry = selectedIndustries.isEmpty || selectedIndustries.contains(request.industrySegment ?? "")
            let matchesQuarter: Bool
            if selectedQuarters.isEmpty {
                matchesQuarter = true
            } else if selectedQuarters.contains(request.investmentQuarter ?? "") {
                matchesQuarter = true
            } else {
                let yearSelections = selectedQuarters.filter { !$0.contains("-Q") }
                matchesQuarter = yearSelections.contains { year in
                    request.investmentQuarter?.hasPrefix(year) == true
                }
            }
            let matchesStatus = selectedStatus == "All" || request.status == selectedStatus
            return matchesTheater && matchesIndustry && matchesQuarter && matchesStatus
        }
    }
    
    var totalMyRequests: Int {
        let currentUserName = dataService.currentUser?.displayName
        let currentUsername = dataService.currentUser?.snowflakeUsername
        let currentEmployeeId = dataService.currentUser?.employeeId
        return dataService.investmentRequests.filter { request in
            let isCreator = request.createdByName == currentUserName ||
                request.createdBy == currentUsername ||
                (currentEmployeeId != nil && (request.createdByEmployeeId == currentEmployeeId || request.onBehalfOfEmployeeId == currentEmployeeId))
            let isPendingApproval = ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains(request.status)
            let isMyApproval = isPendingApproval && request.nextApproverName == currentUserName
            return isCreator || isMyApproval
        }.count
    }
    
    var filteredSummary: (total: Int, draft: Int, pendingApproval: Int, rejected: Int, approved: Int, totalRequested: Double, draftAmount: Double, pendingAmount: Double, rejectedAmount: Double, approvedAmount: Double) {
        let requests = filteredRequests
        let draftRequests = requests.filter { $0.status == "DRAFT" }
        let draft = draftRequests.count
        let draftAmount = draftRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        let pendingRequests = requests.filter { ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains($0.status) }
        let pendingApproval = pendingRequests.count
        let pendingAmount = pendingRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        let rejectedRequests = requests.filter { $0.status == "REJECTED" }
        let rejected = rejectedRequests.count
        let rejectedAmount = rejectedRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        let approvedRequests = requests.filter { $0.status == "FINAL_APPROVED" }
        let approved = approvedRequests.count
        let approvedAmount = approvedRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        let totalRequested = requests.compactMap { $0.requestedAmount }.reduce(0, +)
        
        return (requests.count, draft, pendingApproval, rejected, approved, totalRequested, draftAmount, pendingAmount, rejectedAmount, approvedAmount)
    }
    
    var fiscalYears: [String] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        let currentFY: Int
        if month >= 2 {
            currentFY = year + 1
        } else {
            currentFY = year
        }
        
        let prevYear = "FY\(currentFY - 1)"
        let currYear = "FY\(currentFY)"
        return [prevYear, currYear]
    }
    
    var requestsByFiscalYear: [(year: String, count: Int, amount: Double)] {
        let allQuarters = Set(filteredRequests.compactMap { $0.investmentQuarter })
        var yearTotals: [String: (count: Int, amount: Double)] = [:]
        
        for quarter in allQuarters {
            if let fyRange = quarter.range(of: "FY") {
                let yearPart = String(quarter[fyRange.lowerBound...].prefix(6))
                let requests = filteredRequests.filter { $0.investmentQuarter == quarter }
                let count = requests.count
                let amount = requests.compactMap { $0.requestedAmount }.reduce(0, +)
                
                if let existing = yearTotals[yearPart] {
                    yearTotals[yearPart] = (existing.count + count, existing.amount + amount)
                } else {
                    yearTotals[yearPart] = (count, amount)
                }
            }
        }
        
        return yearTotals.map { (year: $0.key, count: $0.value.count, amount: $0.value.amount) }
            .sorted { $0.year > $1.year }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Investment Governance Dashboard")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if let user = dataService.currentUser {
                        HStack(spacing: 6) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(user.displayName)
                                    .font(.headline)
                                if let title = user.title {
                                    Text(title)
                                        .font(.subheadline)
                                        .foregroundColor(dataService.impersonationStatus.active ? .orange : .secondary)
                                }
                            }
                            if dataService.impersonationStatus.active {
                                Button(action: {
                                    dataService.stopImpersonating { _ in }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Clear impersonation")
                            }
                        }
                        .padding(.horizontal, dataService.impersonationStatus.active ? 10 : 0)
                        .padding(.vertical, dataService.impersonationStatus.active ? 6 : 0)
                        .overlay(
                            Group {
                                if dataService.impersonationStatus.active {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange, lineWidth: 2)
                                }
                            }
                        )
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Button {
                                navigationState.filterMyRequests = true
                                navigationState.passedStatus = ""
                                navigationState.passedQuarters = []
                                navigationState.passedTheater = ""
                                navigationState.passedIndustries = []
                                navigationState.filterPendingMyApproval = true
                                navigationState.selectedTab = 1
                                navigationState.triggerNavigation()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.fill")
                                    Text("My Requests (\(totalMyRequests))")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.purple, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.purple)
                            
                            HStack(spacing: 8) {
                                Text("v\(appVersion)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button {
                                    showSettings = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "gear")
                                        Text("Settings")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.blue, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.horizontal)
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
                
                HStack(spacing: 12) {
                    Picker("Theater", selection: $selectedTheater) {
                        ForEach(theaters, id: \.self) { Text($0) }
                    }
                    .frame(width: 180)
                    
                    Button {
                        showIndustryPicker.toggle()
                    } label: {
                        HStack {
                            Text(selectedIndustries.isEmpty ? "All Industries" : "\(selectedIndustries.count) Selected")
                            Image(systemName: "chevron.down")
                        }
                        .frame(width: 140)
                    }
                    .disabled(availableIndustries.isEmpty)
                    .popover(isPresented: $showIndustryPicker, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Select Industries")
                                    .font(.headline)
                                Spacer()
                                Button("Clear") {
                                    selectedIndustries.removeAll()
                                }
                                .disabled(selectedIndustries.isEmpty)
                                Button("Done") {
                                    showIndustryPicker = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.bottom, 4)
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    if selectedIndustries.count == availableIndustries.count {
                                        selectedIndustries.removeAll()
                                    } else {
                                        selectedIndustries = Set(availableIndustries)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: selectedIndustries.count == availableIndustries.count ? "checkmark.square.fill" : "square")
                                            .foregroundColor(selectedIndustries.count == availableIndustries.count ? .blue : .secondary)
                                        Text("All")
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(availableIndustries, id: \.self) { industry in
                                    Button {
                                        if selectedIndustries.contains(industry) {
                                            selectedIndustries.remove(industry)
                                        } else {
                                            selectedIndustries.insert(industry)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: selectedIndustries.contains(industry) ? "checkmark.square.fill" : "square")
                                                .foregroundColor(selectedIndustries.contains(industry) ? .blue : .secondary)
                                            Text(industry)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(.leading, 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                        .frame(width: 320)
                    }
                    
                    Button {
                        showQuarterPicker.toggle()
                    } label: {
                        HStack {
                            Text(selectedQuarters.isEmpty ? "All Quarters" : "\(selectedQuarters.count) Selected")
                            Image(systemName: "chevron.down")
                        }
                        .frame(width: 120)
                    }
                    .popover(isPresented: $showQuarterPicker, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Select Quarters")
                                    .font(.headline)
                                Spacer()
                                Button("Clear") {
                                    selectedQuarters.removeAll()
                                }
                                .disabled(selectedQuarters.isEmpty)
                                Button("Done") {
                                    showQuarterPicker = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.bottom, 4)
                            
                            Divider()
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(quartersGroupedByYear, id: \.year) { group in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Button {
                                                if selectedQuarters.contains(group.year) {
                                                    selectedQuarters.remove(group.year)
                                                    for q in group.quarters {
                                                        selectedQuarters.remove(q)
                                                    }
                                                } else {
                                                    selectedQuarters.insert(group.year)
                                                    for q in group.quarters {
                                                        selectedQuarters.insert(q)
                                                    }
                                                }
                                            } label: {
                                                HStack {
                                                    Image(systemName: selectedQuarters.contains(group.year) ? "checkmark.square.fill" : "square")
                                                        .foregroundColor(selectedQuarters.contains(group.year) ? .blue : .secondary)
                                                    Text(group.year + " (All)")
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            
                                            ForEach(group.quarters, id: \.self) { quarter in
                                                Button {
                                                    if selectedQuarters.contains(quarter) {
                                                        selectedQuarters.remove(quarter)
                                                        selectedQuarters.remove(group.year)
                                                    } else {
                                                        selectedQuarters.insert(quarter)
                                                        if group.quarters.allSatisfy({ selectedQuarters.contains($0) }) {
                                                            selectedQuarters.insert(group.year)
                                                        }
                                                    }
                                                } label: {
                                                    HStack {
                                                        Image(systemName: selectedQuarters.contains(quarter) ? "checkmark.square.fill" : "square")
                                                            .foregroundColor(selectedQuarters.contains(quarter) ? .blue : .secondary)
                                                        Text(quarter)
                                                            .foregroundColor(.primary)
                                                        Spacer()
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.leading, 20)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 300)
                        }
                        .padding()
                        .frame(width: 200)
                    }
                    
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(statuses, id: \.self) { Text($0) }
                    }
                    .frame(width: 150)
                    
                    Button(action: clearAllFilters) {
                        Text("Clear")
                    }
                    .disabled(!hasActiveFilters)
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.vertical, 8)
                
                let summary = filteredSummary
                let sectionWidth: CGFloat = 1040
                
                // Section 1: Summary of Requests
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary of Requests")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(filtersDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 2)
                            
                            HStack(spacing: 0) {
                                SummaryCardCompact(title: "Draft", value: "\(summary.draft)", color: .gray, action: {
                                    navigateToRequests(status: "DRAFT")
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Pending Approval", value: "\(summary.pendingApproval)", color: .orange, action: {
                                    navigateToRequests(status: "IN_REVIEW")
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Rejected", value: "\(summary.rejected)", color: .red, action: {
                                    navigateToRequests(status: "REJECTED")
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Approved", value: "\(summary.approved)", color: .green, action: {
                                    navigateToRequests(status: "FINAL_APPROVED")
                                })
                                .frame(maxWidth: .infinity)
                            }
                            
                            HStack(spacing: 0) {
                                SummaryCardCompact(title: "Draft Amount", value: formatCurrency(summary.draftAmount), color: .gray, action: {
                                    navigateToRequests(status: "DRAFT")
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Pending Amount", value: formatCurrency(summary.pendingAmount), color: .orange, action: {
                                    navigateToRequests(status: "IN_REVIEW")
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Rejected Amount", value: formatCurrency(summary.rejectedAmount), color: .red, action: {
                                    navigateToRequests(status: "REJECTED")
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Approved Amount", value: formatCurrency(summary.approvedAmount), color: .green, action: {
                                    navigateToRequests(status: "FINAL_APPROVED")
                                })
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(8)
                    }
                    .frame(width: sectionWidth)
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Section 2: Approval Pipeline by Fiscal Year - Comparison of 5 Options
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Original Style - Vertical Bars
                    if userSettings.showVerticalBars {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Approval Pipeline (Vertical Bars)")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            GroupBox {
                                ApprovalPipelineView(requests: filteredRequests, selectedTheater: selectedTheater, selectedIndustries: selectedIndustries, navigationState: navigationState)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                            }
                            .frame(width: sectionWidth)
                        }
                        
                        if userSettings.showHorizontalFlow || userSettings.showCompactPills || userSettings.showStepper || userSettings.showMiniBars {
                            Divider()
                        }
                    }
                    
                    // Horizontal Flow
                    if userSettings.showHorizontalFlow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Approval Pipeline (Horizontal Flow)")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            GroupBox {
                                HorizontalFlowPipeline(requests: filteredRequests, selectedTheater: selectedTheater, selectedIndustries: selectedIndustries, navigationState: navigationState)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                            }
                            .frame(width: sectionWidth)
                        }
                        
                        if userSettings.showCompactPills || userSettings.showStepper || userSettings.showMiniBars {
                            Divider()
                        }
                    }
                    
                    // Compact Pills
                    if userSettings.showCompactPills {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Approval Pipeline (Compact Pills)")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            GroupBox {
                                CompactPillPipeline(requests: filteredRequests, selectedTheater: selectedTheater, selectedIndustries: selectedIndustries, navigationState: navigationState)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                            }
                            .frame(width: sectionWidth)
                        }
                        
                        if userSettings.showStepper || userSettings.showMiniBars {
                            Divider()
                        }
                    }
                    
                    // Stepper
                    if userSettings.showStepper {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Approval Pipeline (Stepper)")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            GroupBox {
                                StepperPipeline(requests: filteredRequests, selectedTheater: selectedTheater, selectedIndustries: selectedIndustries, navigationState: navigationState)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                            }
                            .frame(width: sectionWidth)
                        }
                        
                        if userSettings.showMiniBars {
                            Divider()
                        }
                    }
                    
                    // Two-Row Arrows / Mini Bars
                    if userSettings.showMiniBars {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Approval Pipeline (Mini Bars)")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            GroupBox {
                                TwoRowArrowsPipeline(requests: filteredRequests, selectedTheater: selectedTheater, selectedIndustries: selectedIndustries, navigationState: navigationState)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                            }
                            .frame(width: sectionWidth)
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.vertical)
        }
        .onAppear { initializeFilters() }
        .onChange(of: selectedTheater) { _, _ in
            if availableIndustries.isEmpty {
                selectedIndustries.removeAll()
            } else {
                selectedIndustries = selectedIndustries.filter { availableIndustries.contains($0) }
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    private func formatCurrencyAligned(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "%6.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "%6.1fK", amount / 1_000)
        } else if amount > 0 {
            return String(format: "%6.0f ", amount)
        } else {
            return "     0 "
        }
    }
    
    private func statusDisplayName(_ status: String) -> String {
        switch status {
        case "DRAFT": return "Draft"
        case "SUBMITTED": return "Submitted"
        case "DM_APPROVED": return "DM Approved"
        case "RD_APPROVED": return "RD Approved"
        case "AVP_APPROVED": return "AVP Approved"
        case "FINAL_APPROVED": return "Final Approved"
        case "REJECTED": return "Rejected"
        default: return status
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "DRAFT": return .gray
        case "SUBMITTED": return .orange
        case "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED": return .blue
        case "FINAL_APPROVED": return .green
        case "REJECTED": return .red
        default: return .gray
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let color: Color
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.7))
                
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [color, color.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(10)
            .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

struct SummaryCardCompact: View {
    let title: String
    let value: String
    let color: Color
    var action: (() -> Void)? = nil
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(1)
                
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            .frame(width: 150, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(isHovering ? 1.0 : 0.9), color.opacity(isHovering ? 0.9 : 0.7)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.black.opacity(0.3) : Color.clear, lineWidth: 2)
            )
            .shadow(color: color.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct ReportRow: View {
    let label: String
    let count: Int
    let amount: Double
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
            
            Spacer()
            
            Text("\(count)")
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
            
            Text(formatCurrency(amount))
                .fontWeight(.medium)
                .frame(width: 100, alignment: .trailing)
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
}

struct ApprovalPipelineView: View {
    let requests: [InvestmentRequest]
    let selectedTheater: String
    let selectedIndustries: Set<String>
    @ObservedObject var navigationState: NavigationState
    
    private var fiscalYears: [String] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        let currentFY: Int
        if month >= 2 {
            currentFY = year + 1
        } else {
            currentFY = year
        }
        
        let prevYear = "FY\(currentFY - 1)"
        let currYear = "FY\(currentFY)"
        return [prevYear, currYear]
    }
    
    private func stagesForYear(_ year: String) -> [(String, Int, Double)] {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        return [
            ("Draft", yearRequests.filter { $0.status == "DRAFT" }.count, yearRequests.filter { $0.status == "DRAFT" }.compactMap { $0.requestedAmount }.reduce(0, +)),
            ("Submitted", yearRequests.filter { $0.status == "SUBMITTED" }.count, yearRequests.filter { $0.status == "SUBMITTED" }.compactMap { $0.requestedAmount }.reduce(0, +)),
            ("DM Review", yearRequests.filter { $0.status == "DM_APPROVED" }.count, yearRequests.filter { $0.status == "DM_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +)),
            ("RD Review", yearRequests.filter { $0.status == "RD_APPROVED" }.count, yearRequests.filter { $0.status == "RD_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +)),
            ("AVP Review", yearRequests.filter { $0.status == "AVP_APPROVED" }.count, yearRequests.filter { $0.status == "AVP_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +)),
            ("Rejected", yearRequests.filter { $0.status == "REJECTED" }.count, yearRequests.filter { $0.status == "REJECTED" }.compactMap { $0.requestedAmount }.reduce(0, +)),
            ("Approved", yearRequests.filter { $0.status == "FINAL_APPROVED" }.count, yearRequests.filter { $0.status == "FINAL_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +))
        ]
    }
    
    private var maxCount: Int {
        fiscalYears.flatMap { stagesForYear($0).map { $0.1 } }.max() ?? 1
    }
    
    private func summaryForYear(_ year: String) -> (count: Int, amount: Double) {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        let count = yearRequests.count
        let amount = yearRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        return (count, amount)
    }
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else if amount > 0 {
            return String(format: "$%.0f", amount)
        } else {
            return "$0"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(fiscalYears, id: \.self) { year in
                let summary = summaryForYear(year)
                VStack(spacing: 6) {
                    Text("\(year): \(summary.count) requests, \(formatCurrencyShort(summary.amount))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(stagesForYear(year), id: \.0) { stage in
                            PipelineStageBox(
                                stageName: stage.0,
                                count: stage.1,
                                value: stage.2,
                                maxCount: maxCount,
                                color: colorForStage(stage.0),
                                onTap: {
                                    navigationState.passedStatus = statusCodeForStage(stage.0)
                                    navigationState.passedQuarters = [year]
                                    navigationState.passedTheater = selectedTheater
                                    navigationState.passedIndustries = selectedIndustries
                                    navigationState.selectedTab = 1
                                    navigationState.triggerNavigation()
                                }
                            )
                        }
                    }
                }
                .padding(6)
            }
        }
    }
    
    private func statusCodeForStage(_ stage: String) -> String {
        switch stage {
        case "Draft": return "DRAFT"
        case "Submitted": return "SUBMITTED"
        case "DM Review": return "DM_APPROVED"
        case "RD Review": return "RD_APPROVED"
        case "AVP Review": return "AVP_APPROVED"
        case "Approved": return "FINAL_APPROVED"
        default: return "All"
        }
    }
    
    private func colorForStage(_ stage: String) -> Color {
        switch stage {
        case "Draft": return .gray
        case "Submitted": return .orange
        case "DM Review", "RD Review", "AVP Review": return .blue
        case "Approved": return .green
        default: return .gray
        }
    }
}

struct PipelineStageBox: View {
    let stageName: String
    let count: Int
    let value: Double
    let maxCount: Int
    let color: Color
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(color)
                    .frame(width: 36, height: CGFloat(count) / CGFloat(max(maxCount, 1)) * 50)
                    .frame(minHeight: count > 0 ? 8 : 0)
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 36, height: 1)
            }
            .frame(height: 55)
            
            Text(stageName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.black)
                .frame(width: 54)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(isHovering ? Color(NSColor.controlBackgroundColor).opacity(0.7) : Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isHovering ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isHovering ? 2 : 1)
        )
        .cornerRadius(4)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            onTap()
        }
        .popover(isPresented: .constant(isHovering), arrowEdge: .top) {
            Text(formatCurrencyShort(value))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }
    
    private var displayName: String {
        switch status {
        case "DRAFT": return "Draft"
        case "SUBMITTED": return "Submitted"
        case "DM_APPROVED": return "DM Approved"
        case "RD_APPROVED": return "RD Approved"
        case "AVP_APPROVED": return "AVP Approved"
        case "FINAL_APPROVED": return "Approved"
        case "REJECTED": return "Rejected"
        default: return status
        }
    }
    
    private var backgroundColor: Color {
        switch status {
        case "DRAFT": return .gray.opacity(0.2)
        case "SUBMITTED": return .orange.opacity(0.2)
        case "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED": return .blue.opacity(0.2)
        case "FINAL_APPROVED": return .green.opacity(0.2)
        case "REJECTED": return .red.opacity(0.2)
        default: return .gray.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case "DRAFT": return .gray
        case "SUBMITTED": return .orange
        case "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED": return .blue
        case "FINAL_APPROVED": return .green
        case "REJECTED": return .red
        default: return .gray
        }
    }
}

// MARK: - Option 1: Horizontal Flow Pipeline
struct HorizontalFlowPipeline: View {
    let requests: [InvestmentRequest]
    let selectedTheater: String
    let selectedIndustries: Set<String>
    let navigationState: NavigationState
    
    private var fiscalYears: [String] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let currentFY = month >= 2 ? year + 1 : year
        return ["FY\(currentFY - 1)", "FY\(currentFY)"]
    }
    
    private func stagesForYear(_ year: String) -> [(String, Int, Double, Color, String)] {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        return [
            ("Draft", yearRequests.filter { $0.status == "DRAFT" }.count, yearRequests.filter { $0.status == "DRAFT" }.compactMap { $0.requestedAmount }.reduce(0, +), .gray, "DRAFT"),
            ("Submitted", yearRequests.filter { $0.status == "SUBMITTED" }.count, yearRequests.filter { $0.status == "SUBMITTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .orange, "SUBMITTED"),
            ("DM", yearRequests.filter { $0.status == "DM_APPROVED" }.count, yearRequests.filter { $0.status == "DM_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "DM_APPROVED"),
            ("RD", yearRequests.filter { $0.status == "RD_APPROVED" }.count, yearRequests.filter { $0.status == "RD_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "RD_APPROVED"),
            ("AVP", yearRequests.filter { $0.status == "AVP_APPROVED" }.count, yearRequests.filter { $0.status == "AVP_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "AVP_APPROVED"),
            ("Rejected", yearRequests.filter { $0.status == "REJECTED" }.count, yearRequests.filter { $0.status == "REJECTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .red, "REJECTED"),
            ("Approved", yearRequests.filter { $0.status == "FINAL_APPROVED" }.count, yearRequests.filter { $0.status == "FINAL_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .green, "FINAL_APPROVED")
        ]
    }
    
    private func yearSummary(_ year: String) -> (count: Int, amount: Double) {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        let count = yearRequests.count
        let amount = yearRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        return (count, amount)
    }
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fiscalYears, id: \.self) { year in
                let summary = yearSummary(year)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(year): \(summary.count) requests • \(formatCurrencyShort(summary.amount))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        ForEach(Array(stagesForYear(year).enumerated()), id: \.offset) { index, stage in
                            FlowBox(name: stage.0, count: stage.1, value: stage.2, color: stage.3) {
                                navigationState.passedStatus = stage.4
                                navigationState.passedQuarters = [year]
                                navigationState.passedTheater = selectedTheater
                                navigationState.passedIndustries = selectedIndustries
                                navigationState.selectedTab = 1
                                navigationState.triggerNavigation()
                            }
                            
                            if index < 6 {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct FlowBox: View {
    let name: String
    let count: Int
    let value: Double
    let color: Color
    let onTap: () -> Void
    @State private var isHovering = false
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
            Text(name)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(color.opacity(isHovering ? 0.3 : 0.15))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
        .cornerRadius(4)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture { onTap() }
        .popover(isPresented: .constant(isHovering), arrowEdge: .top) {
            Text(formatCurrencyShort(value))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Option 2: Compact Pill Pipeline
struct CompactPillPipeline: View {
    let requests: [InvestmentRequest]
    let selectedTheater: String
    let selectedIndustries: Set<String>
    let navigationState: NavigationState
    
    private var fiscalYears: [String] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let currentFY = month >= 2 ? year + 1 : year
        return ["FY\(currentFY - 1)", "FY\(currentFY)"]
    }
    
    private func stagesForYear(_ year: String) -> [(String, Int, Double, Color, String)] {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        return [
            ("Draft", yearRequests.filter { $0.status == "DRAFT" }.count, yearRequests.filter { $0.status == "DRAFT" }.compactMap { $0.requestedAmount }.reduce(0, +), .gray, "DRAFT"),
            ("Submit", yearRequests.filter { $0.status == "SUBMITTED" }.count, yearRequests.filter { $0.status == "SUBMITTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .orange, "SUBMITTED"),
            ("DM", yearRequests.filter { $0.status == "DM_APPROVED" }.count, yearRequests.filter { $0.status == "DM_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "DM_APPROVED"),
            ("RD", yearRequests.filter { $0.status == "RD_APPROVED" }.count, yearRequests.filter { $0.status == "RD_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "RD_APPROVED"),
            ("AVP", yearRequests.filter { $0.status == "AVP_APPROVED" }.count, yearRequests.filter { $0.status == "AVP_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "AVP_APPROVED"),
            ("Reject", yearRequests.filter { $0.status == "REJECTED" }.count, yearRequests.filter { $0.status == "REJECTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .red, "REJECTED"),
            ("Approv", yearRequests.filter { $0.status == "FINAL_APPROVED" }.count, yearRequests.filter { $0.status == "FINAL_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .green, "FINAL_APPROVED")
        ]
    }
    
    private func yearSummary(_ year: String) -> (count: Int, amount: Double) {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        let count = yearRequests.count
        let amount = yearRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        return (count, amount)
    }
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fiscalYears, id: \.self) { year in
                let summary = yearSummary(year)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(year): \(summary.count) requests • \(formatCurrencyShort(summary.amount))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        ForEach(Array(stagesForYear(year).enumerated()), id: \.offset) { index, stage in
                            PillButton(name: stage.0, count: stage.1, value: stage.2, color: stage.3) {
                                navigationState.passedStatus = stage.4
                                navigationState.passedQuarters = [year]
                                navigationState.passedTheater = selectedTheater
                                navigationState.passedIndustries = selectedIndustries
                                navigationState.selectedTab = 1
                                navigationState.triggerNavigation()
                            }
                            
                            if index < 6 {
                                Text("›")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PillButton: View {
    let name: String
    let count: Int
    let value: Double
    let color: Color
    let onTap: () -> Void
    @State private var isHovering = false
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        Text("\(name):\(count)")
            .font(.system(size: 10))
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(isHovering ? 0.3 : 0.15)))
            .overlay(Capsule().stroke(color, lineWidth: 1))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture { onTap() }
            .popover(isPresented: .constant(isHovering), arrowEdge: .top) {
                Text(formatCurrencyShort(value))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
    }
}

// MARK: - Option 3: Stepper Pipeline
struct StepperPipeline: View {
    let requests: [InvestmentRequest]
    let selectedTheater: String
    let selectedIndustries: Set<String>
    let navigationState: NavigationState
    
    private var fiscalYears: [String] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let currentFY = month >= 2 ? year + 1 : year
        return ["FY\(currentFY - 1)", "FY\(currentFY)"]
    }
    
    private func stagesForYear(_ year: String) -> [(String, Int, Double, Color, String)] {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        return [
            ("Draft", yearRequests.filter { $0.status == "DRAFT" }.count, yearRequests.filter { $0.status == "DRAFT" }.compactMap { $0.requestedAmount }.reduce(0, +), .gray, "DRAFT"),
            ("Submit", yearRequests.filter { $0.status == "SUBMITTED" }.count, yearRequests.filter { $0.status == "SUBMITTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .orange, "SUBMITTED"),
            ("DM", yearRequests.filter { $0.status == "DM_APPROVED" }.count, yearRequests.filter { $0.status == "DM_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "DM_APPROVED"),
            ("RD", yearRequests.filter { $0.status == "RD_APPROVED" }.count, yearRequests.filter { $0.status == "RD_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "RD_APPROVED"),
            ("AVP", yearRequests.filter { $0.status == "AVP_APPROVED" }.count, yearRequests.filter { $0.status == "AVP_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "AVP_APPROVED"),
            ("Reject", yearRequests.filter { $0.status == "REJECTED" }.count, yearRequests.filter { $0.status == "REJECTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .red, "REJECTED"),
            ("Approv", yearRequests.filter { $0.status == "FINAL_APPROVED" }.count, yearRequests.filter { $0.status == "FINAL_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .green, "FINAL_APPROVED")
        ]
    }
    
    private func yearSummary(_ year: String) -> (count: Int, amount: Double) {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        let count = yearRequests.count
        let amount = yearRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        return (count, amount)
    }
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(fiscalYears, id: \.self) { year in
                let summary = yearSummary(year)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(year): \(summary.count) requests • \(formatCurrencyShort(summary.amount))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 0) {
                        ForEach(Array(stagesForYear(year).enumerated()), id: \.offset) { index, stage in
                            StepperNode(name: stage.0, count: stage.1, value: stage.2, color: stage.3, isLast: index == 6) {
                                navigationState.passedStatus = stage.4
                                navigationState.passedQuarters = [year]
                                navigationState.passedTheater = selectedTheater
                                navigationState.passedIndustries = selectedIndustries
                                navigationState.selectedTab = 1
                                navigationState.triggerNavigation()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct StepperNode: View {
    let name: String
    let count: Int
    let value: Double
    let color: Color
    let isLast: Bool
    let onTap: () -> Void
    @State private var isHovering = false
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.bold)
                
                Circle()
                    .fill(color.opacity(isHovering ? 1.0 : 0.7))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(color, lineWidth: 2))
                
                Text(name)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture { onTap() }
            .popover(isPresented: .constant(isHovering), arrowEdge: .top) {
                Text(formatCurrencyShort(value))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            
            if !isLast {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)
                    .frame(maxWidth: 30)
                    .offset(y: 2)
            }
        }
    }
}

// MARK: - Option 4: Two-Row Arrows Pipeline
struct TwoRowArrowsPipeline: View {
    let requests: [InvestmentRequest]
    let selectedTheater: String
    let selectedIndustries: Set<String>
    let navigationState: NavigationState
    
    private var fiscalYears: [String] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let currentFY = month >= 2 ? year + 1 : year
        return ["FY\(currentFY - 1)", "FY\(currentFY)"]
    }
    
    private func stagesForYear(_ year: String) -> [(String, Int, Double, Color, String)] {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        return [
            ("Draft", yearRequests.filter { $0.status == "DRAFT" }.count, yearRequests.filter { $0.status == "DRAFT" }.compactMap { $0.requestedAmount }.reduce(0, +), .gray, "DRAFT"),
            ("Submitted", yearRequests.filter { $0.status == "SUBMITTED" }.count, yearRequests.filter { $0.status == "SUBMITTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .orange, "SUBMITTED"),
            ("DM Review", yearRequests.filter { $0.status == "DM_APPROVED" }.count, yearRequests.filter { $0.status == "DM_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "DM_APPROVED"),
            ("RD Review", yearRequests.filter { $0.status == "RD_APPROVED" }.count, yearRequests.filter { $0.status == "RD_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "RD_APPROVED"),
            ("AVP Review", yearRequests.filter { $0.status == "AVP_APPROVED" }.count, yearRequests.filter { $0.status == "AVP_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .blue, "AVP_APPROVED"),
            ("Rejected", yearRequests.filter { $0.status == "REJECTED" }.count, yearRequests.filter { $0.status == "REJECTED" }.compactMap { $0.requestedAmount }.reduce(0, +), .red, "REJECTED"),
            ("Approved", yearRequests.filter { $0.status == "FINAL_APPROVED" }.count, yearRequests.filter { $0.status == "FINAL_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +), .green, "FINAL_APPROVED")
        ]
    }
    
    private var maxCount: Int {
        fiscalYears.flatMap { stagesForYear($0).map { $0.1 } }.max() ?? 1
    }
    
    private func yearSummary(_ year: String) -> (count: Int, amount: Double) {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        let count = yearRequests.count
        let amount = yearRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        return (count, amount)
    }
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fiscalYears, id: \.self) { year in
                let summary = yearSummary(year)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(year): \(summary.count) requests • \(formatCurrencyShort(summary.amount))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        ForEach(Array(stagesForYear(year).enumerated()), id: \.offset) { index, stage in
                            ArrowBox(name: stage.0, count: stage.1, value: stage.2, maxCount: maxCount, color: stage.3) {
                                navigationState.passedStatus = stage.4
                                navigationState.passedQuarters = [year]
                                navigationState.passedTheater = selectedTheater
                                navigationState.passedIndustries = selectedIndustries
                                navigationState.selectedTab = 1
                                navigationState.triggerNavigation()
                            }
                            
                            if index < 6 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ArrowBox: View {
    let name: String
    let count: Int
    let value: Double
    let maxCount: Int
    let color: Color
    let onTap: () -> Void
    @State private var isHovering = false
    
    private func formatCurrencyShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "$%.0fK", amount / 1_000)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
            
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(color)
                        .frame(width: min(geometry.size.width * 0.7, 40), height: CGFloat(count) / CGFloat(max(maxCount, 1)) * 35)
                        .frame(minHeight: count > 0 ? 4 : 0)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: min(geometry.size.width * 0.7, 40), height: 1)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 40)
            
            Text(name)
                .font(.system(size: 8))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(isHovering ? Color(NSColor.controlBackgroundColor).opacity(0.7) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isHovering ? Color.blue : Color.secondary.opacity(0.2), lineWidth: 1))
        .cornerRadius(3)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture { onTap() }
        .popover(isPresented: .constant(isHovering), arrowEdge: .top) {
            Text(formatCurrencyShort(value))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }
}
