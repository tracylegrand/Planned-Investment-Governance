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
    
    private let theaters = TheaterMapping.allTheaters
    
    private let portfoliosByTheater = TheaterMapping.portfoliosByTheater
    
    private var availablePortfolios: [String] {
        if selectedTheater == "All" {
            return portfoliosByTheater.values.flatMap { $0 }.sorted()
        }
        return portfoliosByTheater[selectedTheater] ?? []
    }
    private let statuses = ["All", "DRAFT", "SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED", "FINAL_APPROVED", "REJECTED"]
    
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
            
            let matchesTheater = selectedTheater == "All" || TheaterMapping.dbCodes(forDisplayName: selectedTheater).contains(request.theater ?? "")
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
            
            let matchesPendingMyApproval: Bool
            if filterPendingMyApproval {
                let currentUserName = dataService.currentUser?.displayName
                let isPending = ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains(request.status)
                matchesPendingMyApproval = isPending && request.nextApproverName == currentUserName
            } else {
                matchesPendingMyApproval = true
            }
            
            let matchesMyRequests: Bool
            if filterMyRequests {
                let currentUserName = dataService.currentUser?.displayName
                let currentUsername = dataService.currentUser?.snowflakeUsername
                let teamIds = dataService.teamEmployeeIds
                let isMyRequest = request.createdByName == currentUserName || request.createdBy == currentUsername
                let isTeamRequest = request.createdByEmployeeId.map { teamIds.contains($0) } ?? false
                matchesMyRequests = isMyRequest || isTeamRequest
            } else {
                matchesMyRequests = true
            }
            
            return matchesSearch && matchesTheater && matchesIndustry && matchesQuarter && matchesStatus && matchesPendingMyApproval && matchesMyRequests
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
                        Text(selectedIndustries.isEmpty ? "All Portfolios" : "\(selectedIndustries.count) Selected")
                        Image(systemName: "chevron.down")
                    }
                    .frame(width: 140)
                }
                .disabled(availablePortfolios.isEmpty)
                .popover(isPresented: $showIndustryPicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Select Portfolios")
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
                                if selectedIndustries.count == availablePortfolios.count {
                                    selectedIndustries.removeAll()
                                } else {
                                    selectedIndustries = Set(availablePortfolios)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedIndustries.count == availablePortfolios.count ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedIndustries.count == availablePortfolios.count ? .blue : .secondary)
                                    Text("All")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(availablePortfolios, id: \.self) { industry in
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
            NewRequestView(isPresented: $showingNewRequest)
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
        .onChange(of: selectedTheater) { _, _ in
            if availablePortfolios.isEmpty {
                selectedIndustries.removeAll()
            } else {
                selectedIndustries = selectedIndustries.filter { availablePortfolios.contains($0) }
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

struct ApprovalHistoryRow: View {
    let level: String
    let approverName: String
    let approverTitle: String?
    let approvedAt: Date?
    let comments: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(level) Approval")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let date = approvedAt {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("\(approverName)\(approverTitle.map { " (\($0))" } ?? "")")
                .font(.caption)
                .foregroundColor(.secondary)
            if let comments = comments, !comments.isEmpty {
                Text(comments)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct ApprovalLogContent: View {
    let request: InvestmentRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let createdByName = request.createdByName {
                logRow(status: "Created", name: createdByName, date: request.createdAt)
            }
            if let submittedByName = request.submittedByName {
                logRow(status: "Submitted", name: submittedByName, date: request.submittedAt, comment: request.submittedComment)
            }
            if let dm = request.dmApprovedBy {
                logRow(status: "DM Approved", name: dm, title: request.dmApprovedByTitle, date: request.dmApprovedAt, comment: request.dmComments)
            }
            if let rd = request.rdApprovedBy {
                logRow(status: "RD Approved", name: rd, title: request.rdApprovedByTitle, date: request.rdApprovedAt, comment: request.rdComments)
            }
            if let avp = request.avpApprovedBy {
                logRow(status: "AVP Approved", name: avp, title: request.avpApprovedByTitle, date: request.avpApprovedAt, comment: request.avpComments)
            }
            if let gvp = request.gvpApprovedBy {
                logRow(status: "Final Approved", name: gvp, title: request.gvpApprovedByTitle, date: request.gvpApprovedAt, comment: request.gvpComments)
            }
            if let withdrawnBy = request.withdrawnByName {
                logRow(status: "Withdrawn", name: withdrawnBy, date: request.withdrawnAt, comment: request.withdrawnComment)
            }
            if let nextApprover = request.nextApproverName, request.isSubmitted {
                logRow(status: "Pending", name: nextApprover, title: request.nextApproverTitle)
            }
        }
    }
    
    private func logRow(status: String, name: String, title: String? = nil, date: Date? = nil, comment: String? = nil) -> some View {
        HStack(alignment: .top) {
            Text(status)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name)\(title.map { " (\($0))" } ?? "")")
                    .font(.caption)
                if let comment = comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            Spacer()
            if let date = date {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
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
            RequestDetailView(request: request, isPresented: $showingDetail, mode: request.isEditable ? .edit : .view)
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

struct NewRequestView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataService: DataService
    
    @State private var title = ""
    @State private var selectedAccount: SFDCAccount?
    @State private var accountSearchText = ""
    @State private var searchResults: [SFDCAccount] = []
    @State private var isSearching = false
    @State private var investmentType = ""
    @State private var amount = ""
    @State private var quarter = ""
    @State private var theater = "US Majors"
    @State private var industrySegment = ""
    @State private var justification = ""
    @State private var expectedOutcome = ""
    @State private var riskAssessment = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
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
    private let theaters = ["US Majors", "US Public Sector", "Americas Enterprise", "Americas Acquisition", "EMEA", "APJ"]
    
    private var availableQuarters: [String] {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        let (currentFY, currentQ): (Int, Int)
        switch month {
        case 2, 3, 4:
            (currentFY, currentQ) = (year + 1, 1)
        case 5, 6, 7:
            (currentFY, currentQ) = (year + 1, 2)
        case 8, 9, 10:
            (currentFY, currentQ) = (year + 1, 3)
        case 11, 12:
            (currentFY, currentQ) = (year + 2, 4)
        case 1:
            (currentFY, currentQ) = (year + 1, 4)
        default:
            (currentFY, currentQ) = (year + 1, 1)
        }
        
        let previousFY = currentFY - 1
        var quarters = (1...4).map { "FY\(previousFY)-Q\($0)" } + (1...4).map { "FY\(currentFY)-Q\($0)" }
        
        if currentQ == 4 {
            let nextFY = currentFY + 1
            quarters += ["FY\(nextFY)-Q1", "FY\(nextFY)-Q2"]
        }
        
        return quarters
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Investment Request")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
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
                                        TextField("Search accounts...", text: $accountSearchText)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: accountSearchText) { _, newValue in
                                                searchAccounts(query: newValue)
                                            }
                                        
                                        if !searchResults.isEmpty {
                                            VStack(alignment: .leading, spacing: 0) {
                                                ForEach(searchResults.prefix(5)) { account in
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
                                                            if let t = account.theater {
                                                                Text(t)
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                        }
                                                        .padding(8)
                                                    }
                                                    .buttonStyle(.plain)
                                                    
                                                    if account.id != searchResults.prefix(5).last?.id {
                                                        Divider()
                                                    }
                                                }
                                            }
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
                                
                                LabeledField(label: "Amount") {
                                    TextField("$0", text: $amount)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)
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
                                        ForEach(theaters, id: \.self) { Text($0) }
                                    }
                                    .labelsHidden()
                                }
                                
                                LabeledField(label: "Industry Segment") {
                                    TextField("Enter segment", text: $industrySegment)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding()
                    }
                    
                    GroupBox("Business Case") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledField(label: "Business Justification") {
                                TextEditor(text: $justification)
                                    .frame(height: 80)
                                    .border(Color.secondary.opacity(0.3))
                            }
                            
                            LabeledField(label: "Expected Outcome") {
                                TextEditor(text: $expectedOutcome)
                                    .frame(height: 80)
                                    .border(Color.secondary.opacity(0.3))
                            }
                            
                            LabeledField(label: "Risk Assessment") {
                                TextEditor(text: $riskAssessment)
                                    .frame(height: 80)
                                    .border(Color.secondary.opacity(0.3))
                            }
                        }
                        .padding()
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Spacer()
                
                Button("Save as Draft") {
                    saveRequest()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || isSaving)
            }
            .padding()
        }
        .frame(width: 700, height: 700)
        .onAppear {
            if quarter.isEmpty {
                quarter = defaultQuarter
            }
        }
    }
    
    private func searchAccounts(query: String) {
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        
        isSearching = true
        dataService.searchAccounts(query: query) { accounts, _ in
            isSearching = false
            searchResults = accounts
        }
    }
    
    private func saveRequest() {
        isSaving = true
        errorMessage = nil
        
        let amountValue = Double(amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        
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
            industrySegment: industrySegment.isEmpty ? nil : industrySegment
        ) { success, _ in
            isSaving = false
            if success {
                isPresented = false
            } else {
                errorMessage = "Failed to create request. Please try again."
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
    case edit
    case revise
}

struct RequestDetailView: View {
    let request: InvestmentRequest
    @Binding var isPresented: Bool
    var mode: RequestDetailMode = .view
    @EnvironmentObject var dataService: DataService
    @State private var showingSubmitConfirm = false
    @State private var showingWithdrawConfirm = false
    @State private var linkedOpportunities: [SFDCOpportunity] = []
    @State private var isSaving = false
    
    // Editable fields for revise mode
    @State private var editedJustification: String = ""
    @State private var editedOutcome: String = ""
    @State private var editedRisk: String = ""
    
    private var isEditable: Bool {
        mode == .edit || mode == .revise
    }
    
    private var canWithdraw: Bool {
        request.canWithdraw && mode == .view
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.requestTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                
                StatusBadge(status: request.status)
                
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
                
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Request Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            DetailRow(label: "Account", value: request.accountName ?? "—")
                            DetailRow(label: "Investment Type", value: request.investmentType ?? "—")
                            DetailRow(label: "Amount", value: request.formattedAmount)
                            DetailRow(label: "Quarter", value: request.investmentQuarter ?? "—")
                            DetailRow(label: "Theater", value: request.theater ?? "—")
                            DetailRow(label: "Industry Segment", value: request.industrySegment ?? "—")
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
                                DetailRow(label: "Business Justification", value: request.businessJustification ?? "—")
                                DetailRow(label: "Expected Outcome", value: request.expectedOutcome ?? "—")
                                DetailRow(label: "Risk Assessment", value: request.riskAssessment ?? "—")
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
                    
                    GroupBox("Approval Status") {
                        VStack(alignment: .leading, spacing: 12) {
                            DetailRow(label: "Created By", value: request.createdByName ?? "—")
                            DetailRow(label: "Current Status", value: request.statusDisplayName)
                            
                            if let nextApprover = request.nextApproverName, !request.isFinalApproved && request.status != "REJECTED" {
                                DetailRow(label: "Pending Approval", value: "\(nextApprover)\(request.nextApproverTitle != nil ? " (\(request.nextApproverTitle!))" : "")")
                            }
                        }
                        .padding()
                    }
                    
                    if request.dmApprovedBy != nil || request.rdApprovedBy != nil || request.avpApprovedBy != nil || request.gvpApprovedBy != nil {
                        GroupBox("Approval History") {
                            VStack(alignment: .leading, spacing: 16) {
                                if let dmApprover = request.dmApprovedBy {
                                    ApprovalHistoryRow(
                                        level: "DM",
                                        approverName: dmApprover,
                                        approverTitle: request.dmApprovedByTitle,
                                        approvedAt: request.dmApprovedAt,
                                        comments: request.dmComments
                                    )
                                }
                                if let rdApprover = request.rdApprovedBy {
                                    ApprovalHistoryRow(
                                        level: "RD",
                                        approverName: rdApprover,
                                        approverTitle: request.rdApprovedByTitle,
                                        approvedAt: request.rdApprovedAt,
                                        comments: request.rdComments
                                    )
                                }
                                if let avpApprover = request.avpApprovedBy {
                                    ApprovalHistoryRow(
                                        level: "AVP",
                                        approverName: avpApprover,
                                        approverTitle: request.avpApprovedByTitle,
                                        approvedAt: request.avpApprovedAt,
                                        comments: request.avpComments
                                    )
                                }
                                if let gvpApprover = request.gvpApprovedBy {
                                    ApprovalHistoryRow(
                                        level: "GVP/Final",
                                        approverName: gvpApprover,
                                        approverTitle: request.gvpApprovedByTitle,
                                        approvedAt: request.gvpApprovedAt,
                                        comments: request.gvpComments
                                    )
                                }
                            }
                            .padding()
                        }
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
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                if mode == .revise {
                    Button("Save as Draft") {
                        saveRevision(submit: false)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                    
                    Button("Submit") {
                        saveRevision(submit: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                } else if mode == .edit && request.isEditable {
                    Button("Submit for Approval") {
                        showingSubmitConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if canWithdraw {
                    Button("Withdraw") {
                        showingWithdrawConfirm = true
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
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
        .alert("Submit Request", isPresented: $showingSubmitConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Submit") {
                dataService.submitRequest(requestId: request.requestId) { success, error in
                    if success {
                        isPresented = false
                    }
                }
            }
        } message: {
            Text("Submit this request for approval? Once submitted, it cannot be edited unless withdrawn.")
        }
        .alert("Withdraw Request", isPresented: $showingWithdrawConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Withdraw") {
                dataService.withdrawRequest(requestId: request.requestId) { success, error in
                    if success {
                        isPresented = false
                    }
                }
            }
        } message: {
            Text("Withdraw this request back to Draft status? This will clear approvals from the current level forward.")
        }
    }
    
    private func saveRevision(submit: Bool) {
        isSaving = true
        dataService.reviseRequest(
            requestId: request.requestId,
            justification: editedJustification,
            outcome: editedOutcome,
            risk: editedRisk,
            submit: submit
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
