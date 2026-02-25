# Investment Governance - Approval Hierarchy

## Overview

The Investment Governance application implements a 4-level approval chain that routes investment requests from the creator's direct manager up through the organizational hierarchy to Jon Beaulier (GVP of Majors), who serves as the final approver. Each level corresponds to a management tier, and the system tracks each approver's identity, title, comments, and timestamp.

---

## Approval Levels

| Level | Role Code | Role Description | Responsibility |
|---|---|---|---|
| 1 | AE | Account Executive / Submitter | Creates and submits investment requests |
| 2 | DM | District Manager | First-level approval |
| 3 | RD | Regional Director | Second-level approval |
| 4 | AVP | Area Vice President | Third-level approval |
| 5 | GVP | Group Vice President (Final Approver) | Final approval authority |

---

## Hierarchy Chain

```
Level 1: Creator / Submitter (AE)
    |
    | Submits request
    | NEXT_APPROVER_NAME = creator's manager (from USERS table)
    v
Level 2: District Manager (DM)
    |
    | Approves: SUBMITTED -> DM_APPROVED
    | Records: DM_APPROVED_BY, DM_APPROVED_BY_TITLE, DM_APPROVED_AT, DM_COMMENTS
    v
Level 3: Regional Director (RD)
    |
    | Approves: DM_APPROVED -> RD_APPROVED
    | Records: RD_APPROVED_BY, RD_APPROVED_BY_TITLE, RD_APPROVED_AT, RD_COMMENTS
    v
Level 4: Area Vice President (AVP)
    |
    | Approves: RD_APPROVED -> AVP_APPROVED
    | Records: AVP_APPROVED_BY, AVP_APPROVED_BY_TITLE, AVP_APPROVED_AT, AVP_COMMENTS
    v
Level 5: Jon Beaulier - GVP of Majors (Final Approver)
    |
    | Approves: AVP_APPROVED -> FINAL_APPROVED
    | Records: GVP_APPROVED_BY, GVP_APPROVED_BY_TITLE, GVP_APPROVED_AT, GVP_COMMENTS
    v
FINAL_APPROVED (terminal success state)
```

---

## How the Hierarchy is Defined

### USERS Table

The approval hierarchy is configured in `TEMP.INVESTMENT_GOVERNANCE.USERS`. Each user entry defines:

| Field | Purpose |
|---|---|
| `SNOWFLAKE_USERNAME` | Matches the user's Snowflake login (derived from Workday: first initial + last name, uppercase) |
| `ROLE` | Role code: AE, DM, RD, AVP, or GVP |
| `APPROVAL_LEVEL` | Numeric level (1-5) determining where the user sits in the chain |
| `IS_FINAL_APPROVER` | Boolean flag; only the GVP (Jon Beaulier) has this set to `true` |
| `MANAGER_ID` / `MANAGER_NAME` | References to the user's direct manager for routing |

**Current Configuration:**

| User | Role | Level | Final Approver | Manager |
|---|---|---|---|---|
| Tracy LeGrand (TLEGRAND) | AE | 1 | No | DM Manager |
| Jon Beaulier (JON_BEAULIER) | GVP | 5 | Yes | (none) |

### VW_CURRENT_USER_INFO View

This view identifies the currently logged-in user by joining two sources:

1. **Workday** (`HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW`): Provides real-time employee data including display name, business title, manager name, manager ID, and cost center
2. **USERS table** (`TEMP.INVESTMENT_GOVERNANCE.USERS`): Provides application-specific role, approval level, and final approver flag

**Username Derivation:** The Snowflake username is derived from Workday data as:
```
UPPER(CONCAT(LEFT(first_name, 1), REPLACE(last_name, ' ', '')))
```
Example: Tracy LeGrand -> TLEGRAND

**Fallback Behavior:** If a user exists in Workday but not in the USERS table, the LEFT JOIN returns defaults: ROLE = 'USER', APPROVAL_LEVEL = 0, IS_FINAL_APPROVER = false, THEATER falls back to the Workday COST_CENTER_NAME.

---

## How Approval Routing Works

### Step 1: Initial Routing on Submission

When a request is submitted (`POST /api/requests/<id>/submit`):

1. The system looks up the **creator's** record in `cached_users` (not the submitter, since the creator and submitter may differ)
2. Retrieves the creator's `MANAGER_NAME` field
3. Sets `NEXT_APPROVER_NAME` on the request to this manager
4. Sets `CURRENT_APPROVAL_LEVEL` = 1, `STATUS` = `SUBMITTED`

**Code Reference** (`api_server.py`, submit endpoint):
```python
cur2.execute("SELECT manager_name FROM cached_users WHERE snowflake_username = ?", (created_by,))
mrow = cur2.fetchone()
next_approver = mrow["manager_name"] if mrow else None
```

### Step 2: Approval Progression

Each subsequent approval is driven by the **status_transitions** map:

```python
status_transitions = {
    'SUBMITTED':    ('DM_APPROVED',    'dm_approved_by',  'dm_approved_by_title',  'dm_approved_at',  'dm_comments',  2),
    'DM_APPROVED':  ('RD_APPROVED',    'rd_approved_by',  'rd_approved_by_title',  'rd_approved_at',  'rd_comments',  3),
    'RD_APPROVED':  ('AVP_APPROVED',   'avp_approved_by', 'avp_approved_by_title', 'avp_approved_at', 'avp_comments', 4),
    'AVP_APPROVED': ('FINAL_APPROVED', 'gvp_approved_by', 'gvp_approved_by_title', 'gvp_approved_at', 'gvp_comments', 5)
}
```

Each approval:
1. Reads the current status to determine the transition
2. Records the approver's name (from `VW_CURRENT_USER_INFO` via cached session) and title
3. Stores the approval timestamp and optional comments
4. Advances `CURRENT_APPROVAL_LEVEL` to the next level
5. Transitions STATUS to the next state

### Step 3: Final Approval by Jon Beaulier

Jon Beaulier (JON_BEAULIER) is the designated final approver:
- `APPROVAL_LEVEL` = 5
- `IS_FINAL_APPROVER` = true
- `ROLE` = GVP
- `TITLE` = GVP of Majors

When Jon approves a request in `AVP_APPROVED` status:
- STATUS transitions to `FINAL_APPROVED`
- GVP_APPROVED_BY = "Jon Beaulier"
- GVP_APPROVED_BY_TITLE = "GVP of Majors"
- GVP_APPROVED_AT = current timestamp
- CURRENT_APPROVAL_LEVEL = 5

---

## Approver Actions at Each Level

Every approver (Levels 2-5) has four possible actions on a request that has reached their level:

| Action | Effect | Resulting Status | API Endpoint |
|---|---|---|---|
| **Approve** | Advances to next approval level | Next status in chain | `POST /approve` |
| **Send Back** | Returns to creator for revision | DRAFT | `POST /send-back` |
| **Reject** | Marks as rejected (revisable) | REJECTED | `POST /reject` |
| **Deny** | Marks as denied (terminal) | DENIED | `POST /deny` |

### Approve
- Advances the request one level in the chain
- Records the approver's name, title, timestamp, and comments in the level-specific fields
- If this is the final level (AVP_APPROVED -> FINAL_APPROVED), the request is fully approved

### Send Back
- Returns the request to DRAFT status
- Stores the approver's comments in GVP_COMMENTS (regardless of which level sent it back)
- Previous approval fields are preserved (not cleared)
- Creator can edit and resubmit

### Reject
- Sets status to REJECTED
- Creator can revise the business case and resubmit or save as draft

### Deny
- Sets status to DENIED with comments in GVP_COMMENTS
- Terminal state; no further action path documented

---

## Viewer Access Model

### Who Can See What

The application does not implement row-level security at the API layer. All authenticated users can view all investment requests through the following interfaces:

| Interface | Access Level | Description |
|---|---|---|
| **Dashboard** | All users | Summary cards showing counts by status (Draft, Pending Approval, Rejected, Approved) and total investment amounts |
| **Investment Requests Tab** | All users | Full list of all requests with filtering by theater, industry, quarter, status, and fiscal year |
| **Request Detail** | All users | Complete request details including business case, approval log, and all approval chain data |
| **Approvals Tab** | All users | View of requests, filterable by theater; shows requests pending approval |
| **"My Requests" Filter** | Scoped to creator | Filters to show only requests created by the current user |
| **"Pending My Approval" Filter** | Scoped to approver | Filters to show requests where NEXT_APPROVER_NAME matches the current user's display name |

### Pending My Approval Logic

The Dashboard summary calculates "Pending My Approval" count by matching:
```sql
SELECT COUNT(*) FROM cached_investment_requests
WHERE next_approver_name = ?  -- current user's display_name
```

This means a user sees requests pending their action when their display name matches the NEXT_APPROVER_NAME field on the request.

### Approval Pipeline Visibility

The Dashboard's Approval Pipeline section shows all in-flight requests (statuses: SUBMITTED, DM_APPROVED, RD_APPROVED, AVP_APPROVED) to all users, providing full organizational visibility into the approval pipeline.

---

## Hierarchy Management

### Adding New Users to the Hierarchy

To add a new user to the approval chain:

1. Insert a row into `TEMP.INVESTMENT_GOVERNANCE.USERS` with:
   - `SNOWFLAKE_USERNAME` matching their Snowflake login (uppercase, first initial + last name)
   - `ROLE` = DM, RD, AVP, or GVP
   - `APPROVAL_LEVEL` = 2, 3, 4, or 5
   - `MANAGER_NAME` = their direct manager's display name
   - `IS_FINAL_APPROVER` = true only for the GVP

2. The user's Workday data (title, manager, employee ID) is automatically resolved via `VW_CURRENT_USER_INFO` when they log in

### Current Hierarchy Gaps

The current USERS table has only 2 entries (Level 1 AE and Level 5 GVP). Users at intermediate levels (DM, RD, AVP) are not yet configured. The approval chain will still function - any authenticated user can approve a request at any level - but the `NEXT_APPROVER_NAME` routing and approval level enforcement are based on the USERS table configuration.

---

## End-to-End Example

**Scenario:** Tracy LeGrand creates an investment request for $50,000.

1. **Tracy (AE, Level 1)** creates and submits the request
   - STATUS = SUBMITTED, CURRENT_APPROVAL_LEVEL = 1
   - NEXT_APPROVER_NAME = "DM Manager" (Tracy's manager from USERS table)

2. **DM Manager (DM, Level 2)** approves with comment "Good investment case"
   - STATUS = DM_APPROVED, CURRENT_APPROVAL_LEVEL = 2
   - DM_APPROVED_BY = "DM Manager", DM_COMMENTS = "Good investment case"

3. **Regional Director (RD, Level 3)** approves
   - STATUS = RD_APPROVED, CURRENT_APPROVAL_LEVEL = 3
   - RD_APPROVED_BY = (approver name), RD_APPROVED_AT = timestamp

4. **Area VP (AVP, Level 4)** approves
   - STATUS = AVP_APPROVED, CURRENT_APPROVAL_LEVEL = 4
   - AVP_APPROVED_BY = (approver name), AVP_APPROVED_AT = timestamp

5. **Jon Beaulier (GVP, Level 5, Final Approver)** approves with comment "Approved for Q2"
   - STATUS = FINAL_APPROVED, CURRENT_APPROVAL_LEVEL = 5
   - GVP_APPROVED_BY = "Jon Beaulier", GVP_APPROVED_BY_TITLE = "GVP of Majors"
   - GVP_COMMENTS = "Approved for Q2"

The request is now fully approved. The approval log shows all five stages with timestamps, approver names, titles, and comments.
