# SQLite Cache Consolidation Plan

## Overview

The SQLite cache layer (`cache.db`) currently contains **9 tables**. Analysis reveals 3 dead tables, 1 write-only table, and significant column duplication in `cached_investment_requests`. This plan consolidates the cache to reduce complexity and maintenance burden.

---

## Current State (9 tables)

| Table | Status | Rows |
|-------|--------|------|
| `cache_metadata` | Active — read/write | ~6 (one per data source) |
| `cached_current_user` | Active — read/write | 1 (current logged-in user) |
| `cached_users` | **DEAD** — never populated or read | 0 |
| `cached_investment_requests` | Active — read/write | All requests |
| `cached_approval_steps` | Active — read/write | All approval steps |
| `cached_accounts` | Active — read/write | All SFDC accounts |
| `cached_opportunities` | **DEAD** — never populated or read | 0 |
| `cached_final_approvers` | **WRITE-ONLY** — populated, never read | Per-theater approvers |
| `pending_sync` | **DEAD** — never populated or read | 0 |

---

## Phase 1: Remove Dead Tables (Low Risk)

### Step 1.1 — Remove `cached_users`
- **Why**: Created in `init_cache_db()` (line 83) but never populated or read anywhere in code. Has identical schema to `cached_current_user`, which IS used.
- **Action**: Remove the `CREATE TABLE IF NOT EXISTS cached_users` block from `init_cache_db()`.
- **Impact**: None. No code references this table beyond creation.
- **Files**: `api_server.py`

### Step 1.2 — Remove `cached_opportunities`
- **Why**: Created in `init_cache_db()` but never populated or read. Opportunities are always fetched live from Snowflake (`SFDC_SHARED.SFDC_VIEWS.OPPORTUNITIES`) via `/api/accounts/<id>/opportunities` and `/api/requests/<id>/opportunities`.
- **Action**: Remove the `CREATE TABLE IF NOT EXISTS cached_opportunities` block from `init_cache_db()`.
- **Impact**: None. No code references this table beyond creation.
- **Files**: `api_server.py`

### Step 1.3 — Remove `pending_sync`
- **Why**: Created in `init_cache_db()` but never populated or read. Was likely intended as a sync queue, but the actual pattern uses `sync_to_snowflake()` with direct background threads instead.
- **Action**: Remove the `CREATE TABLE IF NOT EXISTS pending_sync` block from `init_cache_db()`.
- **Impact**: None. No code references this table beyond creation.
- **Files**: `api_server.py`

### Step 1.4 — Clean up existing `cache.db`
- **Action**: Add a one-time migration in `init_cache_db()` to `DROP TABLE IF EXISTS` the three removed tables, so existing deployments clean up.
- **Files**: `api_server.py`

**Phase 1 Result**: 9 tables → 6 tables

---

## Phase 2: Fix `cached_final_approvers` (Low-Medium Risk)

### Step 2.1 — Read from cache instead of Snowflake
- **Why**: `cached_final_approvers` is populated during `full_cache_refresh()` (line 633-643) from `TEMP.INVESTMENT_GOVERNANCE.FINAL_APPROVERS`, but `resolve_approval_chain()` (line 485) queries Snowflake directly for the same data. This defeats the cache-first pattern.
- **Action**: Modify `resolve_approval_chain()` to read from `cached_final_approvers` instead of querying Snowflake's `FINAL_APPROVERS` table directly. Fall back to Snowflake if cache is empty.
- **Impact**: Reduces Snowflake queries during approval chain resolution. Faster approval flow.
- **Risk**: If cache is stale, approval chain could use outdated final approver info. Mitigate by refreshing this table when final approvers are updated, or by keeping a Snowflake fallback.
- **Files**: `api_server.py`

**Phase 2 Result**: Eliminates unnecessary Snowflake round-trips for final approver lookups

---

## Phase 3: Remove Legacy Approval Columns (Medium Risk)

### Background
`cached_investment_requests` has **16 legacy approval columns**:
```
dm_approved_by, dm_approved_by_title, dm_approved_at, dm_comments,
rd_approved_by, rd_approved_by_title, rd_approved_at, rd_comments,
avp_approved_by, avp_approved_by_title, avp_approved_at, avp_comments,
gvp_approved_by, gvp_approved_by_title, gvp_approved_at, gvp_comments
```

These **fully duplicate** data stored in `cached_approval_steps` (where step_order 1-4 maps to dm/rd/avp/gvp). Both are written to in parallel during the approve endpoint.

### Step 3.1 — Audit all consumers of legacy approval columns
- **Action**: Search every read path that accesses `dm_approved_by`, `rd_approved_by`, `avp_approved_by`, `gvp_approved_by` and their variants. Verify that all consumers can be migrated to read from `cached_approval_steps` via JOIN.
- **Consumers to check**:
  - `GET /api/requests` — does the list view return these columns?
  - `GET /api/requests/<id>` — does the detail view return these columns?
  - SwiftUI `InvestmentRequest` model — does it decode these fields?
  - Streamlit request detail page — does it display these fields?
  - Snowflake `INVESTMENT_REQUESTS` table — does it still store these columns?
- **Files**: `api_server.py`, `Sources/Models/DataModels.swift`, `app_pages/request_detail.py`

### Step 3.2 — Migrate reads to `cached_approval_steps`
- **Action**: For any endpoint that returns legacy approval columns, replace with a JOIN to `cached_approval_steps` filtered by `request_id`. The API response format can stay the same — just source data from steps instead of denormalized columns.
- **Files**: `api_server.py`

### Step 3.3 — Stop writing legacy approval columns
- **Action**: Remove the code in the approve endpoint (around line 1768-1775) that writes to `dm_approved_by`, `rd_approved_by`, etc. in `cached_investment_requests`. Only write to `cached_approval_steps`.
- **Files**: `api_server.py`

### Step 3.4 — Remove legacy columns from schema
- **Action**: Remove the 16 legacy approval columns from the `cached_investment_requests` CREATE TABLE statement. Add migration DROP COLUMN or recreate table.
- **Note**: SQLite does not support `DROP COLUMN` prior to 3.35.0. May need to recreate the table.
- **Files**: `api_server.py`

### Step 3.5 — Remove legacy columns from Snowflake (optional, deferred)
- **Why**: The Snowflake `INVESTMENT_REQUESTS` table also stores these 16 columns. Removing them is a separate migration that should be coordinated.
- **Action**: Defer to a Snowflake schema migration plan. For now, the API server simply stops writing/reading them from cache.

**Phase 3 Result**: `cached_investment_requests` drops from 52 → 36 columns

---

## Phase 4: Evaluate Denormalized Name Fields (Low Priority)

### Fields in question
`cached_investment_requests` stores several denormalized name fields:
- `created_by_name` — could JOIN from HR/Workday by `created_by`
- `next_approver_name`, `next_approver_title` — could derive from `cached_approval_steps`
- `submitted_by_name` — could derive from `created_by_name`
- `withdrawn_by_name` — could derive from employee lookup
- `draft_by_name` — could derive from employee lookup
- `on_behalf_of_name` — could derive from `on_behalf_of_employee_id`
- `account_name` — could JOIN from `cached_accounts`

### Recommendation: KEEP as-is
- These denormalized fields are a **deliberate caching optimization**. They avoid JOINs on every request list query.
- The SQLite cache is a single-user local store, not a normalized relational database. Denormalization is appropriate here.
- The maintenance cost is low — names rarely change, and a full refresh repopulates them.
- **No action needed.**

---

## Summary

| Phase | Action | Tables Removed | Columns Removed | Risk |
|-------|--------|---------------|-----------------|------|
| 1 | Remove 3 dead tables | 3 | All in those tables | Low |
| 2 | Read final_approvers from cache | 0 | 0 | Low-Medium |
| 3 | Remove legacy approval columns | 0 | 16 | Medium |
| 4 | Keep denormalized names | 0 | 0 | N/A |

### Final State: 6 tables, 36 columns in requests table

| Table | Purpose |
|-------|---------|
| `cache_metadata` | Tracks last refresh timestamps per data source |
| `cached_current_user` | Single row for logged-in user info |
| `cached_investment_requests` | All investment requests (36 columns, down from 52) |
| `cached_approval_steps` | All approval steps (single source of truth for approvals) |
| `cached_accounts` | SFDC account lookup cache |
| `cached_final_approvers` | Final approver per theater (now actually read from cache) |

---

## Execution Order

1. **Phase 1** first — zero risk, immediate cleanup
2. **Phase 2** next — small scope, improves cache consistency
3. **Phase 3** last — requires careful audit of all consumers, most impactful change
4. **Phase 4** — no action needed, keep denormalized fields

Each phase should be a separate commit/PR for easy rollback.
