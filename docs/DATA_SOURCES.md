# Investment Governance - Data Sources

## Overview

The Investment Governance application sources data from three primary systems: Snowflake (persistent storage), Salesforce via Snowflake shared data (account and opportunity data), and Workday via Snowflake HR views (employee identity and org hierarchy). A local SQLite cache provides fast reads for the macOS client.

---

## 1. Snowflake - Primary Data Store

**Account:** `SFCOGSOPS-SNOWHOUSE_AWS_US_WEST_2`
**Database/Schema:** `TEMP.INVESTMENT_GOVERNANCE`
**Owner Role:** `TECHNICAL_ACCOUNT_MANAGER`
**Connection Name:** `DemoAcct` (configured in `config/standard.json`)

### 1.1 INVESTMENT_REQUESTS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | ~232 rows |
| **Primary Key** | `REQUEST_ID` (autoincrement) |
| **Purpose** | Stores all investment requests including status, approval chain fields, business case, and audit trail |

**Key Columns:**
- **Identity:** REQUEST_ID (PK), REQUEST_TITLE, ACCOUNT_ID, ACCOUNT_NAME
- **Request Details:** INVESTMENT_TYPE, REQUESTED_AMOUNT, INVESTMENT_QUARTER, THEATER, INDUSTRY_SEGMENT
- **Business Case:** BUSINESS_JUSTIFICATION, EXPECTED_OUTCOME, RISK_ASSESSMENT (all VARCHAR max)
- **Creator Info:** CREATED_BY (Snowflake username), CREATED_BY_NAME, CREATED_BY_EMPLOYEE_ID, CREATED_AT
- **Status/Approval:** STATUS (default 'DRAFT'), CURRENT_APPROVAL_LEVEL (default 0), NEXT_APPROVER_ID, NEXT_APPROVER_NAME, NEXT_APPROVER_TITLE
- **Approval History:** Stored in `APPROVAL_STEPS` table (see 1.9). Legacy per-level columns (DM/RD/AVP/GVP_APPROVED_BY, etc.) remain in Snowflake for backward compatibility but are no longer used in the SQLite cache.
- **Withdrawal:** WITHDRAWN_BY, WITHDRAWN_BY_NAME, WITHDRAWN_AT, WITHDRAWN_COMMENT
- **Submission:** SUBMITTED_COMMENT, SUBMITTED_BY_NAME, SUBMITTED_AT
- **Draft Comments:** DRAFT_COMMENT, DRAFT_BY_NAME, DRAFT_AT

### 1.2 USERS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.USERS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | 2 rows |
| **Primary Key** | `USER_ID` (autoincrement) |
| **Unique Constraint** | `SNOWFLAKE_USERNAME` |
| **Purpose** | Defines application roles, approval levels, and hierarchy for participating users |

**Current Data:**

| USER_ID | SNOWFLAKE_USERNAME | DISPLAY_NAME | TITLE | ROLE | APPROVAL_LEVEL | IS_FINAL_APPROVER |
|---|---|---|---|---|---|---|
| 1 | TLEGRAND | Tracy LeGrand | Account Executive | AE | 1 | false |
| 2 | JON_BEAULIER | Jon Beaulier | GVP of Majors | GVP | 5 | true |

**Key Columns:** SNOWFLAKE_USERNAME, DISPLAY_NAME, TITLE, ROLE, THEATER, INDUSTRY_SEGMENT, MANAGER_ID, MANAGER_NAME, APPROVAL_LEVEL, IS_FINAL_APPROVER

### 1.3 ANNUAL_BUDGETS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.ANNUAL_BUDGETS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | 12 rows |
| **Primary Key** | `BUDGET_ID` (autoincrement) |
| **Unique Constraint** | (`FISCAL_YEAR`, `THEATER`, `INDUSTRY_SEGMENT`, `PORTFOLIO`) |
| **Purpose** | Stores annual and quarterly budget allocations by theater, industry, and portfolio |

**Key Columns:** FISCAL_YEAR, THEATER, INDUSTRY_SEGMENT, PORTFOLIO, BUDGET_AMOUNT, ALLOCATED_AMOUNT, Q1_BUDGET, Q2_BUDGET, Q3_BUDGET, Q4_BUDGET

### 1.4 SFDC_ACCOUNTS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.SFDC_ACCOUNTS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | 75,570 rows |
| **Primary Key** | None (deduplicated by ACCOUNT_NAME via GROUP BY during cache load) |
| **Purpose** | Deduplicated Salesforce account lookup data providing account names, theaters, and industry segments for request creation |

**Columns:** ACCOUNT_NAME, THEATER, INDUSTRY_SEGMENT

**Source Pipeline:** This table is populated from `SNOW_CERTIFIED.PROFESSIONAL_SERVICES.FCT_SALESFORCE_PROFESSIONAL_SERVICES_OPPORTUNITY` (see Section 2). The 75,570 unique account rows are derived from 266,743 SFDC opportunity records via deduplication.

### 1.5 REQUEST_OPPORTUNITIES

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.REQUEST_OPPORTUNITIES` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | 0 rows (reserved for future use) |
| **Primary Key** | `LINK_ID` (autoincrement) |
| **Purpose** | Links investment requests to SFDC opportunity IDs |

**Columns:** LINK_ID, REQUEST_ID, OPPORTUNITY_ID, LINKED_BY, LINKED_AT

### 1.6 REQUEST_CONTRIBUTORS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.REQUEST_CONTRIBUTORS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | 0 rows (reserved for future use) |
| **Primary Key** | `CONTRIBUTOR_ID` (autoincrement) |
| **Purpose** | Tracks additional contributors on a request with edit permissions |

**Columns:** CONTRIBUTOR_ID, REQUEST_ID, CONTRIBUTOR_USERNAME, CONTRIBUTOR_NAME, CAN_EDIT, ADDED_BY, ADDED_AT

### 1.7 SUGGESTED_CHANGES

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.SUGGESTED_CHANGES` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | 0 rows (reserved for future use) |
| **Primary Key** | `SUGGESTION_ID` (autoincrement) |
| **Purpose** | Stores field-level change suggestions from reviewers with review tracking |

**Columns:** SUGGESTION_ID, REQUEST_ID, FIELD_NAME, SUGGESTED_VALUE, REASON, SUGGESTED_BY, SUGGESTED_AT, STATUS (default 'PENDING'), REVIEWED_BY, REVIEWED_AT

### 1.8 APPROVAL_STEPS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Primary Key** | `STEP_ID` (autoincrement) |
| **Purpose** | Single source of truth for all approval history. Each row represents one approval step in the chain for a request. |

**Key Columns:** STEP_ID, REQUEST_ID, STEP_ORDER, APPROVER_EMPLOYEE_ID, APPROVER_NAME, APPROVER_TITLE, STATUS (PENDING/APPROVED), APPROVED_AT, COMMENTS, IS_FINAL_STEP, CREATED_AT

### 1.9 FINAL_APPROVERS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.FINAL_APPROVERS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Primary Key** | `THEATER` |
| **Purpose** | Defines the final approver (GVP-level) for each theater. Used to determine when the approval chain terminates. |

**Key Columns:** THEATER, APPROVER_EMPLOYEE_ID, APPROVER_NAME, APPROVER_TITLE

### 1.10 AUDIT_LOG

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.AUDIT_LOG` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Row Count** | 0 rows (reserved for future use) |
| **Primary Key** | `LOG_ID` (autoincrement) |
| **Purpose** | Intended for recording all state changes with before/after snapshots (VARIANT columns) |

**Columns:** LOG_ID, REQUEST_ID, ACTION, OLD_VALUES (VARIANT), NEW_VALUES (VARIANT), PERFORMED_BY, PERFORMED_AT

---

## 2. Salesforce (via Snowflake Shared Data)

### 2.1 FCT_SALESFORCE_PROFESSIONAL_SERVICES_OPPORTUNITY

| Attribute | Value |
|---|---|
| **Location** | `SNOW_CERTIFIED.PROFESSIONAL_SERVICES.FCT_SALESFORCE_PROFESSIONAL_SERVICES_OPPORTUNITY` |
| **Access Role** | `SNOW_CERTIFIED_PROFESSIONAL_SERVICES_RO_RL` (read-only) |
| **Row Count** | 266,743 rows |
| **Purpose** | Source of truth for Salesforce account and opportunity data |

This is a shared/certified Snowflake data source containing Salesforce Professional Services opportunity records. The application reads from this table to populate `TEMP.INVESTMENT_GOVERNANCE.SFDC_ACCOUNTS` with deduplicated account-level data.

**Data Flow:**
```
SNOW_CERTIFIED.PROFESSIONAL_SERVICES.FCT_SALESFORCE_PROFESSIONAL_SERVICES_OPPORTUNITY
    (266,743 opportunity rows)
        |
        | GROUP BY ACCOUNT_NAME, THEATER, INDUSTRY_SEGMENT
        v
TEMP.INVESTMENT_GOVERNANCE.SFDC_ACCOUNTS
    (75,570 unique account rows)
        |
        | API server cache load on startup
        v
SQLite cached_accounts table
    (local fast-access for account search and theater/industry lookups)
```

---

## 3. Workday (via Snowflake HR Views)

### 3.1 SFDC_WORKDAY_USER_VW

| Attribute | Value |
|---|---|
| **Location** | `HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW` |
| **Access** | Available to `TECHNICAL_ACCOUNT_MANAGER` role |
| **Purpose** | Provides employee identity, title, manager, and cost center for current user session identification |

**Key Columns Used:**
- `EMPLOYEE_ID` - Unique employee identifier
- `PREFERRED_NAME_FIRST_NAME`, `PREFERRED_NAME_LAST_NAME` - Used to derive Snowflake username via `UPPER(CONCAT(LEFT(first, 1), REPLACE(last, ' ', '')))`
- `BUSINESS_TITLE` - Employee's current job title
- `MANAGER_ID`, `MANAGER_NAME` - Direct manager for approval routing
- `COST_CENTER_NAME` - Used as fallback theater when USERS table has no theater set
- `ACTIVE_STATUS` - Must be 1 (active) for the user to be recognized

**Usage:** The `VW_CURRENT_USER_INFO` view joins this Workday view with the application's USERS table to identify the currently logged-in Snowflake user, merging Workday HR data (name, title, manager) with application-specific data (role, approval level, final approver flag).

---

## 4. Snowflake Views

### 4.1 VW_CURRENT_USER_INFO

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.VW_CURRENT_USER_INFO` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Purpose** | Identifies the current Snowflake session user by joining Workday HR data with the USERS table |

**Join Logic:**
```sql
FROM HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW w
LEFT JOIN TEMP.INVESTMENT_GOVERNANCE.USERS u
    ON UPPER(CONCAT(LEFT(w.PREFERRED_NAME_FIRST_NAME, 1),
       REPLACE(w.PREFERRED_NAME_LAST_NAME, ' ', ''))) = u.SNOWFLAKE_USERNAME
WHERE w.ACTIVE_STATUS = 1
    AND UPPER(CONCAT(LEFT(w.PREFERRED_NAME_FIRST_NAME, 1),
        REPLACE(w.PREFERRED_NAME_LAST_NAME, ' ', ''))) = CURRENT_USER()
```

**Output Columns:** USER_ID, SNOWFLAKE_USERNAME, EMPLOYEE_ID, DISPLAY_NAME, TITLE, ROLE, THEATER, INDUSTRY_SEGMENT, MANAGER_ID, MANAGER_NAME, APPROVAL_LEVEL, IS_FINAL_APPROVER

### 4.2 VW_DATA_SOURCE_TIMESTAMPS

| Attribute | Value |
|---|---|
| **Location** | `TEMP.INVESTMENT_GOVERNANCE.VW_DATA_SOURCE_TIMESTAMPS` |
| **Owner** | `TECHNICAL_ACCOUNT_MANAGER` role |
| **Purpose** | Monitors last-modified timestamps across data sources to determine when the local cache needs refreshing |

**Sources Monitored:**
- `INVESTMENT_REQUESTS` - MAX(UPDATED_AT)
- `USERS` - MAX(CREATED_AT)
- `REQUEST_OPPORTUNITIES` - MAX(LINKED_AT)
- `SUGGESTED_CHANGES` - MAX(SUGGESTED_AT)

---

## 5. Local SQLite Cache

| Attribute | Value |
|---|---|
| **Location** | `cache.db` in project root (configurable via `config/standard.json`) |
| **Purpose** | Local fast-access cache for the macOS client, avoiding round-trips to Snowflake for reads |

### Cache Tables (6 tables)

| Table | Source | Refresh Trigger |
|---|---|---|
| `cache_metadata` | Tracks last Snowflake timestamps per data source | Updated after each refresh |
| `cached_current_user` | `TEMP.INVESTMENT_GOVERNANCE.VW_CURRENT_USER_INFO` | Full cache refresh on startup |
| `cached_investment_requests` | `TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS` (36 columns, excludes legacy approval columns) | Full refresh on startup; background refresh after every write operation |
| `cached_approval_steps` | `TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS` | Full refresh on startup; background refresh after every write operation |
| `cached_accounts` | `FIVETRAN.SALESFORCE.ACCOUNT` | Dropped and recreated on every server start |
| `cached_final_approvers` | `TEMP.INVESTMENT_GOVERNANCE.FINAL_APPROVERS` | Full cache refresh on startup |

### Cache Architecture

**Read Pattern:** All GET endpoints read from SQLite cache exclusively.

**Write Pattern (Cache-First):** All action endpoints (create, update, delete, submit, withdraw, approve, reject, revise, send-back, deny) follow a cache-first strategy:
1. Validate preconditions against cache
2. Write changes to SQLite immediately
3. Return HTTP success to the client
4. Launch a background daemon thread (`sync_to_snowflake()`) that:
   a. Writes the same change to Snowflake
   b. Invalidates the timestamp cache
   c. Refreshes the requests cache from Snowflake

**Refresh on Startup:** The `startup_cache_check()` function forces a full 6-step refresh if the accounts cache is empty or if Snowflake timestamps are newer than cached timestamps.

---

## 6. Configuration

| File | Purpose |
|---|---|
| `config/standard.json` | Runtime configuration: app name, bundle ID, version, API port (8770), cache DB name, Snowflake connection name |

---

## 7. Role Summary

| Role | Purpose | Scope |
|---|---|---|
| `TECHNICAL_ACCOUNT_MANAGER` | Owns all objects in `TEMP.INVESTMENT_GOVERNANCE` schema; reads HR Workday data | Full DDL/DML on application tables and views |
| `SNOW_CERTIFIED_PROFESSIONAL_SERVICES_RO_RL` | Read-only access to certified SFDC data | SELECT on `SNOW_CERTIFIED.PROFESSIONAL_SERVICES.FCT_SALESFORCE_PROFESSIONAL_SERVICES_OPPORTUNITY` |
