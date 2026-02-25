import SwiftUI

enum SortColumn: String {
    case company, request, theater, industry, quarter, amount, status
}

struct InvestmentRequestsView: View {
    @ObservedObject var navigationState: NavigationState
    @ObservedObject var userSettings = UserSettings.shared
    @EnvironmentObject var dataService: DataService
    
    @State private var searchText = ""
    @State private var selectedTheater: String = "All"
    @State private var selectedIndustries: Set<String> = []
    @State private var selectedQuarters: Set<String> = []
    @State private var selectedStatus: String = "All"
    @State private var showingNewRequest = false
    @State private var showQuarterPicker = false
    @State private var showIndustryPicker = false
    @State private var sortColumn: SortColumn = .company
    @State private var sortAscending: Bool = true
    @State private var filterPendingMyApproval: Bool = false
    @State private var filterMyRequests: Bool = false
    @State private var hasInitialized = false
    
    private var hasActiveFilters: Bool {
        selectedTheater != "All" || !selectedIndustries.isEmpty || !selectedQuarters.isEmpty || selectedStatus != "All" || !searchText.isEmpty || filterPendingMyApproval || filterMyRequests
    }
    
    private func clearAllFilters() {
        selectedTheater = "All"
        selectedIndustries = []
        selectedQuarters = []
        selectedStatus = "All"
        searchText = ""
        filterPendingMyApproval = false
        filterMyRequests = false
    }
    
    private var currentFiscalQuarter: String {
        let (fy, q) = currentFiscalYearAndQuarter
        return "FY\(fy)-Q\(q)"
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
    
    private var theaters: [String] {
        ["All"] + dataService.sfdcTheaters
    }
    
    private var availableIndustries: [String] {
        if selectedTheater == "All" {
            return dataService.sfdcIndustries
        }
        return dataService.sfdcIndustriesByTheater[selectedTheater] ?? []
    }
    private let statuses = ["All", "DRAFT", "SUBMITTED", "IN_REVIEW", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED", "FINAL_APPROVED", "REJECTED"]
    
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
        let filtered = dataService.investmentRequests.filter { request in
            let matchesSearch = searchText.isEmpty ||
                request.requestTitle.localizedCaseInsensitiveContains(searchText) ||
                (request.accountName?.localizedCaseInsensitiveContains(searchText) ?? false)
            
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
            let matchesStatus: Bool
            if selectedStatus == "All" {
                matchesStatus = true
            } else if selectedStatus == "IN_REVIEW" {
                matchesStatus = ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains(request.status)
            } else {
                matchesStatus = request.status == selectedStatus
            }
            
            let matchesPersonalFilters: Bool
            if filterPendingMyApproval || filterMyRequests {
                let currentUserName = dataService.currentUser?.displayName
                let currentUsername = dataService.currentUser?.snowflakeUsername
                let currentEmployeeId = dataService.currentUser?.employeeId
                let isPending = ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains(request.status)
                let isMyApproval = isPending && request.nextApproverName == currentUserName
                let isCreator = request.createdByName == currentUserName ||
                    request.createdBy == currentUsername ||
                    (currentEmployeeId != nil && (request.createdByEmployeeId == currentEmployeeId || request.onBehalfOfEmployeeId == currentEmployeeId))

                if filterPendingMyApproval && filterMyRequests {
                    matchesPersonalFilters = isCreator || isMyApproval
                } else if filterPendingMyApproval {
                    matchesPersonalFilters = isMyApproval
                } else {
                    matchesPersonalFilters = isCreator
                }
            } else {
                matchesPersonalFilters = true
            }
            
            return matchesSearch && matchesTheater && matchesIndustry && matchesQuarter && matchesStatus && matchesPersonalFilters
        }
        
        return filtered.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .company:
                result = (a.accountName ?? "") < (b.accountName ?? "")
            case .request:
                result = a.requestTitle < b.requestTitle
            case .theater:
                result = (a.theater ?? "") < (b.theater ?? "")
            case .industry:
                result = (a.industrySegment ?? "") < (b.industrySegment ?? "")
            case .quarter:
                result = (a.investmentQuarter ?? "") < (b.investmentQuarter ?? "")
            case .amount:
                result = (a.requestedAmount ?? 0) < (b.requestedAmount ?? 0)
            case .status:
                result = a.status < b.status
            }
            return sortAscending ? result : !result
        }
    }
    
    private func toggleSort(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Investment Requests")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showingNewRequest = true }) {
                    Label("New Request", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            HStack(spacing: 12) {
                Picker("Theater", selection: $selectedTheater) {
                    ForEach(theaters, id: \.self) { Text($0) }
                }
                .frame(width: 150)
                
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
                    ForEach(statuses, id: \.self) { theater in
                        Text(statusDisplayName(theater)).tag(theater)
                    }
                }
                .frame(width: 130)
                
                Toggle(isOn: $filterPendingMyApproval) {
                    Text("Pending My Approval")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                
                if filterMyRequests {
                    Button(action: { filterMyRequests = false }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                            Text("My Requests")
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.purple, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: clearAllFilters) {
                    Text("Clear")
                }
                .disabled(!hasActiveFilters)
                
                Spacer()
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search requests...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)
                .frame(width: 200)
                
                VStack(spacing: 2) {
                    HStack {
                        Text("Requests:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(filteredRequests.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Value:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatCurrency(filteredRequests.compactMap { $0.requestedAmount }.reduce(0, +)))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 160)
            }
            .padding(.horizontal)
            .padding(.bottom)
            
            Divider()
            
            if filteredRequests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No requests found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        SortableColumnHeader(title: "Company", column: .company, currentColumn: sortColumn, ascending: sortAscending, action: { toggleSort(.company) })
                            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                        
                        SortableColumnHeader(title: "Investment Request", column: .request, currentColumn: sortColumn, ascending: sortAscending, action: { toggleSort(.request) })
                            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                        
                        SortableColumnHeader(title: "Theater", column: .theater, currentColumn: sortColumn, ascending: sortAscending, action: { toggleSort(.theater) })
                            .frame(width: 80, alignment: .leading)
                        
                        SortableColumnHeader(title: "Industry", column: .industry, currentColumn: sortColumn, ascending: sortAscending, action: { toggleSort(.industry) })
                            .frame(width: 80, alignment: .leading)
                        
                        SortableColumnHeader(title: "Quarter", column: .quarter, currentColumn: sortColumn, ascending: sortAscending, action: { toggleSort(.quarter) })
                            .frame(width: 90, alignment: .leading)
                        
                        SortableColumnHeader(title: "Amount", column: .amount, currentColumn: sortColumn, ascending: sortAscending, action: { toggleSort(.amount) })
                            .frame(width: 90, alignment: .trailing)
                        
                        SortableColumnHeader(title: "Status", column: .status, currentColumn: sortColumn, ascending: sortAscending, action: { toggleSort(.status) })
                            .frame(width: 100, alignment: .center)
                        
                        Text("Next Approver")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        
                        Text("Actions")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    List {
                        ForEach(filteredRequests) { request in
                            RequestTableRow(request: request, navigationState: navigationState)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingNewRequest) {
            RequestFormView(isPresented: $showingNewRequest)
        }
        .onChange(of: navigationState.showingNewRequest) { _, newValue in
            if newValue {
                showingNewRequest = true
                navigationState.showingNewRequest = false
            }
        }
        .onAppear {
            applyPassedFiltersOrInitialize()
        }
        .onChange(of: navigationState.selectedTab) { oldValue, newValue in
            if newValue == 1 {
                applyPassedFiltersOrInitialize()
            }
        }
        .onChange(of: navigationState.navigationTrigger) { _, _ in
            applyPassedFiltersOrInitialize()
        }
        .onChange(of: selectedTheater) { _, newTheater in
            if newTheater == "All" {
                selectedIndustries.removeAll()
            } else if availableIndustries.isEmpty {
                selectedIndustries.removeAll()
            } else {
                selectedIndustries = selectedIndustries.filter { availableIndustries.contains($0) }
            }
        }
        .onChange(of: filterPendingMyApproval) { _, isOn in
            if isOn {
                selectedQuarters = []
                selectedTheater = "All"
                selectedIndustries = []
                selectedStatus = "All"
            }
        }
    }
        
    private func applyPassedFiltersOrInitialize() {
        let hasPassedStatus = !navigationState.passedStatus.isEmpty
        let hasPassedQuarters = !navigationState.passedQuarters.isEmpty
        let hasPassedPending = navigationState.filterPendingMyApproval
        let hasPassedMyRequests = navigationState.filterMyRequests
        let hasPassedTheater = !navigationState.passedTheater.isEmpty
        let hasPassedIndustries = !navigationState.passedIndustries.isEmpty
        
        if hasPassedStatus || hasPassedQuarters || hasPassedPending || hasPassedMyRequests || hasPassedTheater || hasPassedIndustries {
            filterPendingMyApproval = hasPassedPending
            filterMyRequests = hasPassedMyRequests
            selectedTheater = hasPassedTheater ? navigationState.passedTheater : "All"
            selectedIndustries = navigationState.passedIndustries
            selectedQuarters = navigationState.passedQuarters
            selectedStatus = hasPassedStatus ? navigationState.passedStatus : "All"
            searchText = ""
            
            navigationState.filterPendingMyApproval = false
            navigationState.filterMyRequests = false
            navigationState.passedStatus = ""
            navigationState.passedQuarters = []
            navigationState.passedTheater = ""
            navigationState.passedIndustries = []
        } else if !hasInitialized {
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
    }
        
    private func statusDisplayName(_ status: String) -> String {
        switch status {
        case "All": return "All"
        case "DRAFT": return "Draft"
        case "SUBMITTED": return "Submitted"
        case "IN_REVIEW": return "Pending Approval"
        case "DM_APPROVED": return "DM Approved"
        case "RD_APPROVED": return "RD Approved"
        case "AVP_APPROVED": return "AVP Approved"
        case "FINAL_APPROVED": return "Approved"
        case "REJECTED": return "Rejected"
        default: return status
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

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
struct RequestTableRow: View {
    let request: InvestmentRequest
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    @State private var showingDetail = false
    @State private var showingWithdrawConfirm = false
    @State private var showingApprovalSheet = false
    @State private var showingReviseSheet = false
    @State private var isProcessing = false
    
    private var isNextApprover: Bool {
        guard let currentUser = dataService.currentUser else { return false }
        return request.nextApproverName == currentUser.displayName
    }
    
    private var isOwner: Bool {
        request.createdByName == dataService.currentUser?.displayName
    }
    
    private var industryShortName: String {
        guard let industry = request.industrySegment else { return "—" }
        switch industry {
        case "Financial Services": return "FSI"
        case "Healthcare & Life Sciences": return "HCLS"
        case "Manufacturing": return "MFG"
        case "Communications, Media & Entertainment": return "CME"
        case "Retail & Consumer Goods": return "RCG"
        case "FSI Globals": return "FSI Globals"
        default: return industry
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(request.accountName ?? "—")
                .font(.subheadline)
                .lineLimit(1)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            
            Text(request.requestTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            
            Text(request.theater ?? "—")
                .font(.caption)
                .frame(width: 80, alignment: .leading)
            
            Text(industryShortName)
                .font(.caption)
                .frame(width: 80, alignment: .leading)
            
            Text(request.investmentQuarter ?? "—")
                .font(.caption)
                .frame(width: 90, alignment: .leading)
            
            Text(request.formattedAmount)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 90, alignment: .trailing)
            
            StatusBadge(status: request.status)
                .frame(width: 100, alignment: .center)
            
            Text(request.nextApproverName ?? "—")
                .font(.caption)
                .lineLimit(1)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 6) {
                if request.isEditable {
                    // DRAFT: Edit button
                    Button("Edit") {
                        showingDetail = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green, lineWidth: 1)
                    )
                } else if request.isFinalApproved || request.isDenied {
                    // FINAL_APPROVED or DENIED: View button (read-only)
                    Button("View") {
                        showingDetail = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                } else if request.isRejected {
                    // REJECTED: Revise button
                    Button("Revise") {
                        showingReviseSheet = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.orange, lineWidth: 1)
                    )
                } else if request.isSubmitted {
                    // SUBMITTED: Review for approver, View for others
                    if isNextApprover {
                        Button("Review") {
                            showingApprovalSheet = true
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green, lineWidth: 1)
                        )
                    } else {
                        Button("View") {
                            showingDetail = true
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                    }
                } else {
                    // Default: View button
                    Button("View") {
                        showingDetail = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                }
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            if request.isEditable {
                RequestFormView(existingRequest: request, isPresented: $showingDetail)
            } else {
                RequestDetailView(request: request, isPresented: $showingDetail, mode: .view)
            }
        }
        .sheet(isPresented: $showingApprovalSheet) {
            ApprovalDetailSheet(request: request, isPresented: $showingApprovalSheet)
        }
        .sheet(isPresented: $showingReviseSheet) {
            RequestDetailView(request: request, isPresented: $showingReviseSheet, mode: .revise)
        }
        .alert("Withdraw Request", isPresented: $showingWithdrawConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Withdraw") {
                dataService.withdrawRequest(requestId: request.requestId) { _, _ in }
            }
        } message: {
            Text("Withdraw this request back to Draft status?")
        }
    }
}

class RichTextState: ObservableObject {
    weak var coordinator: RichTextEditor.Coordinator?
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    @Binding var isFocused: Bool
    var state: RichTextState?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        context.coordinator.textView = textView
        state?.coordinator = context.coordinator

        if !text.isEmpty {
            textView.string = text
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text && !context.coordinator.isEditing {
            textView.string = text
        }
        state?.coordinator = context.coordinator
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = tv.string
            isEditing = false
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.window?.selectNextKeyView(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                textView.window?.selectPreviousKeyView(nil)
                return true
            }
            return false
        }

        func toggleBold() {
            guard let tv = textView else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let storage = tv.textStorage!
            var hasBold = false
            storage.enumerateAttribute(.font, in: range) { value, _, _ in
                if let font = value as? NSFont {
                    hasBold = hasBold || font.fontDescriptor.symbolicTraits.contains(.bold)
                }
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newFont: NSFont
                    if hasBold {
                        newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                    } else {
                        newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    }
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            storage.endEditing()
            parent.text = tv.string
        }

        func toggleItalic() {
            guard let tv = textView else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let storage = tv.textStorage!
            var hasItalic = false
            storage.enumerateAttribute(.font, in: range) { value, _, _ in
                if let font = value as? NSFont {
                    hasItalic = hasItalic || font.fontDescriptor.symbolicTraits.contains(.italic)
                }
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newFont: NSFont
                    if hasItalic {
                        newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                    } else {
                        newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    }
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            storage.endEditing()
            parent.text = tv.string
        }

        func toggleUnderline() {
            guard let tv = textView else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let storage = tv.textStorage!
            var hasUnderline = false
            storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
                if let style = value as? Int, style != 0 { hasUnderline = true }
            }
            storage.beginEditing()
            if hasUnderline {
                storage.removeAttribute(.underlineStyle, range: range)
            } else {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            storage.endEditing()
            parent.text = tv.string
        }

        func insertBullet() {
            guard let tv = textView else { return }
            let range = tv.selectedRange()
            let text = tv.string as NSString
            let lineRange = text.lineRange(for: range)
            let lineText = text.substring(with: lineRange)

            tv.textStorage?.beginEditing()
            if lineText.hasPrefix("• ") {
                tv.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 2), with: "")
            } else {
                tv.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "• ")
            }
            tv.textStorage?.endEditing()
            parent.text = tv.string
        }
    }
}

struct FormattingToolbar: View {
    @ObservedObject var state: RichTextState

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { state.coordinator?.toggleBold() }) {
                Image(systemName: "bold")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Bold")

            Button(action: { state.coordinator?.toggleItalic() }) {
                Image(systemName: "italic")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Italic")

            Button(action: { state.coordinator?.toggleUnderline() }) {
                Image(systemName: "underline")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Underline")

            Button(action: { state.coordinator?.insertBullet() }) {
                Image(systemName: "list.bullet")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Bullet List")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}

struct RequestFormView: View {
    var existingRequest: InvestmentRequest?
    @Binding var isPresented: Bool
    @EnvironmentObject var dataService: DataService

    @State private var title = ""
    @State private var selectedAccount: SFDCAccount?
    @State private var accountSearchText = ""
    @State private var searchResults: [SFDCAccount] = []
    @State private var totalMatchCount: Int = 0
    @State private var isSearching = false
    @State private var investmentType = ""
    @State private var amount = ""
    @State private var amountEditing = false
    @State private var quarter = ""
    @State private var theater = "US Majors"
    @State private var industrySegment = ""
    @State private var salesforceURL = ""
    @State private var expectedROI = "10x"
    @State private var justification = ""
    @State private var expectedOutcome = ""
    @State private var riskAssessment = ""
    @State private var isSaving = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var comment = ""

    @State private var justificationFocused = false
    @State private var outcomeFocused = false
    @State private var riskFocused = false

    @StateObject private var justificationState = RichTextState()
    @StateObject private var outcomeState = RichTextState()
    @StateObject private var riskState = RichTextState()

    private var isEditMode: Bool { existingRequest != nil }

    private var defaultQuarter: String {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        let (fy, q): (Int, Int)
        switch month {
        case 2, 3, 4: (fy, q) = (year + 1, 1)
        case 5, 6, 7: (fy, q) = (year + 1, 2)
        case 8, 9, 10: (fy, q) = (year + 1, 3)
        case 11, 12: (fy, q) = (year + 2, 4)
        case 1: (fy, q) = (year + 1, 4)
        default: (fy, q) = (year + 1, 1)
        }
        return "FY\(fy)-Q\(q)"
    }

    private let investmentTypes = ["Professional Services", "Customer Success", "Training", "Support", "Partnership", "Other"]
    private let roiOptions = ["5x", "6x", "7x", "8x", "9x", "10x", "11x", "12x", "13x", "14x", "15x", "16x", "17x", "18x", "19x", "20x", "> 20x"]

    private var availableIndustries: [String] {
        dataService.sfdcIndustriesByTheater[theater] ?? dataService.sfdcIndustries
    }

    private var availableQuarters: [String] {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        let (currentFY, currentQ): (Int, Int)
        switch month {
        case 2, 3, 4: (currentFY, currentQ) = (year + 1, 1)
        case 5, 6, 7: (currentFY, currentQ) = (year + 1, 2)
        case 8, 9, 10: (currentFY, currentQ) = (year + 1, 3)
        case 11, 12: (currentFY, currentQ) = (year + 2, 4)
        case 1: (currentFY, currentQ) = (year + 1, 4)
        default: (currentFY, currentQ) = (year + 1, 1)
        }

        let previousFY = currentFY - 1
        var quarters = (1...4).map { "FY\(previousFY)-Q\($0)" } + (1...4).map { "FY\(currentFY)-Q\($0)" }

        if currentQ == 4 {
            let nextFY = currentFY + 1
            quarters += ["FY\(nextFY)-Q1", "FY\(nextFY)-Q2"]
        }

        return quarters
    }

    private func formatAmountDisplay(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0 else { return raw }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? raw
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditMode ? "Edit Investment Request" : "New Investment Request")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                if let req = existingRequest {
                    StatusBadge(status: req.status)
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Request Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledField(label: "Title") {
                                TextField("Enter request title", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }

                            LabeledField(label: "Account") {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let account = selectedAccount {
                                        HStack {
                                            Text(account.accountName)
                                                .padding(8)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(4)

                                            Button(action: { selectedAccount = nil }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    } else {
                                        TextField("Search or type account name...", text: $accountSearchText)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: accountSearchText) { _, newValue in
                                                searchAccounts(query: newValue)
                                            }

                                        if !searchResults.isEmpty {
                                            ScrollView {
                                                VStack(alignment: .leading, spacing: 0) {
                                                    ForEach(searchResults.prefix(20)) { account in
                                                        Button(action: {
                                                            selectedAccount = account
                                                            accountSearchText = ""
                                                            searchResults = []
                                                            if let acctTheater = account.theater {
                                                                theater = acctTheater
                                                            }
                                                            if let segment = account.industrySegment {
                                                                industrySegment = segment
                                                            }
                                                        }) {
                                                            HStack {
                                                                Text(account.accountName)
                                                                Spacer()
                                                                if let seg = account.industrySegment {
                                                                    Text(seg)
                                                                        .font(.caption2)
                                                                        .foregroundColor(.secondary)
                                                                }
                                                                if let t = account.theater {
                                                                    Text(t)
                                                                        .font(.caption)
                                                                        .foregroundColor(.secondary)
                                                                }
                                                            }
                                                            .padding(8)
                                                            .contentShape(Rectangle())
                                                        }
                                                        .buttonStyle(.plain)

                                                        if account.id != searchResults.prefix(20).last?.id {
                                                            Divider()
                                                        }
                                                    }
                                                    if totalMatchCount > searchResults.prefix(20).count {
                                                        Divider()
                                                        Text("\(totalMatchCount - searchResults.prefix(20).count) more matches — refine your search")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                            .italic()
                                                            .padding(8)
                                                            .frame(maxWidth: .infinity, alignment: .center)
                                                    }
                                                }
                                            }
                                            .frame(maxHeight: 300)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(4)
                                            .shadow(radius: 2)
                                        } else if accountSearchText.count >= 2 && !isSearching {
                                            Button(action: {
                                                selectedAccount = SFDCAccount(accountId: "", accountName: accountSearchText.trimmingCharacters(in: .whitespaces), theater: nil, industrySegment: nil)
                                                accountSearchText = ""
                                            }) {
                                                HStack {
                                                    Image(systemName: "plus.circle")
                                                    Text("Use \"\(accountSearchText)\" as account name")
                                                        .foregroundColor(.primary)
                                                }
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(4)
                                            .shadow(radius: 2)
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 16) {
                                LabeledField(label: "Investment Type") {
                                    Picker("", selection: $investmentType) {
                                        Text("Select...").tag("")
                                        ForEach(investmentTypes, id: \.self) { Text($0) }
                                    }
                                    .labelsHidden()
                                }

                                LabeledField(label: "Amount Requested") {
                                    TextField("$0", text: $amount, onEditingChanged: { editing in
                                        amountEditing = editing
                                        if !editing {
                                            amount = formatAmountDisplay(amount)
                                        }
                                    })
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                }

                                LabeledField(label: "Expected ROI") {
                                    Picker("", selection: $expectedROI) {
                                        ForEach(roiOptions, id: \.self) { Text($0) }
                                    }
                                    .labelsHidden()
                                    .frame(width: 80)
                                }
                            }

                            HStack(spacing: 16) {
                                LabeledField(label: "Quarter") {
                                    Picker("", selection: $quarter) {
                                        ForEach(availableQuarters, id: \.self) { Text($0) }
                                    }
                                    .labelsHidden()
                                }

                                LabeledField(label: "Theater") {
                                    Picker("", selection: $theater) {
                                        Text("Select...").tag("")
                                        ForEach(dataService.sfdcTheaters, id: \.self) { Text($0) }
                                    }
                                    .labelsHidden()
                                }

                                LabeledField(label: "Industry Segment") {
                                    Picker("", selection: $industrySegment) {
                                        Text("Select...").tag("")
                                        ForEach(availableIndustries, id: \.self) { Text($0) }
                                    }
                                    .labelsHidden()
                                }
                            }

                            LabeledField(label: "Salesforce Record URL") {
                                TextField("https://snowflake.my.salesforce.com/...", text: $salesforceURL)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding()
                    }

                    GroupBox("Business Case") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Business Justification")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if justificationFocused {
                                        FormattingToolbar(state: justificationState)
                                    }
                                }
                                RichTextEditor(text: $justification, placeholder: "Enter justification...", isFocused: $justificationFocused, state: justificationState)
                                    .frame(height: 80)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Expected Outcome")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if outcomeFocused {
                                        FormattingToolbar(state: outcomeState)
                                    }
                                }
                                RichTextEditor(text: $expectedOutcome, placeholder: "Enter expected outcome...", isFocused: $outcomeFocused, state: outcomeState)
                                    .frame(height: 80)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Risk Assessment")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if riskFocused {
                                        FormattingToolbar(state: riskState)
                                    }
                                }
                                RichTextEditor(text: $riskAssessment, placeholder: "Enter risk assessment...", isFocused: $riskFocused, state: riskState)
                                    .frame(height: 80)
                            }
                        }
                        .padding()
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comment (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Add a comment...", text: $comment)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Save as Draft") {
                    saveRequest(submit: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundColor(.black)
                .disabled(title.isEmpty || isSaving || isSubmitting)

                Button("Submit") {
                    saveRequest(submit: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || isSaving || isSubmitting)
            }
            .padding()
        }
        .frame(width: 750, height: 780)
        .onAppear {
            if let req = existingRequest {
                title = req.requestTitle
                if let name = req.accountName {
                    selectedAccount = SFDCAccount(accountId: req.accountId ?? "", accountName: name, theater: req.theater, industrySegment: req.industrySegment)
                }
                investmentType = req.investmentType ?? ""
                if let amt = req.requestedAmount {
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .currency
                    formatter.currencySymbol = "$"
                    formatter.maximumFractionDigits = 0
                    amount = formatter.string(from: NSNumber(value: amt)) ?? "\(amt)"
                }
                quarter = req.investmentQuarter ?? ""
                theater = req.theater ?? "US Majors"
                industrySegment = req.industrySegment ?? ""
                salesforceURL = req.sfdcOpportunityLink ?? ""
                expectedROI = req.expectedRoi ?? "10x"
                justification = req.businessJustification ?? ""
                expectedOutcome = req.expectedOutcome ?? ""
                riskAssessment = req.riskAssessment ?? ""
            } else {
                if quarter.isEmpty {
                    quarter = defaultQuarter
                }
            }
        }
        .onChange(of: theater) { _, _ in
            if !availableIndustries.contains(industrySegment) {
                industrySegment = ""
            }
        }
    }

    private func searchAccounts(query: String) {
        guard query.count >= 2 else {
            searchResults = []
            totalMatchCount = 0
            return
        }

        isSearching = true
        dataService.searchAccounts(query: query) { accounts, total in
            isSearching = false
            searchResults = accounts
            totalMatchCount = total
        }
    }

    private func saveRequest(submit: Bool) {
        if submit {
            isSubmitting = true
        } else {
            isSaving = true
        }
        errorMessage = nil

        let amountValue = Double(amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))

        if let req = existingRequest {
            dataService.updateRequest(
                requestId: req.requestId,
                title: title,
                accountId: selectedAccount?.accountId,
                accountName: selectedAccount?.accountName,
                investmentType: investmentType.isEmpty ? nil : investmentType,
                amount: amountValue,
                quarter: quarter,
                justification: justification.isEmpty ? nil : justification,
                expectedOutcome: expectedOutcome.isEmpty ? nil : expectedOutcome,
                riskAssessment: riskAssessment.isEmpty ? nil : riskAssessment,
                theater: theater,
                industrySegment: industrySegment.isEmpty ? nil : industrySegment,
                salesforceURL: salesforceURL.isEmpty ? nil : salesforceURL,
                expectedROI: expectedROI.isEmpty ? nil : expectedROI,
                draftComment: (!submit && !comment.isEmpty) ? comment : nil,
                autoSubmit: submit,
                submitComment: submit ? (comment.isEmpty ? nil : comment) : nil
            ) { success in
                isSaving = false
                isSubmitting = false
                if success {
                    isPresented = false
                } else {
                    errorMessage = submit ? "Failed to update and submit request." : "Failed to update request. Please try again."
                }
            }
        } else {
            dataService.createRequest(
                title: title,
                accountId: selectedAccount?.accountId,
                accountName: selectedAccount?.accountName,
                investmentType: investmentType.isEmpty ? nil : investmentType,
                amount: amountValue,
                quarter: quarter,
                justification: justification.isEmpty ? nil : justification,
                expectedOutcome: expectedOutcome.isEmpty ? nil : expectedOutcome,
                riskAssessment: riskAssessment.isEmpty ? nil : riskAssessment,
                theater: theater,
                industrySegment: industrySegment.isEmpty ? nil : industrySegment,
                salesforceURL: salesforceURL.isEmpty ? nil : salesforceURL,
                expectedROI: expectedROI.isEmpty ? nil : expectedROI,
                autoSubmit: submit,
                submitComment: submit ? (comment.isEmpty ? nil : comment) : nil
            ) { success, requestId in
                isSaving = false
                isSubmitting = false
                if success {
                    isPresented = false
                } else {
                    errorMessage = submit ? "Failed to create and submit request." : "Failed to create request. Please try again."
                }
            }
        }
    }
}

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
    }
}

enum RequestDetailMode {
    case view
    case revise
}

struct RequestDetailView: View {
    let request: InvestmentRequest
    @Binding var isPresented: Bool
    var mode: RequestDetailMode = .view
    @EnvironmentObject var dataService: DataService
    @State private var showingWithdrawSheet = false
    @State private var withdrawComment = ""
    @State private var linkedOpportunities: [SFDCOpportunity] = []
    @State private var isSaving = false
    @State private var comment = ""
    @State private var errorMessage: String?

    @State private var editedJustification: String = ""
    @State private var editedOutcome: String = ""
    @State private var editedRisk: String = ""

    private var canWithdraw: Bool {
        request.canWithdraw && mode == .view
    }

    private var formattedCreatedAt: String {
        guard let date = request.createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.requestTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                if mode == .revise {
                    Text("(Revising)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer()

                StatusBadge(status: request.status)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Request Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledField(label: "Title") {
                                Text(request.requestTitle)
                            }
                            LabeledField(label: "Account") {
                                Text(request.accountName ?? "—")
                            }
                            HStack(spacing: 16) {
                                LabeledField(label: "Investment Type") {
                                    Text(request.investmentType ?? "—")
                                }
                                LabeledField(label: "Amount Requested") {
                                    Text(request.formattedAmount)
                                }
                                LabeledField(label: "Expected ROI") {
                                    Text(request.expectedRoi ?? "—")
                                }
                            }
                            HStack(spacing: 16) {
                                LabeledField(label: "Quarter") {
                                    Text(request.investmentQuarter ?? "—")
                                }
                                LabeledField(label: "Theater") {
                                    Text(request.theater ?? "—")
                                }
                                LabeledField(label: "Industry Segment") {
                                    Text(request.industrySegment ?? "—")
                                }
                            }
                            if let link = request.sfdcOpportunityLink, !link.isEmpty {
                                LabeledField(label: "Salesforce Record URL") {
                                    Link(link, destination: URL(string: link)!)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding()
                    }

                    GroupBox("Business Case") {
                        VStack(alignment: .leading, spacing: 12) {
                            if mode == .revise {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Business Justification")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextEditor(text: $editedJustification)
                                        .frame(minHeight: 80)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Expected Outcome")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextEditor(text: $editedOutcome)
                                        .frame(minHeight: 60)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Risk Assessment")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextEditor(text: $editedRisk)
                                        .frame(minHeight: 60)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                                }
                            } else {
                                LabeledField(label: "Business Justification") {
                                    Text(request.businessJustification ?? "—")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                LabeledField(label: "Expected Outcome") {
                                    Text(request.expectedOutcome ?? "—")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                LabeledField(label: "Risk Assessment") {
                                    Text(request.riskAssessment ?? "—")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding()
                    }

                    if request.isRejected, let gvpComments = request.gvpComments, !gvpComments.isEmpty {
                        GroupBox("Rejection Feedback") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(gvpComments)
                                    .foregroundColor(.red)
                            }
                            .padding()
                        }
                    }

                    GroupBox("Activity Log") {
                        ApprovalLogContent(request: request)
                            .padding()
                    }

                    if !linkedOpportunities.isEmpty {
                        GroupBox("Linked Opportunities") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(linkedOpportunities) { opp in
                                    HStack {
                                        Text(opp.opportunityName)
                                        Spacer()
                                        Text(opp.stage ?? "—")
                                            .foregroundColor(.secondary)
                                        Text(opp.formattedAmount)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    if mode == .revise {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Comment (optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Add a comment...", text: $comment)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)

                Spacer()

                if mode == .revise {
                    Button("Save as Draft") {
                        saveRevision(submit: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundColor(.black)
                    .disabled(isSaving)

                    Button("Submit") {
                        saveRevision(submit: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }

                if canWithdraw {
                    Button("Withdraw") {
                        showingWithdrawSheet = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)
                }

                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 650)
        .onAppear {
            editedJustification = request.businessJustification ?? ""
            editedOutcome = request.expectedOutcome ?? ""
            editedRisk = request.riskAssessment ?? ""
            dataService.loadLinkedOpportunities(for: request.requestId) { opps in
                linkedOpportunities = opps
            }
        }
        .sheet(isPresented: $showingWithdrawSheet) {
            VStack(spacing: 16) {
                Text("Withdraw Request")
                    .font(.headline)
                Text("This will return the request to Draft status and clear all approvals.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reason for withdrawal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $withdrawComment)
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                }
                HStack {
                    Button("Cancel") {
                        withdrawComment = ""
                        showingWithdrawSheet = false
                    }
                    Spacer()
                    Button("Withdraw") {
                        dataService.withdrawRequest(requestId: request.requestId, comment: withdrawComment.isEmpty ? nil : withdrawComment) { success, _ in
                            if success {
                                withdrawComment = ""
                                showingWithdrawSheet = false
                                isPresented = false
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)
                }
            }
            .padding(24)
            .frame(width: 400)
        }
    }

    private func saveRevision(submit: Bool) {
        isSaving = true
        dataService.reviseRequest(
            requestId: request.requestId,
            justification: editedJustification,
            outcome: editedOutcome,
            risk: editedRisk,
            submit: submit,
            comment: comment.isEmpty ? nil : comment
        ) { success, error in
            isSaving = false
            if success {
                isPresented = false
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .trailing)
            
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ApprovalLogContent: View {
    let request: InvestmentRequest
    @EnvironmentObject var dataService: DataService
    @State private var dynamicSteps: [ApprovalStep] = []
    @State private var loadedSteps = false

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return DateFormatter.shortDateTime.string(from: date)
    }

    private func statusIcon(_ status: String) -> (name: String, color: Color) {
        switch status {
        case "Created": return ("doc.circle.fill", .blue)
        case "Draft": return ("pencil.circle.fill", .gray)
        case "Submitted": return ("paperplane.circle.fill", .blue)
        case "Withdrawn": return ("arrow.uturn.backward.circle.fill", .yellow)
        case "Rejected": return ("xmark.circle.fill", .red)
        default: return ("checkmark.circle.fill", .green)
        }
    }

    private var hasDynamicSteps: Bool {
        if let steps = request.approvalSteps, !steps.isEmpty { return true }
        return !dynamicSteps.isEmpty
    }

    private var effectiveSteps: [ApprovalStep] {
        if let steps = request.approvalSteps, !steps.isEmpty { return steps }
        return dynamicSteps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logRow(status: "Created", user: request.createdByName, comment: nil, date: request.createdAt)

            if let draftByName = request.draftByName, request.draftAt != nil {
                ApprovalLogDivider()
                logRow(status: "Draft", user: draftByName, comment: request.draftComment, date: request.draftAt)
            }

            if let submittedByName = request.submittedByName {
                ApprovalLogDivider()
                logRow(status: "Submitted", user: submittedByName, comment: request.submittedComment, date: request.submittedAt)
            }

            if hasDynamicSteps {
                ForEach(effectiveSteps) { step in
                    ApprovalLogDivider()
                    if step.isApproved {
                        logRow(
                            status: step.isFinalStep ? "Final Approved" : "Approved",
                            user: step.approverName,
                            title: step.approverTitle,
                            comment: step.comments,
                            dateString: step.approvedAt
                        )
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.circle")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pending: \(step.approverName ?? "Unknown")\(step.approverTitle != nil ? " (\(step.approverTitle!))" : "")")
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                                Text(step.isFinalStep ? "Final approval" : "Step \(step.stepOrder)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else {
                if request.dmApprovedBy != nil {
                    ApprovalLogDivider()
                    logRow(status: "DM Approved", user: request.dmApprovedBy, title: request.dmApprovedByTitle, comment: request.dmComments, date: request.dmApprovedAt)
                }
                if request.rdApprovedBy != nil {
                    ApprovalLogDivider()
                    logRow(status: "RD Approved", user: request.rdApprovedBy, title: request.rdApprovedByTitle, comment: request.rdComments, date: request.rdApprovedAt)
                }
                if request.avpApprovedBy != nil {
                    ApprovalLogDivider()
                    logRow(status: "AVP Approved", user: request.avpApprovedBy, title: request.avpApprovedByTitle, comment: request.avpComments, date: request.avpApprovedAt)
                }
                if request.gvpApprovedBy != nil {
                    ApprovalLogDivider()
                    logRow(status: "GVP/Final Approved", user: request.gvpApprovedBy, title: request.gvpApprovedByTitle, comment: request.gvpComments, date: request.gvpApprovedAt)
                }

                if let nextApprover = request.nextApproverName, !request.isFinalApproved && request.status != "REJECTED" && request.status != "DRAFT" {
                    ApprovalLogDivider()
                    HStack(spacing: 8) {
                        Image(systemName: "clock.circle")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pending: \(nextApprover)\(request.nextApproverTitle != nil ? " (\(request.nextApproverTitle!))" : "")")
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("Awaiting approval")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }

            if let withdrawnByName = request.withdrawnByName {
                ApprovalLogDivider()
                logRow(status: "Withdrawn", user: withdrawnByName, comment: request.withdrawnComment, date: request.withdrawnAt)
            }
        }
        .onAppear {
            if !loadedSteps && request.approvalSteps == nil {
                dataService.fetchApprovalSteps(requestId: request.requestId) { steps in
                    dynamicSteps = steps
                    loadedSteps = true
                }
            }
        }
    }

    @ViewBuilder
    private func logRow(status: String, user: String?, title: String? = nil, comment: String?, date: Date?) -> some View {
        let icon = statusIcon(status)
        HStack(spacing: 8) {
            Image(systemName: icon.name)
                .foregroundColor(icon.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(status)
                        .fontWeight(.semibold)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(icon.color.opacity(0.15))
                        .cornerRadius(4)
                    if let user = user {
                        Text(user)
                            .fontWeight(.medium)
                    }
                    if let title = title, !title.isEmpty {
                        Text("(\(title))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let comment = comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func logRow(status: String, user: String?, title: String? = nil, comment: String?, dateString: String?) -> some View {
        let icon = statusIcon(status)
        HStack(spacing: 8) {
            Image(systemName: icon.name)
                .foregroundColor(icon.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(status)
                        .fontWeight(.semibold)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(icon.color.opacity(0.15))
                        .cornerRadius(4)
                    if let user = user {
                        Text(user)
                            .fontWeight(.medium)
                    }
                    if let title = title, !title.isEmpty {
                        Text("(\(title))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let ds = dateString {
                        Text(ds.prefix(19).replacingOccurrences(of: "T", with: " "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let comment = comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ApprovalLogDivider: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 12)
                .padding(.leading, 10)
            Spacer()
        }
    }
}

struct SortableColumnHeader: View {
    let title: String
    let column: SortColumn
    let currentColumn: SortColumn
    let ascending: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                if currentColumn == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .foregroundColor(currentColumn == column ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}
