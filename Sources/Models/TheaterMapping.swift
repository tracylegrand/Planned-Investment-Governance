import Foundation

enum TheaterMapping {
    static let displayToDbCodes: [String: [String]] = [
        "US Majors": ["USMajors"],
        "US Public Sector": ["USPubSec"],
        "Americas Enterprise": ["AMSExpansion", "AMSPartner"],
        "Americas Acquisition": ["AMSAcquisition"],
        "EMEA": ["EMEA"],
        "APJ": ["APJ"]
    ]

    static let dbCodeToDisplay: [String: String] = {
        var map: [String: String] = [:]
        for (display, codes) in displayToDbCodes {
            for code in codes {
                map[code] = display
            }
        }
        return map
    }()

    static let budgetTheaterToDisplay: [String: String] = [
        "US Majors": "US Majors"
    ]

    static func displayName(forDbCode code: String) -> String {
        dbCodeToDisplay[code] ?? code
    }

    static func dbCodes(forDisplayName display: String) -> [String] {
        displayToDbCodes[display] ?? [display]
    }

    static func normalizeTheater(_ rawTheater: String) -> String {
        if let display = dbCodeToDisplay[rawTheater] {
            return display
        }
        return rawTheater
    }

    static let industrySegments: [String] = [
        "CME (TMT)",
        "FSI",
        "FSIGlobals",
        "HCLS",
        "MFG",
        "RCG"
    ]

    static let portfoliosByTheater: [String: [String]] = [
        "US Majors": industrySegments,
        "US Public Sector": ["Federal", "SLED"]
    ]

    static let allTheaters: [String] = ["All", "US Majors", "US Public Sector", "Americas Enterprise", "Americas Acquisition", "EMEA", "APJ"]
}
