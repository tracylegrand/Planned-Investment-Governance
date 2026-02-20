import SwiftUI

struct DashboardView: View {
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Investment Governance Dashboard")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if let user = dataService.currentUser {
                        Text("Welcome, \(user.displayName)")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                if let summary = dataService.summary {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        SummaryCard(title: "Total Requests", value: "\(summary.totalRequests)", color: .blue)
                        SummaryCard(title: "Draft", value: "\(summary.totalDraft)", color: .gray)
                        SummaryCard(title: "In Review", value: "\(summary.totalSubmitted)", color: .orange)
                        SummaryCard(title: "Approved", value: "\(summary.totalApproved)", color: .green)
                    }
                    .padding(.horizontal)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        SummaryCard(title: "Pending My Approval", value: "\(summary.totalPendingMyApproval)", color: .purple, action: {
                            navigationState.selectedTab = 2
                        })
                        SummaryCard(title: "Requested", value: formatCurrency(summary.totalInvestmentRequested), color: .blue)
                        SummaryCard(title: "Approved", value: formatCurrency(summary.totalInvestmentApproved), color: .green)
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView("Loading summary...")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                
                Divider()
                    .padding(.vertical)
                
                HStack {
                    Text("Recent Requests")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("View All") {
                        navigationState.selectedTab = 1
                    }
                }
                .padding(.horizontal)
                
                if dataService.investmentRequests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No investment requests yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Create First Request") {
                            navigationState.selectedTab = 1
                            navigationState.showingNewRequest = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    ForEach(dataService.investmentRequests.prefix(5)) { request in
                        RequestRow(request: request, navigationState: navigationState)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.vertical)
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
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

struct RequestRow: View {
    let request: InvestmentRequest
    @ObservedObject var navigationState: NavigationState
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.requestTitle)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    if let accountName = request.accountName {
                        Text(accountName)
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
            
            Text(request.formattedAmount)
                .font(.headline)
                .foregroundColor(.primary)
            
            StatusBadge(status: request.status)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture {
            navigationState.selectedRequestId = request.requestId
            navigationState.selectedTab = 1
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
