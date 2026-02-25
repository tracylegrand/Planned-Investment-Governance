# Investment Governance - Request Lifecycle

## Overview

An investment request progresses through a defined lifecycle from creation to final disposition. This document describes each stage, the transitions between them, and the actions available at each point.

---

## Status States

| Status | Display Name | Description |
|---|---|---|
| `DRAFT` | Draft | Request is being composed or has been returned for revision |
| `SUBMITTED` | Submitted | Request has been submitted and awaits DM approval |
| `DM_APPROVED` | DM Approved | District Manager has approved; awaits RD approval |
| `RD_APPROVED` | RD Approved | Regional Director has approved; awaits AVP approval |
| `AVP_APPROVED` | AVP Approved | Area VP has approved; awaits GVP/final approval |
| `FINAL_APPROVED` | Approved | Fully approved through the entire chain |
| `REJECTED` | Rejected | Rejected by an approver (can be revised and resubmitted) |
| `DENIED` | Denied | Denied by an approver (terminal state with comments) |

---

## Lifecycle Diagram

```
                                    +------------------+
                                    |                  |
                              +---->|    REJECTED      |----+
                              |     |                  |    |
                              |     +------------------+    | Revise
                              |                             |
                              | Reject                      v
+----------+   Submit   +----------+   Approve   +-------------+
|          |----------->|          |------------>|             |
|  DRAFT   |            | SUBMITTED|             | DM_APPROVED |
|          |<-----------|          |             |             |
+----------+   Withdraw +----------+             +-------------+
    ^   ^       or                                    |    |
    |   |    Send-back                          Approve|    | Reject/
    |   |                                             v    | Send-back/
    |   |                                    +-------------+ Withdraw
    |   |                              +---->|             |----+
    |   |                              |     | RD_APPROVED |    |
    |   +------------------------------+     |             |    |
    |          Withdraw/Send-back            +-------------+    |
    |                                             |    |        |
    |                                       Approve|    |       |
    |                                             v    |       |
    |                                    +-------------+       |
    |                              +---->|             |       |
    |                              |     | AVP_APPROVED|       |
    |                              |     |             |       |
    |                              |     +-------------+       |
    |                              |          |                 |
    |          Withdraw/Send-back  |    Approve|                |
    |          +-------------------+          v                |
    |          |                      +--------------+         |
    |          |                      |              |         |
    |          +---+                  |FINAL_APPROVED|         |
    |              |                  |              |         |
    |              |                  +--------------+         |
    |              |                                           |
    |              +---> DRAFT <-------------------------------+
    |                                                          
    +--- (Revise from REJECTED) ----> DRAFT or SUBMITTED      
                                                               
                                    +------------------+
                                    |                  |
                                    |     DENIED       |
                                    |   (terminal)     |
                                    +------------------+
```

---

## Phase 1: Creation

### Creating a New Request

**Trigger:** User clicks "New Request" button in the Investment Requests tab.

**API Endpoint:** `POST /api/requests`

**Process:**
1. User fills in request fields:
   - **Title** (required)
   - **Account** (searchable dropdown from 75,570 SFDC accounts, or free-form entry)
   - **Investment Type** (Professional Services, Customer Success, Training, Support, Partnership, Other)
   - **Amount Requested** (dollar amount)
   - **Quarter** (fiscal quarter)
   - **Theater** (auto-populated from selected account, or selected from SFDC theaters)
   - **Industry Segment** (filtered by selected theater from SFDC data)
   - **Business Justification** (rich text editor with formatting toolbar)
   - **Expected Outcome** (rich text editor)
   - **Risk Assessment** (rich text editor)
2. System auto-populates:
   - `CREATED_BY` = current Snowflake username
   - `CREATED_BY_NAME` = display name from Workday
   - `CREATED_BY_EMPLOYEE_ID` = Workday employee ID
   - `CREATED_AT` = current timestamp
   - `STATUS` = `DRAFT`
   - `CURRENT_APPROVAL_LEVEL` = 0
   - `NEXT_APPROVER_NAME` = creator's manager name (from USERS table)
3. User saves as **Draft** or submits directly with **Submit for Approval**

**Cache Behavior:** A temporary negative ID is assigned in SQLite. A background thread creates the record in Snowflake (which assigns the real autoincrement ID) and then refreshes the cache.

---

## Phase 2: Drafting and Editing

### Editing a Draft

**Trigger:** User opens a request with status `DRAFT` and clicks Edit.

**API Endpoint:** `PUT /api/requests/<request_id>`

**Precondition:** Request must be in `DRAFT` status.

**Editable Fields:**
- Title, Account, Investment Type, Amount, Quarter, Theater, Industry Segment
- Business Justification, Expected Outcome, Risk Assessment (rich text)
- Optional draft comment (captured with commenter name and timestamp)

**Process:**
1. User modifies any fields
2. User clicks **Save as Draft** (stays in DRAFT) or **Submit for Approval** (transitions to SUBMITTED)
3. If a draft comment is provided, it is stored in DRAFT_COMMENT, DRAFT_BY_NAME, DRAFT_AT

### Deleting a Draft

**API Endpoint:** `DELETE /api/requests/<request_id>`

**Precondition:** Request must be in `DRAFT` status.

**Process:** Removes the request and all associated records (opportunities, contributors, suggested changes) from both cache and Snowflake.

---

## Phase 3: Submission

### Submitting for Approval

**Trigger:** User clicks "Submit for Approval" from a DRAFT request (new or existing).

**API Endpoint:** `POST /api/requests/<request_id>/submit`

**Precondition:** Request must be in `DRAFT` status.

**Process:**
1. System looks up the creator's manager from the `cached_users` table
2. Sets `NEXT_APPROVER_NAME` to the creator's manager
3. Updates fields:
   - `STATUS` = `SUBMITTED`
   - `CURRENT_APPROVAL_LEVEL` = 1
   - `SUBMITTED_COMMENT` = optional comment from submitter
   - `SUBMITTED_BY_NAME` = submitter's display name
   - `SUBMITTED_AT` = current timestamp
4. Request enters the approval pipeline

---

## Phase 4: Approval Chain

### Approval Flow

Each approval advances the request one level through the hierarchy.

**API Endpoint:** `POST /api/requests/<request_id>/approve`

**Status Transition Map:**

| Current Status | New Status | Approval Fields Set | New Level |
|---|---|---|---|
| `SUBMITTED` | `DM_APPROVED` | DM_APPROVED_BY, DM_APPROVED_BY_TITLE, DM_APPROVED_AT, DM_COMMENTS | 2 |
| `DM_APPROVED` | `RD_APPROVED` | RD_APPROVED_BY, RD_APPROVED_BY_TITLE, RD_APPROVED_AT, RD_COMMENTS | 3 |
| `RD_APPROVED` | `AVP_APPROVED` | AVP_APPROVED_BY, AVP_APPROVED_BY_TITLE, AVP_APPROVED_AT, AVP_COMMENTS | 4 |
| `AVP_APPROVED` | `FINAL_APPROVED` | GVP_APPROVED_BY, GVP_APPROVED_BY_TITLE, GVP_APPROVED_AT, GVP_COMMENTS | 5 |

**Process per approval step:**
1. Approver opens the request in the Approvals tab or from a Pending Approval filter
2. Reviews the business case, amount, account details, and prior approval comments
3. Approver can:
   - **Approve** with optional comments (advances to next level)
   - **Send Back** for revision (returns to DRAFT)
   - **Reject** (sets status to REJECTED)
   - **Deny** (sets status to DENIED)

### Final Approval

When a request in `AVP_APPROVED` status is approved, it transitions to `FINAL_APPROVED` and the GVP approval fields are populated. This is the terminal successful state.

---

## Phase 5: Alternative Outcomes

### Withdrawal

**API Endpoint:** `POST /api/requests/<request_id>/withdraw`

**Available During:** SUBMITTED, DM_APPROVED, RD_APPROVED, AVP_APPROVED

**Process:**
1. Creator (or authorized user) withdraws the request with an optional comment
2. System clears ALL approval fields (DM, RD, AVP, GVP - all set to NULL)
3. Records withdrawal metadata: WITHDRAWN_BY, WITHDRAWN_BY_NAME, WITHDRAWN_AT, WITHDRAWN_COMMENT
4. Status returns to `DRAFT` with CURRENT_APPROVAL_LEVEL = 0
5. Request can be edited and resubmitted

### Send Back for Revision

**API Endpoint:** `POST /api/requests/<request_id>/send-back`

**Available During:** SUBMITTED, DM_APPROVED, RD_APPROVED, AVP_APPROVED

**Process:**
1. An approver sends the request back with comments (stored in GVP_COMMENTS)
2. Status returns to `DRAFT`
3. Creator can edit and resubmit the request
4. Previous approval fields are NOT cleared (unlike withdrawal)

### Rejection

**API Endpoint:** `POST /api/requests/<request_id>/reject`

**Available During:** SUBMITTED, DM_APPROVED, RD_APPROVED, AVP_APPROVED

**Process:**
1. An approver rejects the request
2. Status set to `REJECTED`
3. Creator can revise and resubmit (see Revision below)

### Denial

**API Endpoint:** `POST /api/requests/<request_id>/deny`

**Available During:** SUBMITTED, DM_APPROVED, RD_APPROVED, AVP_APPROVED

**Process:**
1. An approver denies the request with comments (stored in GVP_COMMENTS)
2. Status set to `DENIED`
3. This is a terminal state (no further action documented)

### Revision (from Rejected)

**API Endpoint:** `POST /api/requests/<request_id>/revise`

**Precondition:** Request must be in `REJECTED` status.

**Process:**
1. Creator opens the rejected request
2. Can modify: Business Justification, Expected Outcome, Risk Assessment
3. Two options:
   - **Save as Draft**: Sets status to `DRAFT` with optional draft comment
   - **Submit for Approval**: Sets status directly to `SUBMITTED` with optional submission comment, bypassing the DRAFT state

---

## Approval Log (Audit Trail)

The application displays an Approval Log on each request detail view showing the chronological history of state changes. Each entry shows:

| Element | Description |
|---|---|
| **Status Badge** | Color-coded status indicator (Draft, Submitted, DM Approved, etc.) |
| **User Name** | Person who performed the action |
| **Title** | Job title of the person |
| **Comment** | Optional comment provided with the action (italic) |
| **Timestamp** | Date and time of the action (right-aligned) |

The log reconstructs the history from the stored approval fields on the INVESTMENT_REQUESTS record, displaying in order: Created > Draft > Submitted > DM Approved > RD Approved > AVP Approved > GVP/Final Approved > Withdrawn > Pending Next Approver.

---

## Summary of API Endpoints

| Endpoint | Method | Action | From Status | To Status |
|---|---|---|---|---|
| `/api/requests` | POST | Create | (new) | DRAFT |
| `/api/requests/<id>` | PUT | Edit | DRAFT | DRAFT |
| `/api/requests/<id>` | DELETE | Delete | DRAFT | (removed) |
| `/api/requests/<id>/submit` | POST | Submit | DRAFT | SUBMITTED |
| `/api/requests/<id>/approve` | POST | Approve | SUBMITTED/DM_APPROVED/RD_APPROVED/AVP_APPROVED | Next level |
| `/api/requests/<id>/withdraw` | POST | Withdraw | SUBMITTED/DM_APPROVED/RD_APPROVED/AVP_APPROVED | DRAFT |
| `/api/requests/<id>/send-back` | POST | Send Back | SUBMITTED/DM_APPROVED/RD_APPROVED/AVP_APPROVED | DRAFT |
| `/api/requests/<id>/reject` | POST | Reject | SUBMITTED/DM_APPROVED/RD_APPROVED/AVP_APPROVED | REJECTED |
| `/api/requests/<id>/deny` | POST | Deny | SUBMITTED/DM_APPROVED/RD_APPROVED/AVP_APPROVED | DENIED |
| `/api/requests/<id>/revise` | POST | Revise | REJECTED | DRAFT or SUBMITTED |
