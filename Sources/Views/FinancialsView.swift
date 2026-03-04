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

    @State private var selectedTheater: String = "All"
    @State private var selectedIndustries: Set<String> = []
    @State private var showIndustryPicker = false

    private var theaters: [String] {
        ["All"] + dataService.sfdcTheaters
    }

    private var portfoliosByTheater: [String: [String]] {
        dataService.sfdcIndustriesByTheater
    }

    private var availablePortfolios: [String] {
        if selectedTheater == "All" {
            return Array(Set(portfoliosByTheater.values.flatMap { $0 })).sorted()
        }
        return portfoliosByTheater[selectedTheater] ?? []
    }

    private var hasActiveFilters: Bool {
        selectedTheater != "All" || !selectedIndustries.isEmpty
    }

    private func clearAllFilters() {
        selectedTheater = "All"
        selectedIndustries = []
    }

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

        let fyQuarters = (1...4).map { "\(fy)-Q\($0)" }
        let fyApproved = approvedRequests.filter { fyQuarters.contains($0.investmentQuarter ?? "") }

        var theaterIndustries: [String: Set<String>] = [:]
        for b in budgetsForYear {
            let t = TheaterMapping.normalizeTheater(b.theater)
            theaterIndustries[t, default: []].insert(b.industrySegment)
        }
        for r in fyApproved {
            let t = TheaterMapping.normalizeTheater(r.theater ?? "")
            if !t.isEmpty {
                let ind = r.industrySegment ?? ""
                theaterIndustries[t, default: []].insert(ind)
            }
        }

        for t in theaterIndustries.keys {
            for seg in (dataService.sfdcIndustriesByTheater[t] ?? []) {
                theaterIndustries[t, default: []].insert(seg)
            }
        }

        var allTheaters = theaterIndustries.keys.sorted()
        if selectedTheater != "All" {
            allTheaters = allTheaters.filter { $0 == selectedTheater }
        }

        var rows: [FinancialRow] = []
        for theater in allTheaters {
            let dbCodes = TheaterMapping.dbCodes(forDisplayName: theater)
            let theaterBudgets = budgetsForYear.filter { TheaterMapping.normalizeTheater($0.theater) == theater }
            var allIndustries = (theaterIndustries[theater] ?? []).sorted()
            if !selectedIndustries.isEmpty {
                allIndustries = allIndustries.filter { selectedIndustries.contains($0) }
            }

            guard !allIndustries.isEmpty else { continue }

            var theaterRow = FinancialRow(isTheater: true, name: theater, q1: QuarterlyData(), q2: QuarterlyData(), q3: QuarterlyData(), q4: QuarterlyData())

            var industryRows: [FinancialRow] = []
            for industry in allIndustries {
                let budgets = theaterBudgets.filter { $0.industrySegment == industry }
                let q1b = budgets.map { $0.q1Budget }.reduce(0, +)
                let q2b = budgets.map { $0.q2Budget }.reduce(0, +)
                let q3b = budgets.map { $0.q3Budget }.reduce(0, +)
                let q4b = budgets.map { $0.q4Budget }.reduce(0, +)

                let indRequests: [InvestmentRequest]
                indRequests = approvedRequests.filter { dbCodes.contains($0.theater ?? "") && $0.industrySegment == industry }
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

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Theater").font(.caption).foregroundColor(.secondary)
                    Picker("Theater", selection: $selectedTheater) {
                        ForEach(theaters, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Region").font(.caption).foregroundColor(.secondary)
                    Button {
                        showIndustryPicker.toggle()
                    } label: {
                        HStack {
                            Text(selectedIndustries.isEmpty ? "All Regions" : "\(selectedIndustries.count) Selected")
                            Image(systemName: "chevron.down")
                        }
                        .frame(width: 140)
                    }
                    .disabled(availablePortfolios.isEmpty)
                }
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(" ").font(.caption)
                    Button(action: clearAllFilters) {
                        Text("Clear")
                    }
                    .disabled(!hasActiveFilters)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom)

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
        .onChange(of: selectedTheater) { _ in
            selectedIndustries = []
        }
    }
}

struct QuarterlyFinancialTable: View {
    let rows: [FinancialRow]
    let fiscalYear: String

    private let nameWidth: CGFloat = 240
    private let colWidth: CGFloat = 110
    private let colSpacing: CGFloat = 4
    private let barHeight: CGFloat = 22

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

    private func maxBudget() -> Double {
        rows.filter { $0.isTheater }.map { max($0.fyTotal.budget, $0.fyTotal.approved) }.max() ?? 1
    }

    private func barWidth(amount: Double, maxVal: Double) -> CGFloat {
        guard maxVal > 0 else { return 0 }
        return CGFloat(min(amount / maxVal, 1.0)) * (colWidth - 4)
    }

    @ViewBuilder
    private func barCell(amount: Double, color: Color, maxVal: Double, text: String, isBold: Bool) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.2))
                    .frame(width: barWidth(amount: abs(amount), maxVal: maxVal), height: barHeight)
                Spacer(minLength: 0)
            }
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(isBold ? .bold : .regular)
                .padding(.trailing, 2)
        }
        .frame(width: colWidth, height: barHeight)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Theater / Region")
                    .font(.headline)
                    .fontWeight(.bold)
                    .frame(height: 40, alignment: .bottomLeading)
                    .padding(.bottom, 6)

                Divider().padding(.bottom, 4)

                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        if !row.isTheater {
                            Spacer().frame(width: 20)
                        }
                        Text(row.name)
                            .font(row.isTheater ? .body : .callout)
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .lineLimit(1)
                    }
                    .frame(width: nameWidth, height: barHeight, alignment: .leading)
                    .padding(.vertical, row.isTheater ? 4 : 2)
                    .background(row.isTheater ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
                }
            }
            .frame(width: nameWidth)
            .padding(.leading, 8)

            Divider()

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(["Q1", "Q2", "Q3", "Q4", "FY Total"], id: \.self) { label in
                            VStack(spacing: 2) {
                                Text(label)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                HStack(spacing: colSpacing) {
                                    Text("Approved for IC")
                                        .frame(width: colWidth, alignment: .trailing)
                                    Text("Budget")
                                        .frame(width: colWidth, alignment: .trailing)
                                    Text("Remaining")
                                        .frame(width: colWidth, alignment: .trailing)
                                }
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
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

                    let globalMax = maxBudget()

                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            ForEach(Array(zip(["Q1","Q2","Q3","Q4","FYT"], [row.q1, row.q2, row.q3, row.q4, row.fyTotal])), id: \.0) { _, qd in
                                let rem = formatRemaining(qd.remaining)
                                HStack(spacing: colSpacing) {
                                    barCell(amount: qd.approved, color: .green, maxVal: globalMax, text: formatCurrency(qd.approved), isBold: row.isTheater)
                                    barCell(amount: qd.budget, color: .blue, maxVal: globalMax, text: formatCurrency(qd.budget), isBold: row.isTheater)
                                    barCell(amount: abs(qd.remaining), color: rem.isNegative ? .red : .green, maxVal: globalMax, text: rem.text, isBold: row.isTheater)
                                        .foregroundColor(rem.isNegative ? .red : .primary)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(.vertical, row.isTheater ? 4 : 2)
                        .background(row.isTheater ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
    }
}
