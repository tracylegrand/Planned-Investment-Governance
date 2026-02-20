import SwiftUI

struct InvestmentRequestsView: View {
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    
    @State private var searchText = ""
    @State private var selectedTheater: String = "All"
    @State private var selectedQuarter: String = "All"
    @State private var selectedStatus: String = "All"
    @State private var showingNewRequest = false
    
    private let theaters = ["All", "US Majors", "US Public Sector", "Americas Enterprise", "Americas Acquisition", "EMEA", "APJ"]
    private let quarters = ["All", "FY27-Q1", "FY27-Q2", "FY27-Q3", "FY27-Q4"]
    private let statuses = ["All", "DRAFT", "SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED", "FINAL_APPROVED", "REJECTED"]
    
    var filteredRequests: [InvestmentRequest] {
        dataService.investmentRequests.filter { request in
            let matchesSearch = searchText.isEmpty ||
                request.requestTitle.localizedCaseInsensitiveContains(searchText) ||
                (request.accountName?.localizedCaseInsensitiveContains(searchText) ?? false)
            
            let matchesTheater = selectedTheater == "All" || request.theater == selectedTheater
            let matchesQuarter = selectedQuarter == "All" || request.investmentQuarter == selectedQuarter
            let matchesStatus = selectedStatus == "All" || request.status == selectedStatus
            
            return matchesSearch && matchesTheater && matchesQuarter && matchesStatus
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
            
            HStack(spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search requests...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 300)
                
                Picker("Theater", selection: $selectedTheater) {
                    ForEach(theaters, id: \.self) { Text($0) }
                }
                .frame(width: 180)
                
                Picker("Quarter", selection: $selectedQuarter) {
                    ForEach(quarters, id: \.self) { Text($0) }
                }
                .frame(width: 120)
                
                Picker("Status", selection: $selectedStatus) {
                    ForEach(statuses, id: \.self) { theater in
                        Text(statusDisplayName(theater)).tag(theater)
                    }
                }
                .frame(width: 150)
                
                Spacer()
                
                Text("\(filteredRequests.count) requests")
                    .foregroundColor(.secondary)
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
                    if searchText.isEmpty && selectedTheater == "All" && selectedQuarter == "All" && selectedStatus == "All" {
                        Button("Create First Request") {
                            showingNewRequest = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRequests) { request in
                        RequestListRow(request: request, navigationState: navigationState)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
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
}

struct RequestListRow: View {
    let request: InvestmentRequest
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    @State private var showingDetail = false
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.requestTitle)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    if let accountName = request.accountName {
                        Text(accountName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let theater = request.theater {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(theater)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let quarter = request.investmentQuarter {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(quarter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(request.formattedAmount)
                    .font(.headline)
                
                if let nextApprover = request.nextApproverName, !request.isFinalApproved {
                    Text("Awaiting: \(nextApprover)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            StatusBadge(status: request.status)
            
            HStack(spacing: 8) {
                Button(action: { showingDetail = true }) {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .help("View Details")
                
                if request.isEditable {
                    Button(action: { showingDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            RequestDetailView(request: request, isPresented: $showingDetail)
        }
        .alert("Delete Request", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                dataService.deleteRequest(requestId: request.requestId) { _ in }
            }
        } message: {
            Text("Are you sure you want to delete \"\(request.requestTitle)\"? This action cannot be undone.")
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
    @State private var quarter = "FY27-Q1"
    @State private var theater = "US Majors"
    @State private var industrySegment = ""
    @State private var justification = ""
    @State private var expectedOutcome = ""
    @State private var riskAssessment = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    private let investmentTypes = ["Professional Services", "Customer Success", "Training", "Support", "Partnership", "Other"]
    private let theaters = ["US Majors", "US Public Sector", "Americas Enterprise", "Americas Acquisition", "EMEA", "APJ"]
    private let quarters = ["FY27-Q1", "FY27-Q2", "FY27-Q3", "FY27-Q4"]
    
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
                                        ForEach(quarters, id: \.self) { Text($0) }
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
    }
    
    private func searchAccounts(query: String) {
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        
        isSearching = true
        dataService.searchAccounts(query: query) { accounts in
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

struct RequestDetailView: View {
    let request: InvestmentRequest
    @Binding var isPresented: Bool
    @EnvironmentObject var dataService: DataService
    @State private var showingSubmitConfirm = false
    @State private var showingWithdrawConfirm = false
    @State private var linkedOpportunities: [SFDCOpportunity] = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.requestTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                
                StatusBadge(status: request.status)
                
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
                            DetailRow(label: "Business Justification", value: request.businessJustification ?? "—")
                            DetailRow(label: "Expected Outcome", value: request.expectedOutcome ?? "—")
                            DetailRow(label: "Risk Assessment", value: request.riskAssessment ?? "—")
                        }
                        .padding()
                    }
                    
                    GroupBox("Approval Status") {
                        VStack(alignment: .leading, spacing: 12) {
                            DetailRow(label: "Created By", value: request.createdByName ?? "—")
                            DetailRow(label: "Current Status", value: request.statusDisplayName)
                            
                            if let nextApprover = request.nextApproverName {
                                DetailRow(label: "Next Approver", value: "\(nextApprover) (\(request.nextApproverTitle ?? ""))")
                            }
                            
                            if let dmApprover = request.dmApprovedBy {
                                DetailRow(label: "DM Approved By", value: dmApprover)
                            }
                            if let rdApprover = request.rdApprovedBy {
                                DetailRow(label: "RD Approved By", value: rdApprover)
                            }
                            if let avpApprover = request.avpApprovedBy {
                                DetailRow(label: "AVP Approved By", value: avpApprover)
                            }
                            if let gvpApprover = request.gvpApprovedBy {
                                DetailRow(label: "GVP Approved By", value: gvpApprover)
                            }
                        }
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
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                if request.isEditable {
                    Button("Submit for Approval") {
                        showingSubmitConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if request.canWithdraw {
                    Button("Withdraw") {
                        showingWithdrawConfirm = true
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(width: 600, height: 600)
        .onAppear {
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
