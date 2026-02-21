import SwiftUI

struct DashboardView: View {
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    
    @AppStorage("dashboard_selectedTheater") private var storedTheater: String = "All"
    @AppStorage("dashboard_selectedIndustries") private var storedIndustriesData: Data = Data()
    @AppStorage("dashboard_selectedQuarters") private var storedQuartersData: Data = Data()
    @AppStorage("dashboard_selectedStatus") private var storedStatus: String = "All"
    
    @State private var selectedTheater: String = "All"
    @State private var selectedIndustries: Set<String> = []
    @State private var selectedQuarters: Set<String> = []
    @State private var selectedStatus: String = "All"
    @State private var showQuarterPicker = false
    @State private var showIndustryPicker = false
    
    private var hasActiveFilters: Bool {
        selectedTheater != "All" || !selectedIndustries.isEmpty || !selectedQuarters.isEmpty || selectedStatus != "All"
    }
    
    private func clearAllFilters() {
        selectedTheater = "All"
        selectedIndustries = []
        selectedQuarters = []
        selectedStatus = "All"
    }
    
    private func loadFilters() {
        selectedTheater = storedTheater
        selectedStatus = storedStatus
        if let industries = try? JSONDecoder().decode(Set<String>.self, from: storedIndustriesData) {
            selectedIndustries = industries
        }
        if let quarters = try? JSONDecoder().decode(Set<String>.self, from: storedQuartersData) {
            selectedQuarters = quarters
        }
    }
    
    private func saveFilters() {
        storedTheater = selectedTheater
        storedStatus = selectedStatus
        storedIndustriesData = (try? JSONEncoder().encode(selectedIndustries)) ?? Data()
        storedQuartersData = (try? JSONEncoder().encode(selectedQuarters)) ?? Data()
    }
    
    private let theaters = ["All", "USMajors", "US Public Sector", "Americas Enterprise", "Americas Acquisition", "EMEA", "APJ"]
    private let industryList = ["Financial Services", "Healthcare & Life Sciences", "Manufacturing", "Communications, Media & Entertainment", "Retail & Consumer Goods", "FSI Globals"]
    private let statuses = ["All", "DRAFT", "SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED", "FINAL_APPROVED", "REJECTED"]
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var quartersGroupedByYear: [(year: String, quarters: [String])] {
        let allQuarters = Set(dataService.investmentRequests.compactMap { $0.investmentQuarter })
        var grouped: [String: [String]] = [:]
        
        for quarter in allQuarters {
            if let fyRange = quarter.range(of: "FY") {
                let yearPart = String(quarter[fyRange.lowerBound...].prefix(6))
                grouped[yearPart, default: []].append(quarter)
            }
        }
        
        return grouped.sorted { $0.key > $1.key }.map { (year: $0.key, quarters: $0.value.sorted()) }
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
    
    var filteredSummary: (total: Int, draft: Int, inReview: Int, approved: Int, pendingMyApproval: Int, totalRequested: Double, totalApproved: Double, draftAmount: Double, pendingAmount: Double) {
        let requests = filteredRequests
        let draftRequests = requests.filter { $0.status == "DRAFT" }
        let draft = draftRequests.count
        let draftAmount = draftRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        let inReview = requests.filter { ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains($0.status) }.count
        let approvedRequests = requests.filter { $0.status == "FINAL_APPROVED" }
        let approved = approvedRequests.count
        let totalRequested = requests.compactMap { $0.requestedAmount }.reduce(0, +)
        let totalApproved = approvedRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        
        let currentUserName = dataService.currentUser?.displayName
        let pendingMyApprovalRequests = requests.filter { request in
            let isPending = ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains(request.status)
            return isPending && request.nextApproverName == currentUserName
        }
        let pendingMyApproval = pendingMyApprovalRequests.count
        let pendingAmount = pendingMyApprovalRequests.compactMap { $0.requestedAmount }.reduce(0, +)
        
        return (requests.count, draft, inReview, approved, pendingMyApproval, totalRequested, totalApproved, draftAmount, pendingAmount)
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
    
    var requestsByTheaterAndIndustry: [(theater: String, industries: [(industry: String, prevCount: Int, prevAmount: Double, currCount: Int, currAmount: Double, prevBudget: Double, currBudget: Double)])] {
        let theaterList = theaters.filter { $0 != "All" }
        let years = fiscalYears
        let prevYear = years[0]
        let currYear = years[1]
        let approvedRequests = filteredRequests.filter { $0.status == "FINAL_APPROVED" }
        
        return theaterList.compactMap { theater in
            let theaterRequests = approvedRequests.filter { $0.theater == theater }
            guard !theaterRequests.isEmpty else { return nil }
            
            let industryGroups = Dictionary(grouping: theaterRequests) { $0.industrySegment ?? "Unknown" }
            let industries = industryGroups.map { (industry, requests) -> (industry: String, prevCount: Int, prevAmount: Double, currCount: Int, currAmount: Double, prevBudget: Double, currBudget: Double) in
                let prevRequests = requests.filter { $0.investmentQuarter?.hasPrefix(prevYear) == true }
                let currRequests = requests.filter { $0.investmentQuarter?.hasPrefix(currYear) == true }
                let prevBudget = dataService.annualBudgets.filter { $0.theater == theater && $0.industrySegment == industry && $0.fiscalYear == prevYear }.map { $0.budgetAmount }.reduce(0, +)
                let currBudget = dataService.annualBudgets.filter { $0.theater == theater && $0.industrySegment == industry && $0.fiscalYear == currYear }.map { $0.budgetAmount }.reduce(0, +)
                return (
                    industry: industry,
                    prevCount: prevRequests.count,
                    prevAmount: prevRequests.compactMap { $0.requestedAmount }.reduce(0, +),
                    currCount: currRequests.count,
                    currAmount: currRequests.compactMap { $0.requestedAmount }.reduce(0, +),
                    prevBudget: prevBudget,
                    currBudget: currBudget
                )
            }.sorted { ($0.prevCount + $0.currCount) > ($1.prevCount + $1.currCount) }
            
            return (theater: theater, industries: industries)
        }
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
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(user.displayName)
                                .font(.headline)
                            if let title = user.title {
                                Text(title)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
                .padding(.horizontal)
                
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
                                    if selectedIndustries.count == industryList.count {
                                        selectedIndustries.removeAll()
                                    } else {
                                        selectedIndustries = Set(industryList)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: selectedIndustries.count == industryList.count ? "checkmark.square.fill" : "square")
                                            .foregroundColor(selectedIndustries.count == industryList.count ? .blue : .secondary)
                                        Text("All")
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(industryList, id: \.self) { industry in
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
                .onChange(of: selectedTheater) { _ in saveFilters() }
                .onChange(of: selectedIndustries) { _ in saveFilters() }
                .onChange(of: selectedQuarters) { _ in saveFilters() }
                .onChange(of: selectedStatus) { _ in saveFilters() }
                
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
                        VStack(spacing: 12) {
                            HStack(spacing: 0) {
                                SummaryCardCompact(title: "Total Requests", value: "\(summary.total)", color: .blue, action: {
                                    navigationState.passedStatus = "All"
                                    navigationState.passedFiscalYear = ""
                                    navigationState.selectedTab = 1
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Approved", value: "\(summary.approved)", color: .green, action: {
                                    navigationState.passedStatus = "FINAL_APPROVED"
                                    navigationState.passedFiscalYear = ""
                                    navigationState.selectedTab = 1
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Draft", value: "\(summary.draft)", color: .gray, action: {
                                    navigationState.passedStatus = "DRAFT"
                                    navigationState.passedFiscalYear = ""
                                    navigationState.selectedTab = 1
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Pending My Approval", value: "\(summary.pendingMyApproval)", color: .purple, action: {
                                    navigationState.filterPendingMyApproval = true
                                    navigationState.selectedTab = 1
                                })
                                .frame(maxWidth: .infinity)
                            }
                            
                            HStack(spacing: 0) {
                                SummaryCardCompact(title: "Requested Amount", value: formatCurrency(summary.totalRequested), color: .blue, action: {
                                    navigationState.passedStatus = "All"
                                    navigationState.passedFiscalYear = ""
                                    navigationState.selectedTab = 1
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Approved Amount", value: formatCurrency(summary.totalApproved), color: .green, action: {
                                    navigationState.passedStatus = "FINAL_APPROVED"
                                    navigationState.passedFiscalYear = ""
                                    navigationState.selectedTab = 1
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Draft Amount", value: formatCurrency(summary.draftAmount), color: .gray, action: {
                                    navigationState.passedStatus = "DRAFT"
                                    navigationState.passedFiscalYear = ""
                                    navigationState.selectedTab = 1
                                })
                                .frame(maxWidth: .infinity)
                                SummaryCardCompact(title: "Pending Amount", value: formatCurrency(summary.pendingAmount), color: .purple, action: {
                                    navigationState.filterPendingMyApproval = true
                                    navigationState.selectedTab = 1
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
                
                // Section 2: Approval Pipeline by Fiscal Year
                VStack(alignment: .leading, spacing: 8) {
                    Text("Approval Pipeline by Fiscal Year")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    GroupBox {
                        ApprovalPipelineView(requests: filteredRequests, navigationState: navigationState)
                            .frame(maxWidth: .infinity)
                            .padding(4)
                    }
                    .frame(width: sectionWidth)
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Section 3: Totals by Theater/Industry (Approved)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Totals by Theater/Industry (Approved)")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    GroupBox {
                        if requestsByTheaterAndIndustry.isEmpty {
                            Text("No data")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            TheaterIndustryTableView(
                                data: requestsByTheaterAndIndustry,
                                prevYear: fiscalYears[0],
                                currYear: fiscalYears[1]
                            )
                        }
                    }
                    .frame(width: sectionWidth)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.vertical)
        }
        .onAppear { loadFilters() }
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

struct TheaterIndustryTableView: View {
    let data: [(theater: String, industries: [(industry: String, prevCount: Int, prevAmount: Double, currCount: Int, currAmount: Double, prevBudget: Double, currBudget: Double)])]
    let prevYear: String
    let currYear: String
    
    private func formatCurrency(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "%.1fK", amount / 1_000)
        } else if amount > 0 {
            return String(format: "%.0f", amount)
        } else {
            return "0"
        }
    }
    
    private var flattenedRows: [(isTheater: Bool, name: String, prevCount: Int, prevAmount: Double, currCount: Int, currAmount: Double, prevBudget: Double, currBudget: Double)] {
        var rows: [(isTheater: Bool, name: String, prevCount: Int, prevAmount: Double, currCount: Int, currAmount: Double, prevBudget: Double, currBudget: Double)] = []
        for theaterGroup in data {
            let prevCount = theaterGroup.industries.map { $0.prevCount }.reduce(0, +)
            let currCount = theaterGroup.industries.map { $0.currCount }.reduce(0, +)
            let prevAmount = theaterGroup.industries.map { $0.prevAmount }.reduce(0, +)
            let currAmount = theaterGroup.industries.map { $0.currAmount }.reduce(0, +)
            let prevBudget = theaterGroup.industries.map { $0.prevBudget }.reduce(0, +)
            let currBudget = theaterGroup.industries.map { $0.currBudget }.reduce(0, +)
            rows.append((true, theaterGroup.theater, prevCount, prevAmount, currCount, currAmount, prevBudget, currBudget))
            for industry in theaterGroup.industries {
                rows.append((false, industry.industry, industry.prevCount, industry.prevAmount, industry.currCount, industry.currAmount, industry.prevBudget, industry.currBudget))
            }
        }
        return rows
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                    Text("Theater / Industry")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(width: 240, alignment: .leading)
                    
                    VStack(spacing: 4) {
                        Text("Full Year 2026")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        HStack(spacing: 14) {
                            Text("#").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 40, alignment: .trailing)
                            Text("Approved").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 85, alignment: .trailing)
                            Text("Budget").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 85, alignment: .trailing)
                            Text("Remaining").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 90, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.3), lineWidth: 1))
                    
                    VStack(spacing: 4) {
                        Text("Full Year 2027")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        HStack(spacing: 14) {
                            Text("#").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 40, alignment: .trailing)
                            Text("Approved").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 85, alignment: .trailing)
                            Text("Budget").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 85, alignment: .trailing)
                            Text("Remaining").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 90, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.3), lineWidth: 1))
                }
                .padding(.bottom, 10)
                
                Divider().padding(.bottom, 8)
                
                ForEach(Array(flattenedRows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 16) {
                        HStack(spacing: 0) {
                            if !row.isTheater {
                                Text("").frame(width: 20)
                            }
                            Text(row.name)
                                .font(row.isTheater ? .title3 : .body)
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor(.black)
                                .lineLimit(1)
                        }
                        .frame(width: 240, alignment: .leading)
                        
                        HStack(spacing: 14) {
                            Text("\(row.prevCount)")
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor(.black)
                                .frame(width: 40, alignment: .trailing)
                            Text(formatCurrency(row.prevAmount))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor(.black)
                                .frame(width: 85, alignment: .trailing)
                            Text(formatCurrency(row.prevBudget))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor(.black)
                                .frame(width: 85, alignment: .trailing)
                            Text(formatCurrency(row.prevBudget - row.prevAmount))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor((row.prevBudget - row.prevAmount) < 0 ? .red : .black)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        
                        HStack(spacing: 14) {
                            Text("\(row.currCount)")
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor(.black)
                                .frame(width: 40, alignment: .trailing)
                            Text(formatCurrency(row.currAmount))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor(.black)
                                .frame(width: 85, alignment: .trailing)
                            Text(formatCurrency(row.currBudget))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor(.black)
                                .frame(width: 85, alignment: .trailing)
                            Text(formatCurrency(row.currBudget - row.currAmount))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .foregroundColor((row.currBudget - row.currAmount) < 0 ? .red : .black)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.vertical, row.isTheater ? 5 : 3)
                    .background(row.isTheater ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
                }
            }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
    
    private func stagesForYear(_ year: String) -> [(String, Int)] {
        let yearRequests = requests.filter { $0.investmentQuarter?.hasPrefix(year) == true }
        return [
            ("Draft", yearRequests.filter { $0.status == "DRAFT" }.count),
            ("Submitted", yearRequests.filter { $0.status == "SUBMITTED" }.count),
            ("DM Review", yearRequests.filter { $0.status == "DM_APPROVED" }.count),
            ("RD Review", yearRequests.filter { $0.status == "RD_APPROVED" }.count),
            ("AVP Review", yearRequests.filter { $0.status == "AVP_APPROVED" }.count),
            ("Approved", yearRequests.filter { $0.status == "FINAL_APPROVED" }.count)
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
                                maxCount: maxCount,
                                color: colorForStage(stage.0),
                                onTap: {
                                    navigationState.passedStatus = statusCodeForStage(stage.0)
                                    navigationState.passedFiscalYear = year
                                    navigationState.selectedTab = 1
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
    let maxCount: Int
    let color: Color
    let onTap: () -> Void
    
    @State private var isHovering = false
    
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
                    .frame(width: 45, height: CGFloat(count) / CGFloat(max(maxCount, 1)) * 50)
                    .frame(minHeight: count > 0 ? 8 : 0)
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 45, height: 1)
            }
            .frame(height: 55)
            
            Text(stageName)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.black)
                .frame(width: 68)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 5)
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
