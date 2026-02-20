import SwiftUI

struct ReportingView: View {
    @EnvironmentObject var dataService: DataService
    @State private var selectedTheater: String = "All"
    @State private var selectedQuarter: String = "All"
    
    private let theaters = ["All", "US Majors", "US Public Sector", "Americas Enterprise", "Americas Acquisition", "EMEA", "APJ"]
    private let quarters = ["All", "FY27-Q1", "FY27-Q2", "FY27-Q3", "FY27-Q4"]
    
    var filteredRequests: [InvestmentRequest] {
        dataService.investmentRequests.filter { request in
            let matchesTheater = selectedTheater == "All" || request.theater == selectedTheater
            let matchesQuarter = selectedQuarter == "All" || request.investmentQuarter == selectedQuarter
            return matchesTheater && matchesQuarter
        }
    }
    
    var requestsByStatus: [(String, Int, Double)] {
        let statuses = ["DRAFT", "SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED", "FINAL_APPROVED", "REJECTED"]
        return statuses.map { status in
            let requests = filteredRequests.filter { $0.status == status }
            let total = requests.compactMap { $0.requestedAmount }.reduce(0, +)
            return (status, requests.count, total)
        }.filter { $0.1 > 0 }
    }
    
    var requestsByTheater: [(String, Int, Double)] {
        let theaterList = theaters.filter { $0 != "All" }
        return theaterList.map { theater in
            let requests = filteredRequests.filter { $0.theater == theater }
            let total = requests.compactMap { $0.requestedAmount }.reduce(0, +)
            return (theater, requests.count, total)
        }.filter { $0.1 > 0 }
    }
    
    var requestsByQuarter: [(String, Int, Double)] {
        let quarterList = quarters.filter { $0 != "All" }
        return quarterList.map { quarter in
            let requests = filteredRequests.filter { $0.investmentQuarter == quarter }
            let total = requests.compactMap { $0.requestedAmount }.reduce(0, +)
            return (quarter, requests.count, total)
        }.filter { $0.1 > 0 }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Investment Reports")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Picker("Theater", selection: $selectedTheater) {
                        ForEach(theaters, id: \.self) { Text($0) }
                    }
                    .frame(width: 180)
                    
                    Picker("Quarter", selection: $selectedQuarter) {
                        ForEach(quarters, id: \.self) { Text($0) }
                    }
                    .frame(width: 120)
                }
                .padding(.horizontal)
                
                HStack(spacing: 20) {
                    SummaryStatCard(
                        title: "Total Requests",
                        value: "\(filteredRequests.count)",
                        subtitle: "In selection"
                    )
                    
                    SummaryStatCard(
                        title: "Total Requested",
                        value: formatCurrency(filteredRequests.compactMap { $0.requestedAmount }.reduce(0, +)),
                        subtitle: "Investment amount"
                    )
                    
                    SummaryStatCard(
                        title: "Approved",
                        value: formatCurrency(filteredRequests.filter { $0.status == "FINAL_APPROVED" }.compactMap { $0.requestedAmount }.reduce(0, +)),
                        subtitle: "Final approved"
                    )
                    
                    SummaryStatCard(
                        title: "Pending",
                        value: formatCurrency(filteredRequests.filter { ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains($0.status) }.compactMap { $0.requestedAmount }.reduce(0, +)),
                        subtitle: "In approval chain"
                    )
                }
                .padding(.horizontal)
                
                Divider()
                
                HStack(alignment: .top, spacing: 20) {
                    GroupBox("By Status") {
                        if requestsByStatus.isEmpty {
                            Text("No data")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(requestsByStatus, id: \.0) { item in
                                    ReportRow(
                                        label: statusDisplayName(item.0),
                                        count: item.1,
                                        amount: item.2,
                                        color: statusColor(item.0)
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(minWidth: 250)
                    
                    GroupBox("By Theater") {
                        if requestsByTheater.isEmpty {
                            Text("No data")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(requestsByTheater, id: \.0) { item in
                                    ReportRow(
                                        label: item.0,
                                        count: item.1,
                                        amount: item.2,
                                        color: .blue
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(minWidth: 250)
                    
                    GroupBox("By Quarter") {
                        if requestsByQuarter.isEmpty {
                            Text("No data")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(requestsByQuarter, id: \.0) { item in
                                    ReportRow(
                                        label: item.0,
                                        count: item.1,
                                        amount: item.2,
                                        color: .purple
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(minWidth: 250)
                }
                .padding(.horizontal)
                
                Divider()
                
                GroupBox("Approval Pipeline") {
                    ApprovalPipelineView(requests: filteredRequests)
                        .padding()
                }
                .padding(.horizontal)
                
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

struct SummaryStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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
    
    private var stages: [(String, Int)] {
        [
            ("Draft", requests.filter { $0.status == "DRAFT" }.count),
            ("Submitted", requests.filter { $0.status == "SUBMITTED" }.count),
            ("DM Review", requests.filter { $0.status == "DM_APPROVED" }.count),
            ("RD Review", requests.filter { $0.status == "RD_APPROVED" }.count),
            ("AVP Review", requests.filter { $0.status == "AVP_APPROVED" }.count),
            ("Approved", requests.filter { $0.status == "FINAL_APPROVED" }.count)
        ]
    }
    
    private var maxCount: Int {
        stages.map { $0.1 }.max() ?? 1
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(stages, id: \.0) { stage in
                VStack(spacing: 4) {
                    Text("\(stage.1)")
                        .font(.headline)
                    
                    Rectangle()
                        .fill(colorForStage(stage.0))
                        .frame(width: 60, height: CGFloat(stage.1) / CGFloat(max(maxCount, 1)) * 150)
                        .frame(minHeight: stage.1 > 0 ? 20 : 4)
                    
                    Text(stage.0)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
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
