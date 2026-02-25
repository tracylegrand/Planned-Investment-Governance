# Financials Tab Implementation Plan

## Overview
Create a new "Financials" tab in the application that consolidates financial reporting. Move the "Totals by Theater/Industry (Approved)" table from the Dashboard into this new tab with enhanced formatting.

## Requirements

### 1. Create New FinancialsView.swift
- New SwiftUI view file at `Sources/Views/FinancialsView.swift`
- Tab icon: `dollarsign.circle.fill` or similar finance icon
- Tab label: "Financials"

### 2. Move Theater/Industry Table
- Extract `TheaterIndustryTableView` from DashboardView.swift
- Move to FinancialsView or keep as shared component
- Remove from Dashboard (Section 3)

### 3. Enhanced Currency Formatting
Current formatting uses abbreviations (M, K):
```swift
if amount >= 1_000_000 {
    return String(format: "%.1fM", amount / 1_000_000)
} else if amount >= 1_000 {
    return String(format: "%.1fK", amount / 1_000)
}
```

New formatting should show full dollar amounts:
```swift
func formatFullCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencySymbol = "$"
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: amount)) ?? "$0"
}
```

### 4. Accounting-Style Negative Numbers
For negative Remaining amounts, use accounting notation with angle brackets:
- Current: Shows "0" in red when negative
- New: Show `<$50,000>` in red for -$50,000

```swift
func formatRemainingAmount(_ amount: Double) -> String {
    if amount < 0 {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let absAmount = formatter.string(from: NSNumber(value: abs(amount))) ?? "0"
        return "<$\(absAmount)>"
    } else {
        return formatFullCurrency(amount)
    }
}
```

### 5. Column Width Adjustments
Expand column widths to accommodate full dollar amounts:

| Column | Current Width | New Width |
|--------|---------------|-----------|
| # (Count) | 40 | 40 (unchanged) |
| Approved | 85 | 120 |
| Budget | 85 | 120 |
| Remaining | 90 | 130 |
| Theater/Industry | 240 | 240 (unchanged) |

### 6. Update ContentView.swift
Add new tab to TabView:
```swift
TabView(selection: $navigationState.selectedTab) {
    DashboardView(navigationState: navigationState)
        .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
        .tag(0)
    
    InvestmentRequestsView(navigationState: navigationState)
        .tabItem { Label("Requests", systemImage: "list.bullet.rectangle.fill") }
        .tag(1)
    
    FinancialsView(navigationState: navigationState)
        .tabItem { Label("Financials", systemImage: "dollarsign.circle.fill") }
        .tag(2)
}
```

## Files to Modify

1. **Create**: `Sources/Views/FinancialsView.swift`
   - New view with Theater/Industry table
   - Full currency formatting
   - Accounting-style negative numbers

2. **Modify**: `Sources/Views/DashboardView.swift`
   - Remove Section 3 (Totals by Theater/Industry)
   - Remove or keep `TheaterIndustryTableView` (may be shared)

3. **Modify**: `Sources/Views/ContentView.swift`
   - Add Financials tab to TabView

## Data Requirements
The FinancialsView needs access to:
- `dataService.investmentRequests` - for calculating approved amounts
- `dataService.annualBudgets` - for budget amounts
- Same filtering logic as Dashboard (theater, industry, quarter filters)

## UI Layout for FinancialsView

```
┌─────────────────────────────────────────────────────────────────────┐
│  Financials                                                          │
├─────────────────────────────────────────────────────────────────────┤
│  [Filter Bar: Theater | Industries | Quarters | Status]              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Totals by Theater/Industry (Approved)                               │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ Theater/Industry  │    Full Year 2026      │    Full Year 2027  ││
│  │                   │ # | Approved|Budget|Rem│ # |Approved|Budget|R││
│  ├───────────────────┼────────────────────────┼────────────────────┤│
│  │ USMajors          │25 |$29,084,755|$30,000,000|$915,245│...     ││
│  │   Financial Svcs  │10 |$12,500,000|$15,000,000|$2,500,000│       ││
│  │   HCLS            │ 8 |$10,000,000|$8,000,000|<$2,000,000>│      ││
│  │   ...             │   │                      │                   ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Example Remaining Amount Display

| Scenario | Amount | Display |
|----------|--------|---------|
| Positive | $2,500,000 | $2,500,000 (black) |
| Zero | $0 | $0 (black) |
| Negative | -$500,000 | <$500,000> (red) |
| Negative | -$2,345,678 | <$2,345,678> (red) |

## Implementation Steps

1. Create `FinancialsView.swift` with basic structure
2. Copy filter bar logic from DashboardView
3. Copy `requestsByTheaterAndIndustry` computed property
4. Create new `FinancialTableView` with:
   - Full currency formatting (no M/K abbreviations)
   - Accounting-style negative numbers
   - Expanded column widths
5. Update ContentView to add Financials tab
6. Remove Section 3 from DashboardView
7. Build and test
