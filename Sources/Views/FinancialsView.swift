import SwiftUI

struct FinancialsView: View {
    @ObservedObject var navigationState: NavigationState
    @EnvironmentObject var dataService: DataService
    
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
        let years = fiscalYears
        let prevYear = years[0]
        let currYear = years[1]
        let approvedRequests = dataService.investmentRequests.filter { $0.status == "FINAL_APPROVED" }
        
        let theatersFromBudgets = Set(dataService.annualBudgets.map { $0.theater })
        let theatersFromRequests = Set(approvedRequests.compactMap { $0.theater })
        let allTheaters = theatersFromBudgets.union(theatersFromRequests).sorted()
        
        return allTheaters.compactMap { theater in
            let industriesFromBudgets = Set(dataService.annualBudgets.filter { $0.theater == theater }.map { $0.industrySegment })
            let industriesFromRequests = Set(approvedRequests.filter { $0.theater == theater }.compactMap { $0.industrySegment })
            let allIndustries = industriesFromBudgets.union(industriesFromRequests).sorted()
            
            guard !allIndustries.isEmpty else { return nil }
            
            let industries = allIndustries.map { industry -> (industry: String, prevCount: Int, prevAmount: Double, currCount: Int, currAmount: Double, prevBudget: Double, currBudget: Double) in
                let industryRequests = approvedRequests.filter { $0.theater == theater && $0.industrySegment == industry }
                let prevRequests = industryRequests.filter { $0.investmentQuarter?.hasPrefix(prevYear) == true }
                let currRequests = industryRequests.filter { $0.investmentQuarter?.hasPrefix(currYear) == true }
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
            }
            
            return (theater: theater, industries: industries)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Financials")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Totals by Theater/Industry (Approved)")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    GroupBox {
                        if requestsByTheaterAndIndustry.isEmpty {
                            Text("No approved requests found")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            FinancialTableView(
                                data: requestsByTheaterAndIndustry,
                                prevYear: fiscalYears[0],
                                currYear: fiscalYears[1]
                            )
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.vertical)
        }
    }
}

struct FinancialTableView: View {
    let data: [(theater: String, industries: [(industry: String, prevCount: Int, prevAmount: Double, currCount: Int, currAmount: Double, prevBudget: Double, currBudget: Double)])]
    let prevYear: String
    let currYear: String
    
    private func formatFullCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "$\(formatted)"
    }
    
    private func formatRemainingAmount(_ amount: Double) -> (text: String, isNegative: Bool) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        
        if amount < 0 {
            let absFormatted = formatter.string(from: NSNumber(value: abs(amount))) ?? "0"
            return ("<$\(absFormatted)>", true)
        } else {
            let formatted = formatter.string(from: NSNumber(value: amount)) ?? "0"
            return ("$\(formatted)", false)
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
                    Text("Full Year \(String(prevYear.dropFirst(2)))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    HStack(spacing: 14) {
                        Text("#").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 40, alignment: .trailing)
                        Text("Approved").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 120, alignment: .trailing)
                        Text("Budget").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 120, alignment: .trailing)
                        Text("Remaining").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 130, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.3), lineWidth: 1))
                
                VStack(spacing: 4) {
                    Text("Full Year \(String(currYear.dropFirst(2)))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    HStack(spacing: 14) {
                        Text("#").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 40, alignment: .trailing)
                        Text("Approved").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 120, alignment: .trailing)
                        Text("Budget").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 120, alignment: .trailing)
                        Text("Remaining").font(.headline).fontWeight(.semibold).foregroundColor(.black).frame(width: 130, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.3), lineWidth: 1))
            }
            .padding(.bottom, 10)
            
            Divider().padding(.bottom, 8)
            
            ForEach(Array(flattenedRows.enumerated()), id: \.offset) { index, row in
                let prevRemaining = formatRemainingAmount(row.prevBudget - row.prevAmount)
                let currRemaining = formatRemainingAmount(row.currBudget - row.currAmount)
                
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
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(.black)
                            .frame(width: 40, alignment: .trailing)
                        Text(formatFullCurrency(row.prevAmount))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(.black)
                            .frame(width: 120, alignment: .trailing)
                        Text(formatFullCurrency(row.prevBudget))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(.black)
                            .frame(width: 120, alignment: .trailing)
                        Text(prevRemaining.text)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(prevRemaining.isNegative ? .red : .black)
                            .frame(width: 130, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    
                    HStack(spacing: 14) {
                        Text("\(row.currCount)")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(.black)
                            .frame(width: 40, alignment: .trailing)
                        Text(formatFullCurrency(row.currAmount))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(.black)
                            .frame(width: 120, alignment: .trailing)
                        Text(formatFullCurrency(row.currBudget))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(.black)
                            .frame(width: 120, alignment: .trailing)
                        Text(currRemaining.text)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(row.isTheater ? .bold : .regular)
                            .foregroundColor(currRemaining.isNegative ? .red : .black)
                            .frame(width: 130, alignment: .trailing)
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
