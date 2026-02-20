// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlannedInvestmentGovernance",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PlannedInvestmentGovernance",
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
