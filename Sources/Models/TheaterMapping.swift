import Foundation

enum TheaterMapping {
    static let regionToPortfolio: [String: String] = [
        "CME": "TMT",
        "TMT": "TMT",
        "RetailCG": "RCG",
    ]

    static func portfolioName(forRegion region: String) -> String {
        regionToPortfolio[region] ?? region
    }

    static let industrySegments: [String] = [
        "TMT",
        "FSI",
        "FSIGlobals",
        "HCLS",
        "MFG",
        "RCG"
    ]

    static let portfoliosByTheater: [String: [String]] = [
        "USMajors": industrySegments,
        "USPubSec": ["Federal", "SLED"]
    ]

    static let allTheaters: [String] = ["All", "USMajors", "USPubSec", "AMSExpansion", "AMSAcquisition", "EMEA", "APJ"]
}
