import SwiftUI

struct ApprovalsView: View {
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    
    @State private var showMyApprovalsOnly = true
    @State private var selectedTheater: String = "All"
    @State private var selectedQuarter: String = "All"
    
    private var theaters: [String] {
        ["All"] + dataService.sfdcTheaters
    }
    private let quarters = ["All", "FY27-Q1", "FY27-Q2", "FY27-Q3", "FY27-Q4"]
    
    var pendingApprovals: [InvestmentRequest] {
        dataService.investmentRequests.filter { request in
            let isPending = ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains(request.status)
            let matchesTheater = selectedTheater == "All" || request.theater == selectedTheater
            let matchesQuarter = selectedQuarter == "All" || request.investmentQuarter == selectedQuarter
            
            if showMyApprovalsOnly {
                let isMyApproval = request.nextApproverName == dataService.currentUser?.displayName
                return isPending && isMyApproval && matchesTheater && matchesQuarter
            }
            
            return isPending && matchesTheater && matchesQuarter
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Approvals")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Toggle("My Approvals Only", isOn: $showMyApprovalsOnly)
                    .toggleStyle(.switch)
            }
            .padding()
            
            HStack(spacing: 16) {
                Picker("Theater", selection: $selectedTheater) {
                    ForEach(theaters, id: \.self) { Text($0) }
                }
                .frame(width: 180)
                
                Picker("Quarter", selection: $selectedQuarter) {
                    ForEach(quarters, id: \.self) { Text($0) }
                }
                .frame(width: 120)
                
                Spacer()
                
                Text("\(pendingApprovals.count) pending")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
            
            Divider()
            
            if pendingApprovals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text(showMyApprovalsOnly ? "No requests awaiting your approval" : "No pending approvals")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(pendingApprovals) { request in
                        ApprovalRow(request: request)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct ApprovalRow: View {
    let request: InvestmentRequest
    @EnvironmentObject var dataService: DataService
    @State private var showingApprovalSheet = false
    @State private var showingRejectConfirm = false
    @State private var comments = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
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
                
                if let createdBy = request.createdByName {
                    Text("Submitted by: \(createdBy)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(request.formattedAmount)
                    .font(.headline)
                
                Text(approvalLevelName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            StatusBadge(status: request.status)
            
            HStack(spacing: 8) {
                Button(action: { showingApprovalSheet = true }) {
                    Label("Review", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                
                Button(action: { approve() }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.borderless)
                .help("Approve")
                .disabled(isProcessing)
                
                Button(action: { showingRejectConfirm = true }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Reject")
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingApprovalSheet) {
            ApprovalDetailSheet(request: request, isPresented: $showingApprovalSheet)
        }
        .alert("Reject Request", isPresented: $showingRejectConfirm) {
            TextField("Reason for rejection", text: $comments)
            Button("Cancel", role: .cancel) {}
            Button("Reject", role: .destructive) { reject() }
        } message: {
            Text("Are you sure you want to reject \"\(request.requestTitle)\"?")
        }
    }
    
    private var approvalLevelName: String {
        switch request.status {
        case "SUBMITTED": return "DM Approval"
        case "DM_APPROVED": return "RD Approval"
        case "RD_APPROVED": return "AVP Approval"
        case "AVP_APPROVED": return "GVP Approval"
        default: return "Approval"
        }
    }
    
    private func approve() {
        isProcessing = true
        dataService.approveRequest(requestId: request.requestId, comments: nil) { success, error in
            isProcessing = false
            if !success {
                errorMessage = error
            }
        }
    }
    
    private func reject() {
        isProcessing = true
        dataService.rejectRequest(requestId: request.requestId, comments: comments.isEmpty ? nil : comments) { success, error in
            isProcessing = false
            if !success {
                errorMessage = error
            }
        }
    }
}

struct ApprovalDetailSheet: View {
    let request: InvestmentRequest
    @Binding var isPresented: Bool
    @EnvironmentObject var dataService: DataService
    @State private var comments = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var linkedOpportunities: [SFDCOpportunity] = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Request")
                    .font(.title2)
                    .fontWeight(.bold)
                
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

                            LabeledField(label: "Submitted By") {
                                Text(request.createdByName ?? "—")
                            }
                        }
                        .padding()
                    }
                    
                    GroupBox("Business Case") {
                        VStack(alignment: .leading, spacing: 12) {
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
                    
                    GroupBox("Activity Log") {
                        ApprovalLogContent(request: request)
                            .padding()
                    }
                    
                    GroupBox("Your Decision") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Comments (optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $comments)
                                .frame(height: 60)
                                .border(Color.secondary.opacity(0.3))
                            
                            if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding()
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                
                Button("Send Back for Revision") {
                    sendBackForRevision()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
                .disabled(isProcessing)
                
                Button("Deny Request") {
                    denyRequest()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .disabled(isProcessing)
                
                Spacer()
                
                Button("Approve") {
                    approve()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
            .padding()
        }
        .frame(width: 650, height: 700)
        .onAppear {
            dataService.loadLinkedOpportunities(for: request.requestId) { opps in
                linkedOpportunities = opps
            }
        }
    }
    
    private func approve() {
        isProcessing = true
        errorMessage = nil
        dataService.approveRequest(requestId: request.requestId, comments: comments.isEmpty ? nil : comments) { success, error in
            isProcessing = false
            if success {
                isPresented = false
            } else {
                errorMessage = error
            }
        }
    }
    
    private func sendBackForRevision() {
        isProcessing = true
        errorMessage = nil
        dataService.sendBackForRevision(requestId: request.requestId, comments: comments.isEmpty ? nil : comments) { success, error in
            isProcessing = false
            if success {
                isPresented = false
            } else {
                errorMessage = error
            }
        }
    }
    
    private func denyRequest() {
        isProcessing = true
        errorMessage = nil
        dataService.denyRequest(requestId: request.requestId, comments: comments.isEmpty ? nil : comments) { success, error in
            isProcessing = false
            if success {
                isPresented = false
            } else {
                errorMessage = error
            }
        }
    }
}


