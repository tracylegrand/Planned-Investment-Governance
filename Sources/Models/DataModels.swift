import Foundation

struct CacheProgress {
    var status: String = "idle"
    var currentStep: String = ""
    var stepsCompleted: Int = 0
    var totalSteps: Int = 4
    var message: String = ""
}

struct User: Codable, Identifiable {
    let userId: Int
    let snowflakeUsername: String
    let displayName: String
    let title: String?
    let role: String?
    let theater: String?
    let industrySegment: String?
    let managerId: Int?
    let managerName: String?
    let approvalLevel: Int?
    let isFinalApprover: Bool
    
    var id: Int { userId }
    
    enum CodingKeys: String, CodingKey {
        case userId = "USER_ID"
        case snowflakeUsername = "SNOWFLAKE_USERNAME"
        case displayName = "DISPLAY_NAME"
        case title = "TITLE"
        case role = "ROLE"
        case theater = "THEATER"
        case industrySegment = "INDUSTRY_SEGMENT"
        case managerId = "MANAGER_ID"
        case managerName = "MANAGER_NAME"
        case approvalLevel = "APPROVAL_LEVEL"
        case isFinalApprover = "IS_FINAL_APPROVER"
    }
}

struct InvestmentRequest: Codable, Identifiable {
    let requestId: Int
    let requestTitle: String
    let accountId: String?
    let accountName: String?
    let investmentType: String?
    let requestedAmount: Double?
    let investmentQuarter: String?
    let businessJustification: String?
    let expectedOutcome: String?
    let riskAssessment: String?
    let createdBy: String?
    let createdByName: String?
    let createdByEmployeeId: Int?
    let createdAt: Date?
    let theater: String?
    let industrySegment: String?
    let status: String
    let currentApprovalLevel: Int?
    let nextApproverId: Int?
    let nextApproverName: String?
    let nextApproverTitle: String?
    let dmApprovedBy: String?
    let dmApprovedByTitle: String?
    let dmApprovedAt: Date?
    let dmComments: String?
    let rdApprovedBy: String?
    let rdApprovedByTitle: String?
    let rdApprovedAt: Date?
    let rdComments: String?
    let avpApprovedBy: String?
    let avpApprovedByTitle: String?
    let avpApprovedAt: Date?
    let avpComments: String?
    let gvpApprovedBy: String?
    let gvpApprovedByTitle: String?
    let gvpApprovedAt: Date?
    let gvpComments: String?
    let updatedAt: Date?
    
    var id: Int { requestId }
    
    var isEditable: Bool { status == "DRAFT" }
    var isFinalApproved: Bool { status == "FINAL_APPROVED" }
    var canWithdraw: Bool { ["SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"].contains(status) }
    
    var statusDisplayName: String {
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
    
    var formattedAmount: String {
        guard let amount = requestedAmount else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "—"
    }
    
    enum CodingKeys: String, CodingKey {
        case requestId = "REQUEST_ID"
        case requestTitle = "REQUEST_TITLE"
        case accountId = "ACCOUNT_ID"
        case accountName = "ACCOUNT_NAME"
        case investmentType = "INVESTMENT_TYPE"
        case requestedAmount = "REQUESTED_AMOUNT"
        case investmentQuarter = "INVESTMENT_QUARTER"
        case businessJustification = "BUSINESS_JUSTIFICATION"
        case expectedOutcome = "EXPECTED_OUTCOME"
        case riskAssessment = "RISK_ASSESSMENT"
        case createdBy = "CREATED_BY"
        case createdByName = "CREATED_BY_NAME"
        case createdByEmployeeId = "CREATED_BY_EMPLOYEE_ID"
        case createdAt = "CREATED_AT"
        case theater = "THEATER"
        case industrySegment = "INDUSTRY_SEGMENT"
        case status = "STATUS"
        case currentApprovalLevel = "CURRENT_APPROVAL_LEVEL"
        case nextApproverId = "NEXT_APPROVER_ID"
        case nextApproverName = "NEXT_APPROVER_NAME"
        case nextApproverTitle = "NEXT_APPROVER_TITLE"
        case dmApprovedBy = "DM_APPROVED_BY"
        case dmApprovedByTitle = "DM_APPROVED_BY_TITLE"
        case dmApprovedAt = "DM_APPROVED_AT"
        case dmComments = "DM_COMMENTS"
        case rdApprovedBy = "RD_APPROVED_BY"
        case rdApprovedByTitle = "RD_APPROVED_BY_TITLE"
        case rdApprovedAt = "RD_APPROVED_AT"
        case rdComments = "RD_COMMENTS"
        case avpApprovedBy = "AVP_APPROVED_BY"
        case avpApprovedByTitle = "AVP_APPROVED_BY_TITLE"
        case avpApprovedAt = "AVP_APPROVED_AT"
        case avpComments = "AVP_COMMENTS"
        case gvpApprovedBy = "GVP_APPROVED_BY"
        case gvpApprovedByTitle = "GVP_APPROVED_BY_TITLE"
        case gvpApprovedAt = "GVP_APPROVED_AT"
        case gvpComments = "GVP_COMMENTS"
        case updatedAt = "UPDATED_AT"
    }
}

struct LinkedOpportunity: Codable, Identifiable {
    let linkId: Int
    let requestId: Int
    let opportunityId: String
    let linkedBy: String?
    let linkedAt: Date?
    
    var id: Int { linkId }
    
    enum CodingKeys: String, CodingKey {
        case linkId = "LINK_ID"
        case requestId = "REQUEST_ID"
        case opportunityId = "OPPORTUNITY_ID"
        case linkedBy = "LINKED_BY"
        case linkedAt = "LINKED_AT"
    }
}

struct SuggestedChange: Codable, Identifiable {
    let suggestionId: Int
    let requestId: Int
    let fieldName: String?
    let suggestedValue: String?
    let reason: String?
    let suggestedBy: String?
    let suggestedAt: Date?
    let status: String?
    let reviewedBy: String?
    let reviewedAt: Date?
    
    var id: Int { suggestionId }
    
    enum CodingKeys: String, CodingKey {
        case suggestionId = "SUGGESTION_ID"
        case requestId = "REQUEST_ID"
        case fieldName = "FIELD_NAME"
        case suggestedValue = "SUGGESTED_VALUE"
        case reason = "REASON"
        case suggestedBy = "SUGGESTED_BY"
        case suggestedAt = "SUGGESTED_AT"
        case status = "STATUS"
        case reviewedBy = "REVIEWED_BY"
        case reviewedAt = "REVIEWED_AT"
    }
}

struct SFDCAccount: Codable, Identifiable, Hashable {
    let accountId: String
    let accountName: String
    let theater: String?
    let industrySegment: String?
    
    var id: String { accountId }
    
    enum CodingKeys: String, CodingKey {
        case accountId = "ACCOUNT_ID"
        case accountName = "ACCOUNT_NAME"
        case theater = "THEATER"
        case industrySegment = "INDUSTRY_SEGMENT"
    }
}

struct SFDCOpportunity: Codable, Identifiable, Hashable {
    let opportunityId: String
    let opportunityName: String
    let accountId: String?
    let accountName: String?
    let stage: String?
    let amount: Double?
    let closeDate: Date?
    let ownerName: String?
    
    var id: String { opportunityId }
    
    var formattedAmount: String {
        guard let amount = amount else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "—"
    }
    
    enum CodingKeys: String, CodingKey {
        case opportunityId = "OPPORTUNITY_ID"
        case opportunityName = "OPPORTUNITY_NAME"
        case accountId = "ACCOUNT_ID"
        case accountName = "ACCOUNT_NAME"
        case stage = "STAGE"
        case amount = "AMOUNT"
        case closeDate = "CLOSE_DATE"
        case ownerName = "OWNER_NAME"
    }
}

struct RequestContributor: Codable, Identifiable {
    let contributorId: Int
    let requestId: Int
    let contributorUsername: String?
    let contributorName: String?
    let canEdit: Bool
    let addedBy: String?
    let addedAt: Date?
    
    var id: Int { contributorId }
    
    enum CodingKeys: String, CodingKey {
        case contributorId = "CONTRIBUTOR_ID"
        case requestId = "REQUEST_ID"
        case contributorUsername = "CONTRIBUTOR_USERNAME"
        case contributorName = "CONTRIBUTOR_NAME"
        case canEdit = "CAN_EDIT"
        case addedBy = "ADDED_BY"
        case addedAt = "ADDED_AT"
    }
}

struct InvestmentSummary: Codable {
    let totalRequests: Int
    let totalDraft: Int
    let totalSubmitted: Int
    let totalApproved: Int
    let totalRejected: Int
    let totalPendingMyApproval: Int
    let totalInvestmentRequested: Double
    let totalInvestmentApproved: Double
    
    enum CodingKeys: String, CodingKey {
        case totalRequests = "TOTAL_REQUESTS"
        case totalDraft = "TOTAL_DRAFT"
        case totalSubmitted = "TOTAL_SUBMITTED"
        case totalApproved = "TOTAL_APPROVED"
        case totalRejected = "TOTAL_REJECTED"
        case totalPendingMyApproval = "TOTAL_PENDING_MY_APPROVAL"
        case totalInvestmentRequested = "TOTAL_INVESTMENT_REQUESTED"
        case totalInvestmentApproved = "TOTAL_INVESTMENT_APPROVED"
    }
}

struct AnnualBudget: Codable, Identifiable {
    let budgetId: Int
    let fiscalYear: String
    let theater: String
    let industrySegment: String
    let portfolio: String?
    let budgetAmount: Double
    let allocatedAmount: Double
    let q1Budget: Double
    let q2Budget: Double
    let q3Budget: Double
    let q4Budget: Double
    
    var id: Int { budgetId }
    
    enum CodingKeys: String, CodingKey {
        case budgetId = "BUDGET_ID"
        case fiscalYear = "FISCAL_YEAR"
        case theater = "THEATER"
        case industrySegment = "INDUSTRY_SEGMENT"
        case portfolio = "PORTFOLIO"
        case budgetAmount = "BUDGET_AMOUNT"
        case allocatedAmount = "ALLOCATED_AMOUNT"
        case q1Budget = "Q1_BUDGET"
        case q2Budget = "Q2_BUDGET"
        case q3Budget = "Q3_BUDGET"
        case q4Budget = "Q4_BUDGET"
    }
}

class NavigationState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var selectedRequestId: Int? = nil
    @Published var showingRequestDetail: Bool = false
    @Published var showingNewRequest: Bool = false
    @Published var filterPendingMyApproval: Bool = false
    @Published var passedStatus: String = ""
    @Published var passedFiscalYear: String = ""
}
