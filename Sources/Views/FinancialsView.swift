import SwiftUI

struct QuarterlyData {
    var approved: Double = 0
    var budget: Double = 0
    var remaining: Double { budget - approved }
}

struct FinancialRow: Identifiable {
    let id = UUID()
    let isTheater: Bool
    let name: String
    var q1: QuarterlyData
    var q2: QuarterlyData
    var q3: QuarterlyData
    var q4: QuarterlyData
    var fyTotal: QuarterlyData {
        QuarterlyData(approved: q1.approved + q2.approved + q3.approved + q4.approved,
                      budget: q1.budget + q2.budget + q3.budget + q4.budget)
    }
}

struct FinancialsView: View {
    @ObservedObject var navigationState: NavigationState
    @ObservedObject var userSettings = UserSettings.shared
    @EnvironmentObject var dataService: DataService

    private var currentFY: Int {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        return month >= 2 ? year + 1 : year
    }

    private var fiscalYears: [String] {
        let curr = "FY\(currentFY)"
        if userSettings.showPriorYear {
            return [curr, "FY\(currentFY - 1)"]
        }
        return [curr]
    }

    private func dataForYear(_ fy: String) -> [FinancialRow] {
        let approvedRequests = dataService.investmentRequests.filter { $0.status == "FINAL_APPROVED" }
        let budgetsForYear = dataService.annualBudgets.filter { $0.fiscalYear == fy }

        let allTheaters = Set(budgetsForYear.map { TheaterMapping.normalizeTheater($0.theater) }).sorted()

        var rows: [FinancialRow] = []
        for theater in allTheaters {
            let dbCodes = TheaterMapping.dbCodes(forDisplayName: theater)
            let theaterBudgets = budgetsForYear.filter { TheaterMapping.normalizeTheater($0.theater) == theater }
            let allIndustries = Set(theaterBudgets.map { $0.industrySegment }).sorted()

            guard !allIndustries.isEmpty else { continue }

            var theaterRow = FinancialRow(isTheater: true, name: theater, q1: QuarterlyData(), q2: QuarterlyData(), q3: QuarterlyData(), q4: QuarterlyData())

            var industryRows: [FinancialRow] = []
            for industry in allIndustries {
                let budgets = theaterBudgets.filter { $0.industrySegment == industry }
                let q1b = budgets.map { $0.q1Budget }.reduce(0, +)
                let q2b = budgets.map { $0.q2Budget }.reduce(0, +)
                let q3b = budgets.map { $0.q3Budget }.reduce(0, +)
                let q4b = budgets.map { $0.q4Budget }.reduce(0, +)

                let indRequests = approvedRequests.filter { dbCodes.contains($0.theater ?? "") && $0.industrySegment == industry }
                let q1a = indRequests.filter { $0.investmentQuarter == "\(fy)-Q1" }.compactMap { $0.requestedAmount }.reduce(0, +)
                let q2a = indRequests.filter { $0.investmentQuarter == "\(fy)-Q2" }.compactMap { $0.requestedAmount }.reduce(0, +)
                let q3a = indRequests.filter { $0.investmentQuarter == "\(fy)-Q3" }.compactMap { $0.requestedAmount }.reduce(0, +)
                let q4a = indRequests.filter { $0.investmentQuarter == "\(fy)-Q4" }.compactMap { $0.requestedAmount }.reduce(0, +)

                let row = FinancialRow(isTheater: false, name: industry,
                                       q1: QuarterlyData(approved: q1a, budget: q1b),
                                       q2: QuarterlyData(approved: q2a, budget: q2b),
                                       q3: QuarterlyData(approved: q3a, budget: q3b),
                                       q4: QuarterlyData(approved: q4a, budget: q4b))
                industryRows.append(row)

                theaterRow.q1.approved += q1a; theaterRow.q1.budget += q1b
                theaterRow.q2.approved += q2a; theaterRow.q2.budget += q2b
                theaterRow.q3.approved += q3a; theaterRow.q3.budget += q3b
                theaterRow.q4.approved += q4a; theaterRow.q4.budget += q4b
            }

            rows.append(theaterRow)
            rows.append(contentsOf: industryRows)
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Financials")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(fiscalYears, id: \.self) { fy in
                        let rows = dataForYear(fy)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Approved vs Budget — \(fy)")
                                .font(.title2)
                                .fontWeight(.bold)

                            GroupBox {
                                if rows.isEmpty {
                                    Text("No data for \(fy)")
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding()
                                } else {
                                    QuarterlyFinancialTable(rows: rows, fiscalYear: fy)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.vertical)
            }
        }
    }
}

struct QuarterlyFinancialTable: View {
    let rows: [FinancialRow]
    let fiscalYear: String

    private let nameWidth: CGFloat = 220
    private let colWidth: CGFloat = 100
    private let colSpacing: CGFloat = 2

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return "$\(formatter.string(from: NSNumber(value: amount)) ?? "0")"
    }

    private func formatRemaining(_ amount: Double) -> (text: String, isNegative: Bool) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        if amount < 0 {
            return ("<$\(formatter.string(from: NSNumber(value: abs(amount))) ?? "0")>", true)
        }
        return ("$\(formatter.string(from: NSNumber(value: amount)) ?? "0")", false)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Theater / Industry")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(width: nameWidth, alignment: .leading)

                    ForEach(["Q1", "Q2", "Q3", "Q4", "FY Total"], id: \.self) { label in
                        VStack(spacing: 2) {
                            Text(label)
                                .font(.caption)
                                .fontWeight(.bold)
                            HStack(spacing: colSpacing) {
                                Text("Appr.")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .frame(width: colWidth, alignment: .trailing)
                                Text("Budg.")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .frame(width: colWidth, alignment: .trailing)
                                Text("Rem.")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .frame(width: colWidth, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.bottom, 6)

                Divider().padding(.bottom, 4)

                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        HStack(spacing: 0) {
                            if !row.isTheater {
                                Spacer().frame(width: 16)
                            }
                            Text(row.name)
                                .font(row.isTheater ? .subheadline : .caption)
                                .fontWeight(row.isTheater ? .bold : .regular)
                                .lineLimit(1)
                        }
                        .frame(width: nameWidth, alignment: .leading)

                        ForEach(Array(zip(["Q1","Q2","Q3","Q4","FYT"], [row.q1, row.q2, row.q3, row.q4, row.fyTotal])), id: \.0) { _, qd in
                            let rem = formatRemaining(qd.remaining)
                            HStack(spacing: colSpacing) {
                                Text(formatCurrency(qd.approved))
                                    .frame(width: colWidth, alignment: .trailing)
                                Text(formatCurrency(qd.budget))
                                    .frame(width: colWidth, alignment: .trailing)
                                Text(rem.text)
                                    .foregroundColor(rem.isNegative ? .red : .primary)
                                    .frame(width: colWidth, alignment: .trailing)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.vertical, row.isTheater ? 4 : 2)
                    .background(row.isTheater ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}
