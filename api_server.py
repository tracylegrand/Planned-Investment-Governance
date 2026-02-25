#!/usr/bin/env python3
"""
Investment Governance API Server with Local SQLite Cache
"""

import json
import os
import sqlite3
import threading
import time
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import snowflake.connector
from flask import Flask, jsonify, request

app = Flask(__name__)

SCRIPT_DIR = Path(__file__).parent
CONFIG_FILE = SCRIPT_DIR / "config" / "standard.json"
with open(CONFIG_FILE) as f:
    RUNTIME_CONFIG = json.load(f)

API_PORT = RUNTIME_CONFIG.get("api_port", 8767)
CACHE_DB_NAME = RUNTIME_CONFIG.get("cache_db", "cache.db")
CONNECTION_NAME = os.environ.get("SNOWFLAKE_CONNECTION_NAME", RUNTIME_CONFIG.get("connection_name", "DemoAcct"))

CACHE_DB_PATH = SCRIPT_DIR / CACHE_DB_NAME

ADMIN_USERNAME = "TLEGRAND"

cache_lock = threading.Lock()
progress_lock = threading.Lock()
impersonation_lock = threading.Lock()

cache_progress = {
    "status": "idle",
    "current_step": "",
    "steps_completed": 0,
    "total_steps": 7,
    "message": ""
}

impersonated_user = None

def get_snowflake_connection():
    return snowflake.connector.connect(connection_name=CONNECTION_NAME)

def get_cache_connection():
    conn = sqlite3.connect(str(CACHE_DB_PATH), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def json_serializer(obj):
    if isinstance(obj, (date, datetime)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, bool):
        return obj
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

def init_cache_db():
    conn = get_cache_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS cache_metadata (
            data_source TEXT PRIMARY KEY,
            last_snowflake_modified TEXT,
            last_cache_refresh TEXT
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_users (
            user_id INTEGER PRIMARY KEY,
            snowflake_username TEXT UNIQUE,
            employee_id INTEGER,
            display_name TEXT,
            title TEXT,
            role TEXT,
            theater TEXT,
            industry_segment TEXT,
            manager_id INTEGER,
            manager_name TEXT,
            approval_level INTEGER,
            is_final_approver INTEGER
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_current_user (
            snowflake_username TEXT PRIMARY KEY,
            user_id INTEGER,
            employee_id INTEGER,
            display_name TEXT,
            title TEXT,
            role TEXT,
            theater TEXT,
            industry_segment TEXT,
            manager_id INTEGER,
            manager_name TEXT,
            approval_level INTEGER,
            is_final_approver INTEGER
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_investment_requests (
            request_id INTEGER PRIMARY KEY,
            request_title TEXT,
            account_id TEXT,
            account_name TEXT,
            investment_type TEXT,
            requested_amount REAL,
            investment_quarter TEXT,
            business_justification TEXT,
            expected_outcome TEXT,
            risk_assessment TEXT,
            created_by TEXT,
            created_by_name TEXT,
            created_by_employee_id INTEGER,
            created_at TEXT,
            theater TEXT,
            industry_segment TEXT,
            status TEXT,
            current_approval_level INTEGER,
            next_approver_id INTEGER,
            next_approver_name TEXT,
            next_approver_title TEXT,
            dm_approved_by TEXT,
            dm_approved_by_title TEXT,
            dm_approved_at TEXT,
            dm_comments TEXT,
            rd_approved_by TEXT,
            rd_approved_by_title TEXT,
            rd_approved_at TEXT,
            rd_comments TEXT,
            avp_approved_by TEXT,
            avp_approved_by_title TEXT,
            avp_approved_at TEXT,
            avp_comments TEXT,
            gvp_approved_by TEXT,
            gvp_approved_by_title TEXT,
            gvp_approved_at TEXT,
            gvp_comments TEXT,
            updated_at TEXT,
            withdrawn_by TEXT,
            withdrawn_by_name TEXT,
            withdrawn_at TEXT,
            withdrawn_comment TEXT,
            submitted_comment TEXT,
            submitted_by_name TEXT,
            submitted_at TEXT,
            draft_comment TEXT,
            draft_by_name TEXT,
            draft_at TEXT,
            on_behalf_of_employee_id INTEGER,
            on_behalf_of_name TEXT,
            sfdc_opportunity_link TEXT,
            expected_roi TEXT
        )
    """)

    cur.execute("DROP TABLE IF EXISTS cached_accounts")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_accounts (
            account_id TEXT,
            account_name TEXT PRIMARY KEY,
            theater TEXT,
            industry_segment TEXT
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_opportunities (
            opportunity_id TEXT PRIMARY KEY,
            opportunity_name TEXT,
            account_id TEXT,
            account_name TEXT,
            stage TEXT,
            amount REAL,
            close_date TEXT,
            owner_name TEXT
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS pending_sync (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operation TEXT,
            table_name TEXT,
            data TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            status TEXT DEFAULT 'pending',
            error_message TEXT
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_approval_steps (
            step_id INTEGER PRIMARY KEY,
            request_id INTEGER NOT NULL,
            step_order INTEGER NOT NULL,
            approver_employee_id INTEGER,
            approver_name TEXT,
            approver_title TEXT,
            status TEXT DEFAULT 'PENDING',
            approved_at TEXT,
            comments TEXT,
            is_final_step INTEGER DEFAULT 0,
            created_at TEXT
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_final_approvers (
            theater TEXT PRIMARY KEY,
            approver_employee_id INTEGER NOT NULL,
            approver_name TEXT NOT NULL,
            approver_title TEXT
        )
    """)

    cur.execute("CREATE INDEX IF NOT EXISTS idx_requests_status ON cached_investment_requests(status)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_requests_theater ON cached_investment_requests(theater)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_requests_quarter ON cached_investment_requests(investment_quarter)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_accounts_name ON cached_accounts(account_name)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_steps_request ON cached_approval_steps(request_id)")

    conn.commit()
    conn.close()
    print("Cache database initialized")

_sf_timestamps_cache = None
_sf_timestamps_cache_time = None
SF_TIMESTAMPS_TTL = 60

def get_snowflake_timestamps(sf_conn=None):
    global _sf_timestamps_cache, _sf_timestamps_cache_time

    now = datetime.now()
    if _sf_timestamps_cache is not None and _sf_timestamps_cache_time is not None:
        age = (now - _sf_timestamps_cache_time).total_seconds()
        if age < SF_TIMESTAMPS_TTL:
            return _sf_timestamps_cache

    close_conn = False
    if sf_conn is None:
        sf_conn = get_snowflake_connection()
        close_conn = True
    try:
        cur = sf_conn.cursor()
        cur.execute("SELECT DATA_SOURCE, LAST_MODIFIED FROM TEMP.INVESTMENT_GOVERNANCE.VW_DATA_SOURCE_TIMESTAMPS")
        _sf_timestamps_cache = {row[0]: row[1].isoformat() if row[1] else None for row in cur.fetchall()}
        _sf_timestamps_cache_time = now
        return _sf_timestamps_cache
    except Exception as e:
        print(f"Error getting Snowflake timestamps: {e}")
        return {}
    finally:
        if close_conn:
            sf_conn.close()

def invalidate_timestamps_cache():
    global _sf_timestamps_cache, _sf_timestamps_cache_time
    _sf_timestamps_cache = None
    _sf_timestamps_cache_time = None

def get_cached_user_info():
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT * FROM cached_current_user LIMIT 1")
        row = cur.fetchone()
        if row:
            return {
                "username": row["snowflake_username"],
                "display_name": row["display_name"],
                "employee_id": row["employee_id"],
                "title": row["title"],
                "manager_name": row["manager_name"],
                "manager_id": row["manager_id"],
                "role": row["role"],
                "theater": row["theater"],
            }
        return None
    finally:
        cache_conn.close()

def get_effective_user():
    with impersonation_lock:
        if impersonated_user is not None:
            return impersonated_user
    return get_cached_user_info()

def get_real_username():
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT snowflake_username FROM cached_current_user LIMIT 1")
        row = cur.fetchone()
        return row["snowflake_username"] if row else None
    finally:
        cache_conn.close()

def is_admin():
    return get_real_username() == ADMIN_USERNAME

def update_cache_request(request_id, updates):
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        set_parts = []
        params = []
        for col, val in updates.items():
            set_parts.append(f"{col} = ?")
            params.append(val)
        params.append(request_id)
        cur.execute(f"UPDATE cached_investment_requests SET {', '.join(set_parts)} WHERE request_id = ?", params)
        cache_conn.commit()
    finally:
        cache_conn.close()

def delete_cache_request(request_id):
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("DELETE FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        cache_conn.commit()
    finally:
        cache_conn.close()

def insert_cache_request(row_dict):
    cache_conn = get_cache_connection()
    try:
        cols = list(row_dict.keys())
        placeholders = ", ".join(["?"] * len(cols))
        cur = cache_conn.cursor()
        cur.execute(f"INSERT OR REPLACE INTO cached_investment_requests ({', '.join(cols)}) VALUES ({placeholders})", list(row_dict.values()))
        cache_conn.commit()
    finally:
        cache_conn.close()

def sync_to_snowflake(sf_func):
    def _run():
        try:
            sf_func()
        except Exception as e:
            print(f"Background Snowflake sync error: {e}")
        finally:
            invalidate_timestamps_cache()
            try:
                _refresh_requests_and_steps()
            except Exception as e:
                print(f"Background cache refresh error: {e}")
    threading.Thread(target=_run, daemon=True).start()

def _refresh_requests_and_steps():
    sf_conn = get_snowflake_connection()
    cache_conn = get_cache_connection()
    try:
        sf_cur = sf_conn.cursor()
        sf_cur.execute("""
            SELECT REQUEST_ID, REQUEST_TITLE, ACCOUNT_ID, ACCOUNT_NAME, INVESTMENT_TYPE,
                   REQUESTED_AMOUNT, INVESTMENT_QUARTER, BUSINESS_JUSTIFICATION, EXPECTED_OUTCOME,
                   RISK_ASSESSMENT, CREATED_BY, CREATED_BY_NAME, CREATED_BY_EMPLOYEE_ID, CREATED_AT,
                   THEATER, INDUSTRY_SEGMENT, STATUS, CURRENT_APPROVAL_LEVEL, NEXT_APPROVER_ID,
                   NEXT_APPROVER_NAME, NEXT_APPROVER_TITLE, DM_APPROVED_BY, DM_APPROVED_BY_TITLE, DM_APPROVED_AT, DM_COMMENTS,
                   RD_APPROVED_BY, RD_APPROVED_BY_TITLE, RD_APPROVED_AT, RD_COMMENTS, AVP_APPROVED_BY, AVP_APPROVED_BY_TITLE,
                   AVP_APPROVED_AT, AVP_COMMENTS, GVP_APPROVED_BY, GVP_APPROVED_BY_TITLE, GVP_APPROVED_AT, GVP_COMMENTS, UPDATED_AT,
                   WITHDRAWN_BY, WITHDRAWN_BY_NAME, WITHDRAWN_AT, WITHDRAWN_COMMENT,
                   SUBMITTED_COMMENT, SUBMITTED_BY_NAME, SUBMITTED_AT,
                   DRAFT_COMMENT, DRAFT_BY_NAME, DRAFT_AT,
                   ON_BEHALF_OF_EMPLOYEE_ID, ON_BEHALF_OF_NAME,
                   SFDC_OPPORTUNITY_LINK, EXPECTED_ROI
            FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
            ORDER BY CREATED_AT DESC
        """)
        rows = sf_cur.fetchall()

        def convert_row(row):
            return tuple(
                v.isoformat() if isinstance(v, (date, datetime)) else (float(v) if isinstance(v, Decimal) else v)
                for v in row
            )

        cache_cur = cache_conn.cursor()
        cache_cur.execute("DELETE FROM cached_investment_requests")
        placeholders = ", ".join(["?"] * 52)
        cache_cur.executemany(
            f"INSERT OR REPLACE INTO cached_investment_requests VALUES ({placeholders})",
            [convert_row(row) for row in rows]
        )

        sf_cur.execute("""
            SELECT STEP_ID, REQUEST_ID, STEP_ORDER, APPROVER_EMPLOYEE_ID, APPROVER_NAME,
                   APPROVER_TITLE, STATUS, APPROVED_AT, COMMENTS, IS_FINAL_STEP, CREATED_AT
            FROM TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS
            ORDER BY REQUEST_ID, STEP_ORDER
        """)
        step_rows = sf_cur.fetchall()
        cache_cur.execute("DELETE FROM cached_approval_steps")
        cache_cur.executemany(
            "INSERT OR REPLACE INTO cached_approval_steps VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [convert_row(r) for r in step_rows]
        )

        cache_conn.commit()
        print(f"Background refresh: cached {len(rows)} requests, {len(step_rows)} approval steps")
    finally:
        sf_conn.close()
        cache_conn.close()

def get_cached_timestamps():
    conn = get_cache_connection()
    try:
        cur = conn.cursor()
        cur.execute("SELECT data_source, last_snowflake_modified FROM cache_metadata")
        return {row[0]: row[1] for row in cur.fetchall()}
    finally:
        conn.close()

def needs_refresh(data_sources):
    try:
        with progress_lock:
            cache_progress["status"] = "checking"
            cache_progress["message"] = "Checking cache freshness..."

        sf_timestamps = get_snowflake_timestamps()
        cached_timestamps = get_cached_timestamps()

        for source in data_sources:
            sf_ts = sf_timestamps.get(source)
            cached_ts = cached_timestamps.get(source)

            if sf_ts is None:
                continue
            if cached_ts is None:
                print(f"Cache miss for {source}")
                return True
            if sf_ts > cached_ts:
                print(f"Cache stale for {source}")
                return True

        return False
    except Exception as e:
        print(f"Error checking timestamps: {e}")
        return True

def update_cache_timestamp(data_source, sf_timestamp):
    conn = get_cache_connection()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT OR REPLACE INTO cache_metadata (data_source, last_snowflake_modified, last_cache_refresh)
            VALUES (?, ?, ?)
        """, (data_source, sf_timestamp, datetime.now().isoformat()))
        conn.commit()
    finally:
        conn.close()

def update_progress(step_name, steps_completed, message="", total_steps=7):
    global cache_progress
    with progress_lock:
        cache_progress["status"] = "loading"
        cache_progress["current_step"] = step_name
        cache_progress["steps_completed"] = steps_completed
        cache_progress["total_steps"] = total_steps
        cache_progress["message"] = message

def resolve_approval_chain(employee_id, theater):
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        cur.execute("SELECT APPROVER_EMPLOYEE_ID FROM TEMP.INVESTMENT_GOVERNANCE.FINAL_APPROVERS WHERE THEATER = %s", (theater,))
        fa_row = cur.fetchone()
        if not fa_row:
            return []
        final_approver_eid = int(fa_row[0])

        cur.execute("""
            WITH RECURSIVE chain AS (
                SELECT EMPLOYEE_ID,
                       PREFERRED_NAME_FIRST_NAME || ' ' || PREFERRED_NAME_LAST_NAME AS NAME,
                       BUSINESS_TITLE, MANAGER_ID, 1 AS LEVEL
                FROM HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW
                WHERE EMPLOYEE_ID = %s AND ACTIVE_STATUS = '1'
                UNION ALL
                SELECT w.EMPLOYEE_ID,
                       w.PREFERRED_NAME_FIRST_NAME || ' ' || w.PREFERRED_NAME_LAST_NAME,
                       w.BUSINESS_TITLE, w.MANAGER_ID, c.LEVEL + 1
                FROM HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW w
                JOIN chain c ON w.EMPLOYEE_ID = c.MANAGER_ID
                WHERE w.ACTIVE_STATUS = '1' AND c.LEVEL < 10
            )
            SELECT EMPLOYEE_ID, NAME, BUSINESS_TITLE, LEVEL
            FROM chain WHERE LEVEL > 1 ORDER BY LEVEL
        """, (employee_id,))

        raw_chain = []
        for r in cur.fetchall():
            eid = int(r[0]) if r[0] is not None else None
            raw_chain.append({
                "employee_id": eid,
                "name": r[1],
                "title": r[2],
                "level": r[3],
                "is_final": eid == final_approver_eid
            })
            if eid == final_approver_eid:
                break

        if not raw_chain or raw_chain[-1]["employee_id"] != final_approver_eid:
            cur.execute("""
                SELECT EMPLOYEE_ID, PREFERRED_NAME_FIRST_NAME || ' ' || PREFERRED_NAME_LAST_NAME, BUSINESS_TITLE
                FROM HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW
                WHERE EMPLOYEE_ID = %s AND ACTIVE_STATUS = '1'
            """, (final_approver_eid,))
            fa = cur.fetchone()
            if fa:
                raw_chain.append({
                    "employee_id": int(fa[0]),
                    "name": fa[1],
                    "title": fa[2],
                    "level": (raw_chain[-1]["level"] + 1) if raw_chain else 2,
                    "is_final": True
                })

        return raw_chain
    finally:
        sf_conn.close()

def insert_approval_steps_cache(request_id, chain, cache_conn=None):
    close_conn = cache_conn is None
    if cache_conn is None:
        cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("DELETE FROM cached_approval_steps WHERE request_id = ?", (request_id,))
        for i, step in enumerate(chain):
            cur.execute("""
                INSERT INTO cached_approval_steps
                (step_id, request_id, step_order, approver_employee_id, approver_name,
                 approver_title, status, is_final_step, created_at)
                VALUES (?, ?, ?, ?, ?, ?, 'PENDING', ?, ?)
            """, (
                -(request_id * 100 + i + 1),
                request_id, i + 1, step["employee_id"], step["name"],
                step["title"], 1 if step.get("is_final") else 0,
                datetime.now().isoformat()
            ))
        cache_conn.commit()
    finally:
        if close_conn:
            cache_conn.close()

def get_cached_approval_steps(request_id):
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("""
            SELECT step_id, request_id, step_order, approver_employee_id, approver_name,
                   approver_title, status, approved_at, comments, is_final_step
            FROM cached_approval_steps
            WHERE request_id = ?
            ORDER BY step_order
        """, (request_id,))
        return [{
            "STEP_ID": r["step_id"],
            "REQUEST_ID": r["request_id"],
            "STEP_ORDER": r["step_order"],
            "APPROVER_EMPLOYEE_ID": r["approver_employee_id"],
            "APPROVER_NAME": r["approver_name"],
            "APPROVER_TITLE": r["approver_title"],
            "STATUS": r["status"],
            "APPROVED_AT": r["approved_at"],
            "COMMENTS": r["comments"],
            "IS_FINAL_STEP": bool(r["is_final_step"])
        } for r in cur.fetchall()]
    finally:
        cache_conn.close()

def has_approval_steps(request_id):
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT COUNT(*) FROM cached_approval_steps WHERE request_id = ?", (request_id,))
        return cur.fetchone()[0] > 0
    finally:
        cache_conn.close()

def full_cache_refresh():
    print("Starting full cache refresh...")
    max_retries = 2
    with cache_lock:
        for attempt in range(max_retries + 1):
            try:
                update_progress("connect", 0, "Connecting to Snowflake...")

                sf_conn = get_snowflake_connection()
                cache_conn = get_cache_connection()
                try:
                    sf_cur = sf_conn.cursor()

                    update_progress("current_user", 1, "Identifying current user session...")
                    sf_cur.execute("""
                        SELECT SNOWFLAKE_USERNAME, USER_ID, EMPLOYEE_ID, DISPLAY_NAME, TITLE, ROLE,
                               THEATER, INDUSTRY_SEGMENT, MANAGER_ID, MANAGER_NAME, APPROVAL_LEVEL, IS_FINAL_APPROVER
                        FROM TEMP.INVESTMENT_GOVERNANCE.VW_CURRENT_USER_INFO
                    """)
                    user_row = sf_cur.fetchone()
                    cache_cur = cache_conn.cursor()
                    if user_row:
                        cache_cur.execute("DELETE FROM cached_current_user")
                        cache_cur.execute(
                            "INSERT INTO cached_current_user VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            user_row
                        )
                        cache_conn.commit()
                        print(f"Cached current user: {user_row[0]}")

                    update_progress("final_approvers", 2, "Loading final approvers config...")
                    sf_cur.execute("""
                        SELECT THEATER, APPROVER_EMPLOYEE_ID, APPROVER_NAME, APPROVER_TITLE
                        FROM TEMP.INVESTMENT_GOVERNANCE.FINAL_APPROVERS
                    """)
                    fa_rows = sf_cur.fetchall()
                    cache_cur.execute("DELETE FROM cached_final_approvers")
                    cache_cur.executemany(
                        "INSERT OR REPLACE INTO cached_final_approvers VALUES (?, ?, ?, ?)",
                        fa_rows
                    )
                    cache_conn.commit()
                    print(f"Cached {len(fa_rows)} final approvers")

                    update_progress("requests", 3, "Querying investment requests from Snowflake...")
                    sf_cur.execute("""
                        SELECT REQUEST_ID, REQUEST_TITLE, ACCOUNT_ID, ACCOUNT_NAME, INVESTMENT_TYPE,
                               REQUESTED_AMOUNT, INVESTMENT_QUARTER, BUSINESS_JUSTIFICATION, EXPECTED_OUTCOME,
                               RISK_ASSESSMENT, CREATED_BY, CREATED_BY_NAME, CREATED_BY_EMPLOYEE_ID, CREATED_AT,
                               THEATER, INDUSTRY_SEGMENT, STATUS, CURRENT_APPROVAL_LEVEL, NEXT_APPROVER_ID,
                               NEXT_APPROVER_NAME, NEXT_APPROVER_TITLE, DM_APPROVED_BY, DM_APPROVED_BY_TITLE, DM_APPROVED_AT, DM_COMMENTS,
                               RD_APPROVED_BY, RD_APPROVED_BY_TITLE, RD_APPROVED_AT, RD_COMMENTS, AVP_APPROVED_BY, AVP_APPROVED_BY_TITLE,
                               AVP_APPROVED_AT, AVP_COMMENTS, GVP_APPROVED_BY, GVP_APPROVED_BY_TITLE, GVP_APPROVED_AT, GVP_COMMENTS, UPDATED_AT,
                               WITHDRAWN_BY, WITHDRAWN_BY_NAME, WITHDRAWN_AT, WITHDRAWN_COMMENT,
                               SUBMITTED_COMMENT, SUBMITTED_BY_NAME, SUBMITTED_AT,
                               DRAFT_COMMENT, DRAFT_BY_NAME, DRAFT_AT,
                               ON_BEHALF_OF_EMPLOYEE_ID, ON_BEHALF_OF_NAME,
                               SFDC_OPPORTUNITY_LINK, EXPECTED_ROI
                        FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                        ORDER BY CREATED_AT DESC
                    """)
                    request_rows = sf_cur.fetchall()

                    def convert_row(row):
                        return tuple(
                            v.isoformat() if isinstance(v, (date, datetime)) else (float(v) if isinstance(v, Decimal) else v)
                            for v in row
                        )

                    update_progress("requests_cache", 4, f"Caching {len(request_rows)} investment requests...")
                    cache_cur.execute("DELETE FROM cached_investment_requests")
                    placeholders = ", ".join(["?"] * 52)
                    cache_cur.executemany(
                        f"INSERT OR REPLACE INTO cached_investment_requests VALUES ({placeholders})",
                        [convert_row(row) for row in request_rows]
                    )
                    cache_conn.commit()
                    print(f"Cached {len(request_rows)} investment requests")

                    update_progress("approval_steps", 5, "Caching approval steps...")
                    sf_cur.execute("""
                        SELECT STEP_ID, REQUEST_ID, STEP_ORDER, APPROVER_EMPLOYEE_ID, APPROVER_NAME,
                               APPROVER_TITLE, STATUS, APPROVED_AT, COMMENTS, IS_FINAL_STEP, CREATED_AT
                        FROM TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS
                        ORDER BY REQUEST_ID, STEP_ORDER
                    """)
                    step_rows = sf_cur.fetchall()
                    cache_cur.execute("DELETE FROM cached_approval_steps")
                    cache_cur.executemany(
                        "INSERT OR REPLACE INTO cached_approval_steps VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        [convert_row(r) for r in step_rows]
                    )
                    cache_conn.commit()
                    print(f"Cached {len(step_rows)} approval steps")

                    update_progress("accounts", 6, "Building account lookup cache...")
                    sf_cur.execute("""
                        SELECT '' AS ACCOUNT_ID, ACCOUNT_NAME, THEATER, INDUSTRY_SEGMENT
                        FROM TEMP.INVESTMENT_GOVERNANCE.SFDC_ACCOUNTS
                        WHERE ACCOUNT_NAME IS NOT NULL
                        GROUP BY ACCOUNT_NAME, THEATER, INDUSTRY_SEGMENT
                        ORDER BY ACCOUNT_NAME
                    """)
                    acct_rows = sf_cur.fetchall()
                    cache_cur.execute("DELETE FROM cached_accounts")
                    cache_cur.executemany(
                        "INSERT OR IGNORE INTO cached_accounts VALUES (?, ?, ?, ?)",
                        acct_rows
                    )
                    cache_conn.commit()
                    print(f"Cached {len(acct_rows)} SFDC accounts")

                    sf_timestamps = get_snowflake_timestamps(sf_conn)
                    update_cache_timestamp('INVESTMENT_REQUESTS', sf_timestamps.get('INVESTMENT_REQUESTS'))

                finally:
                    sf_conn.close()
                    cache_conn.close()

                with progress_lock:
                    cache_progress["status"] = "complete"
                    cache_progress["steps_completed"] = 7
                    cache_progress["total_steps"] = 7
                    cache_progress["message"] = "Cache refresh complete"

                print("Full cache refresh complete")
                return
            except Exception as e:
                step = cache_progress.get("current_step", "unknown")
                print(f"Error during cache refresh (attempt {attempt + 1}/{max_retries + 1}, step={step}): {e}")
                if attempt < max_retries:
                    with progress_lock:
                        cache_progress["status"] = "loading"
                        cache_progress["message"] = f"Retrying after error in {step}... (attempt {attempt + 2})"
                    print(f"Retrying cache refresh (attempt {attempt + 2})...")
                    time.sleep(2)
                else:
                    with progress_lock:
                        cache_progress["status"] = "error"
                        cache_progress["message"] = f"Failed to load {step}: {str(e)}"

def startup_cache_check():
    cache_conn = get_cache_connection()
    try:
        acct_count = cache_conn.cursor().execute("SELECT COUNT(*) FROM cached_accounts").fetchone()[0]
    except Exception:
        acct_count = 0
    finally:
        cache_conn.close()

    if acct_count == 0 or needs_refresh(['INVESTMENT_REQUESTS']):
        full_cache_refresh()
    else:
        with progress_lock:
            cache_progress["status"] = "complete"
            cache_progress["message"] = "Cache is fresh"
        print("Cache is fresh, no refresh needed")

def _request_row_to_dict(row):
    return {
        "REQUEST_ID": row["request_id"],
        "REQUEST_TITLE": row["request_title"],
        "ACCOUNT_ID": row["account_id"],
        "ACCOUNT_NAME": row["account_name"],
        "INVESTMENT_TYPE": row["investment_type"],
        "REQUESTED_AMOUNT": row["requested_amount"],
        "INVESTMENT_QUARTER": row["investment_quarter"],
        "BUSINESS_JUSTIFICATION": row["business_justification"],
        "EXPECTED_OUTCOME": row["expected_outcome"],
        "RISK_ASSESSMENT": row["risk_assessment"],
        "CREATED_BY": row["created_by"],
        "CREATED_BY_NAME": row["created_by_name"],
        "CREATED_BY_EMPLOYEE_ID": row["created_by_employee_id"],
        "CREATED_AT": row["created_at"],
        "THEATER": row["theater"],
        "INDUSTRY_SEGMENT": row["industry_segment"],
        "STATUS": row["status"],
        "CURRENT_APPROVAL_LEVEL": row["current_approval_level"],
        "NEXT_APPROVER_ID": row["next_approver_id"],
        "NEXT_APPROVER_NAME": row["next_approver_name"],
        "NEXT_APPROVER_TITLE": row["next_approver_title"],
        "DM_APPROVED_BY": row["dm_approved_by"],
        "DM_APPROVED_BY_TITLE": row["dm_approved_by_title"],
        "DM_APPROVED_AT": row["dm_approved_at"],
        "DM_COMMENTS": row["dm_comments"],
        "RD_APPROVED_BY": row["rd_approved_by"],
        "RD_APPROVED_BY_TITLE": row["rd_approved_by_title"],
        "RD_APPROVED_AT": row["rd_approved_at"],
        "RD_COMMENTS": row["rd_comments"],
        "AVP_APPROVED_BY": row["avp_approved_by"],
        "AVP_APPROVED_BY_TITLE": row["avp_approved_by_title"],
        "AVP_APPROVED_AT": row["avp_approved_at"],
        "AVP_COMMENTS": row["avp_comments"],
        "GVP_APPROVED_BY": row["gvp_approved_by"],
        "GVP_APPROVED_BY_TITLE": row["gvp_approved_by_title"],
        "GVP_APPROVED_AT": row["gvp_approved_at"],
        "GVP_COMMENTS": row["gvp_comments"],
        "UPDATED_AT": row["updated_at"],
        "WITHDRAWN_BY": row["withdrawn_by"],
        "WITHDRAWN_BY_NAME": row["withdrawn_by_name"],
        "WITHDRAWN_AT": row["withdrawn_at"],
        "WITHDRAWN_COMMENT": row["withdrawn_comment"],
        "SUBMITTED_COMMENT": row["submitted_comment"],
        "SUBMITTED_BY_NAME": row["submitted_by_name"],
        "SUBMITTED_AT": row["submitted_at"],
        "DRAFT_COMMENT": row["draft_comment"],
        "DRAFT_BY_NAME": row["draft_by_name"],
        "DRAFT_AT": row["draft_at"],
        "ON_BEHALF_OF_EMPLOYEE_ID": row["on_behalf_of_employee_id"],
        "ON_BEHALF_OF_NAME": row["on_behalf_of_name"],
        "SFDC_OPPORTUNITY_LINK": row["sfdc_opportunity_link"],
        "EXPECTED_ROI": row["expected_roi"],
    }

@app.route('/api/health')
def health():
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

@app.route('/api/cache/progress')
def get_cache_progress():
    with progress_lock:
        return jsonify(cache_progress)

@app.route('/api/cache/refresh', methods=['POST'])
def trigger_cache_refresh():
    with progress_lock:
        if cache_progress.get("status") == "loading":
            return jsonify({"message": "Cache refresh already in progress"}), 409
    threading.Thread(target=full_cache_refresh, daemon=True).start()
    return jsonify({"message": "Cache refresh started"})

@app.route('/api/user')
def get_current_user():
    effective = get_effective_user()
    if effective:
        with impersonation_lock:
            is_impersonating = impersonated_user is not None
        return jsonify({
            "USER_ID": int(effective.get("employee_id", 0)),
            "SNOWFLAKE_USERNAME": effective.get("username", ""),
            "EMPLOYEE_ID": int(effective.get("employee_id", 0)),
            "DISPLAY_NAME": effective.get("display_name", ""),
            "TITLE": effective.get("title", ""),
            "ROLE": effective.get("role", "USER"),
            "THEATER": effective.get("theater", ""),
            "INDUSTRY_SEGMENT": effective.get("industry_segment", ""),
            "MANAGER_ID": int(effective.get("manager_id", 0)) if effective.get("manager_id") is not None else None,
            "MANAGER_NAME": effective.get("manager_name", ""),
            "APPROVAL_LEVEL": int(effective.get("approval_level", 0)),
            "IS_FINAL_APPROVER": effective.get("is_final_approver", False),
            "IS_IMPERSONATING": is_impersonating,
            "REAL_USERNAME": get_real_username() if is_impersonating else None,
            "IS_ADMIN": is_admin()
        })

    sf_conn = get_snowflake_connection()
    try:
        sf_cur = sf_conn.cursor()
        sf_cur.execute("SELECT CURRENT_USER()")
        username = sf_cur.fetchone()[0]
        return jsonify({
            "USER_ID": 0,
            "SNOWFLAKE_USERNAME": username,
            "DISPLAY_NAME": username,
            "TITLE": "User",
            "ROLE": "USER",
            "APPROVAL_LEVEL": 0,
            "IS_FINAL_APPROVER": False,
            "IS_IMPERSONATING": False,
            "IS_ADMIN": username == ADMIN_USERNAME
        })
    finally:
        sf_conn.close()

_employee_search_cache = {}
_employee_search_cache_time = {}
EMPLOYEE_SEARCH_CACHE_TTL = 300

@app.route('/api/employees/search')
def search_employees():
    if not is_admin():
        return jsonify({"error": "Admin access required"}), 403
    query = request.args.get('q', '').strip().lower()
    if len(query) < 2:
        return jsonify([])

    now = time.time()
    if query in _employee_search_cache and (now - _employee_search_cache_time.get(query, 0)) < EMPLOYEE_SEARCH_CACHE_TTL:
        return jsonify(_employee_search_cache[query])

    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        cur.execute("""
            SELECT EMPLOYEE_ID,
                   PREFERRED_NAME_FIRST_NAME || ' ' || PREFERRED_NAME_LAST_NAME AS NAME,
                   BUSINESS_TITLE, MANAGER_NAME, DEPARTMENT
            FROM HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW
            WHERE ACTIVE_STATUS = '1'
              AND (PREFERRED_NAME_FIRST_NAME ILIKE %s
                   OR PREFERRED_NAME_LAST_NAME ILIKE %s
                   OR (PREFERRED_NAME_FIRST_NAME || ' ' || PREFERRED_NAME_LAST_NAME) ILIKE %s)
            ORDER BY PREFERRED_NAME_LAST_NAME, PREFERRED_NAME_FIRST_NAME
            LIMIT 20
        """, (f'%{query}%', f'%{query}%', f'%{query}%'))
        results = [{
            "EMPLOYEE_ID": r[0], "NAME": r[1], "TITLE": r[2],
            "MANAGER_NAME": r[3], "DEPARTMENT": r[4]
        } for r in cur.fetchall()]
        _employee_search_cache[query] = results
        _employee_search_cache_time[query] = now
        return jsonify(results)
    finally:
        sf_conn.close()

@app.route('/api/impersonate', methods=['POST'])
def impersonate():
    global impersonated_user
    if not is_admin():
        return jsonify({"error": "Admin access required"}), 403
    data = request.json or {}
    employee_id = data.get("EMPLOYEE_ID")
    if not employee_id:
        return jsonify({"error": "EMPLOYEE_ID required"}), 400

    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        cur.execute("""
            SELECT w.EMPLOYEE_ID,
                   UPPER(CONCAT(LEFT(w.PREFERRED_NAME_FIRST_NAME, 1), REPLACE(w.PREFERRED_NAME_LAST_NAME, ' ', ''))) AS USERNAME,
                   w.PREFERRED_NAME_FIRST_NAME || ' ' || w.PREFERRED_NAME_LAST_NAME AS DISPLAY_NAME,
                   w.BUSINESS_TITLE, w.MANAGER_ID, w.MANAGER_NAME,
                   w.IS_MANAGER, w.COST_CENTER_NAME, w.DEPARTMENT
            FROM HR.WORKDAY_BASIC.SFDC_WORKDAY_USER_VW w
            WHERE w.EMPLOYEE_ID = %s AND w.ACTIVE_STATUS = '1'
        """, (employee_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Employee not found"}), 404

        cur.execute("""
            SELECT APPROVER_EMPLOYEE_ID FROM TEMP.INVESTMENT_GOVERNANCE.FINAL_APPROVERS
            WHERE APPROVER_EMPLOYEE_ID = %s
        """, (row[0],))
        is_fa = cur.fetchone() is not None

        with impersonation_lock:
            impersonated_user = {
                "username": row[1],
                "employee_id": int(row[0]) if row[0] is not None else 0,
                "display_name": row[2],
                "title": row[3],
                "manager_id": int(row[4]) if row[4] is not None else None,
                "manager_name": row[5],
                "role": "FINAL_APPROVER" if is_fa else ("MANAGER" if row[6] == 1 else "USER"),
                "theater": row[7],
                "industry_segment": None,
                "approval_level": 99 if is_fa else 0,
                "is_final_approver": is_fa
            }

        return jsonify({
            "message": f"Now acting as {row[2]}",
            "user": impersonated_user
        })
    finally:
        sf_conn.close()

@app.route('/api/stop-impersonate', methods=['POST'])
def stop_impersonate():
    global impersonated_user
    with impersonation_lock:
        impersonated_user = None
    return jsonify({"message": "Stopped impersonating", "user": get_cached_user_info()})

@app.route('/api/impersonate/status')
def impersonate_status():
    with impersonation_lock:
        if impersonated_user is not None:
            return jsonify({
                "active": True,
                "employee_id": impersonated_user["employee_id"],
                "display_name": impersonated_user["display_name"],
                "title": impersonated_user["title"]
            })
    return jsonify({"active": False})

@app.route('/api/approval-chain')
def get_approval_chain_endpoint():
    employee_id = request.args.get('employee_id', type=int)
    theater = request.args.get('theater')
    if not employee_id or not theater:
        return jsonify({"error": "employee_id and theater are required"}), 400
    chain = resolve_approval_chain(employee_id, theater)
    return jsonify(chain)

@app.route('/api/summary')
def get_summary():
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()

        cur.execute("SELECT COUNT(*) FROM cached_investment_requests")
        total = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM cached_investment_requests WHERE status = 'DRAFT'")
        draft = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM cached_investment_requests WHERE status IN ('SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED')")
        submitted = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM cached_investment_requests WHERE status = 'FINAL_APPROVED'")
        approved = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM cached_investment_requests WHERE status = 'REJECTED'")
        rejected = cur.fetchone()[0]

        effective = get_effective_user()
        current_user_name = effective["display_name"] if effective else None

        pending_my = 0
        if current_user_name:
            cur.execute("SELECT COUNT(*) FROM cached_investment_requests WHERE next_approver_name = ?", (current_user_name,))
            pending_my = cur.fetchone()[0]

        cur.execute("SELECT COALESCE(SUM(requested_amount), 0) FROM cached_investment_requests")
        total_requested = cur.fetchone()[0]

        cur.execute("SELECT COALESCE(SUM(requested_amount), 0) FROM cached_investment_requests WHERE status = 'FINAL_APPROVED'")
        total_approved_amt = cur.fetchone()[0]

        return jsonify({
            "TOTAL_REQUESTS": total,
            "TOTAL_DRAFT": draft,
            "TOTAL_SUBMITTED": submitted,
            "TOTAL_APPROVED": approved,
            "TOTAL_REJECTED": rejected,
            "TOTAL_PENDING_MY_APPROVAL": pending_my,
            "TOTAL_INVESTMENT_REQUESTED": total_requested or 0,
            "TOTAL_INVESTMENT_APPROVED": total_approved_amt or 0
        })
    finally:
        cache_conn.close()

@app.route('/api/budgets')
def get_budgets():
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        cur.execute("""
            SELECT BUDGET_ID, FISCAL_YEAR, THEATER, INDUSTRY_SEGMENT, PORTFOLIO, BUDGET_AMOUNT, ALLOCATED_AMOUNT,
                   Q1_BUDGET, Q2_BUDGET, Q3_BUDGET, Q4_BUDGET
            FROM TEMP.INVESTMENT_GOVERNANCE.ANNUAL_BUDGETS
            ORDER BY FISCAL_YEAR DESC, THEATER, INDUSTRY_SEGMENT
        """)
        rows = cur.fetchall()
        columns = ['BUDGET_ID', 'FISCAL_YEAR', 'THEATER', 'INDUSTRY_SEGMENT', 'PORTFOLIO', 'BUDGET_AMOUNT', 'ALLOCATED_AMOUNT',
                   'Q1_BUDGET', 'Q2_BUDGET', 'Q3_BUDGET', 'Q4_BUDGET']
        return jsonify([dict(zip(columns, [float(v) if isinstance(v, Decimal) else v for v in row])) for row in rows])
    except Exception as e:
        print(f"Error fetching budgets: {e}")
        return jsonify([])
    finally:
        sf_conn.close()

@app.route('/api/requests')
def get_requests():
    theater = request.args.get('theater')
    industry_segment = request.args.get('industry_segment')
    quarter = request.args.get('quarter')
    status = request.args.get('status')

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()

        query = "SELECT * FROM cached_investment_requests WHERE 1=1"
        params = []

        if theater:
            query += " AND theater = ?"
            params.append(theater)
        if industry_segment:
            query += " AND industry_segment = ?"
            params.append(industry_segment)
        if quarter:
            query += " AND investment_quarter = ?"
            params.append(quarter)
        if status:
            query += " AND status = ?"
            params.append(status)

        query += " ORDER BY created_at DESC"

        cur.execute(query, params)
        rows = cur.fetchall()

        return jsonify([_request_row_to_dict(row) for row in rows])
    finally:
        cache_conn.close()

@app.route('/api/requests/<int:request_id>')
def get_request(request_id):
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT * FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()

        if not row:
            return jsonify({"error": "Request not found"}), 404

        result = _request_row_to_dict(row)
        result["APPROVAL_STEPS"] = get_cached_approval_steps(request_id)
        return jsonify(result)
    finally:
        cache_conn.close()

@app.route('/api/requests/<int:request_id>/steps')
def get_request_steps(request_id):
    return jsonify(get_cached_approval_steps(request_id))

@app.route('/api/requests', methods=['POST'])
def create_request():
    data = request.json

    user_info = get_effective_user()
    if not user_info:
        return jsonify({"error": "User info not available"}), 500

    current_user = user_info["username"]
    created_by_name = user_info["display_name"] or current_user
    employee_id = user_info["employee_id"]
    manager_name = user_info["manager_name"]
    now_iso = datetime.now().isoformat()

    with impersonation_lock:
        is_impersonating = impersonated_user is not None
    real_user = get_cached_user_info() if is_impersonating else None

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT COALESCE(MIN(request_id), 0) - 1 FROM cached_investment_requests WHERE request_id < 0")
        temp_id = cur.fetchone()[0]
        if temp_id >= 0:
            temp_id = -1
    finally:
        cache_conn.close()

    row_dict = {
        "request_id": temp_id,
        "request_title": data.get('REQUEST_TITLE'),
        "account_id": data.get('ACCOUNT_ID'),
        "account_name": data.get('ACCOUNT_NAME'),
        "investment_type": data.get('INVESTMENT_TYPE'),
        "requested_amount": data.get('REQUESTED_AMOUNT'),
        "investment_quarter": data.get('INVESTMENT_QUARTER'),
        "business_justification": data.get('BUSINESS_JUSTIFICATION'),
        "expected_outcome": data.get('EXPECTED_OUTCOME'),
        "risk_assessment": data.get('RISK_ASSESSMENT'),
        "created_by": current_user,
        "created_by_name": created_by_name,
        "created_by_employee_id": employee_id,
        "created_at": now_iso,
        "theater": data.get('THEATER'),
        "industry_segment": data.get('INDUSTRY_SEGMENT'),
        "status": "DRAFT",
        "current_approval_level": 0,
        "next_approver_name": manager_name,
        "updated_at": now_iso,
        "on_behalf_of_employee_id": employee_id if is_impersonating else None,
        "on_behalf_of_name": created_by_name if is_impersonating else None,
        "sfdc_opportunity_link": data.get('SFDC_OPPORTUNITY_LINK'),
        "expected_roi": data.get('EXPECTED_ROI'),
    }
    insert_cache_request(row_dict)

    auto_submit = data.get('AUTO_SUBMIT', False)
    submit_comment = data.get('SUBMIT_COMMENT')
    chain = []

    if auto_submit:
        ae_employee_id = row_dict["on_behalf_of_employee_id"] or row_dict["created_by_employee_id"]
        theater = row_dict["theater"]
        chain = resolve_approval_chain(ae_employee_id, theater) if ae_employee_id and theater else []

        next_approver_name = chain[0]["name"] if chain else None
        next_approver_title = chain[0]["title"] if chain else None
        next_approver_eid = chain[0]["employee_id"] if chain else None

        submit_updates = {
            "status": "SUBMITTED",
            "current_approval_level": 1,
            "next_approver_name": next_approver_name,
            "next_approver_title": next_approver_title,
            "next_approver_id": next_approver_eid,
            "submitted_comment": submit_comment,
            "submitted_by_name": created_by_name,
            "submitted_at": now_iso,
            "updated_at": now_iso
        }
        update_cache_request(temp_id, submit_updates)

        if chain:
            insert_approval_steps_cache(temp_id, chain)

    sf_created_by = current_user
    sf_created_by_name = created_by_name
    sf_employee_id = employee_id
    on_behalf_eid = employee_id if is_impersonating else None
    on_behalf_name = created_by_name if is_impersonating else None
    sf_status = "SUBMITTED" if auto_submit else "DRAFT"
    sf_next_approver = chain[0]["name"] if (auto_submit and chain) else manager_name
    sf_next_approver_title = chain[0]["title"] if (auto_submit and chain) else None
    sf_next_approver_eid = chain[0]["employee_id"] if (auto_submit and chain) else None
    chain_for_sync = list(chain)

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            cur.execute("""
                INSERT INTO TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                (REQUEST_TITLE, ACCOUNT_ID, ACCOUNT_NAME, INVESTMENT_TYPE, REQUESTED_AMOUNT,
                 INVESTMENT_QUARTER, BUSINESS_JUSTIFICATION, EXPECTED_OUTCOME, RISK_ASSESSMENT,
                 CREATED_BY, CREATED_BY_NAME, CREATED_BY_EMPLOYEE_ID, THEATER, INDUSTRY_SEGMENT,
                 STATUS, NEXT_APPROVER_NAME, NEXT_APPROVER_TITLE, NEXT_APPROVER_ID,
                 SUBMITTED_COMMENT, SUBMITTED_BY_NAME, SUBMITTED_AT,
                 ON_BEHALF_OF_EMPLOYEE_ID, ON_BEHALF_OF_NAME,
                 SFDC_OPPORTUNITY_LINK, EXPECTED_ROI)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        {0}, %s, %s, %s, %s)
            """.format("CURRENT_TIMESTAMP()" if auto_submit else "NULL"), (
                data.get('REQUEST_TITLE'), data.get('ACCOUNT_ID'), data.get('ACCOUNT_NAME'),
                data.get('INVESTMENT_TYPE'), data.get('REQUESTED_AMOUNT'), data.get('INVESTMENT_QUARTER'),
                data.get('BUSINESS_JUSTIFICATION'), data.get('EXPECTED_OUTCOME'), data.get('RISK_ASSESSMENT'),
                sf_created_by, sf_created_by_name, sf_employee_id,
                data.get('THEATER'), data.get('INDUSTRY_SEGMENT'), sf_status,
                sf_next_approver, sf_next_approver_title, sf_next_approver_eid,
                submit_comment, sf_created_by_name if auto_submit else None,
                on_behalf_eid, on_behalf_name,
                data.get('SFDC_OPPORTUNITY_LINK'), data.get('EXPECTED_ROI')
            ))

            if auto_submit and chain_for_sync:
                new_id_row = cur.execute("SELECT MAX(REQUEST_ID) FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE CREATED_BY = %s", (sf_created_by,)).fetchone()
                new_request_id = new_id_row[0] if new_id_row else None
                if new_request_id:
                    for i, step in enumerate(chain_for_sync):
                        cur.execute("""
                            INSERT INTO TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS
                            (REQUEST_ID, STEP_ORDER, APPROVER_EMPLOYEE_ID, APPROVER_NAME, APPROVER_TITLE, STATUS, IS_FINAL_STEP)
                            VALUES (%s, %s, %s, %s, %s, 'PENDING', %s)
                        """, (new_request_id, i + 1, step["employee_id"], step["name"], step["title"], step.get("is_final", False)))

            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    resp = {"REQUEST_ID": temp_id, "message": "Request created"}
    if auto_submit:
        resp["message"] = "Request created and submitted"
        resp["chain"] = chain
    return jsonify(resp), 201

@app.route('/api/requests/<int:request_id>', methods=['PUT'])
def update_request(request_id):
    data = request.json

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row["status"] != 'DRAFT':
            return jsonify({"error": "Cannot edit request that is not in DRAFT status"}), 400
    finally:
        cache_conn.close()

    col_map = {
        'REQUEST_TITLE': 'request_title', 'ACCOUNT_ID': 'account_id', 'ACCOUNT_NAME': 'account_name',
        'INVESTMENT_TYPE': 'investment_type', 'REQUESTED_AMOUNT': 'requested_amount',
        'INVESTMENT_QUARTER': 'investment_quarter', 'BUSINESS_JUSTIFICATION': 'business_justification',
        'EXPECTED_OUTCOME': 'expected_outcome', 'RISK_ASSESSMENT': 'risk_assessment',
        'THEATER': 'theater', 'INDUSTRY_SEGMENT': 'industry_segment',
        'SFDC_OPPORTUNITY_LINK': 'sfdc_opportunity_link', 'EXPECTED_ROI': 'expected_roi'
    }
    cache_updates = {}
    for key, col in col_map.items():
        if key in data:
            cache_updates[col] = data[key]

    draft_comment = data.get('DRAFT_COMMENT')
    user_info = get_effective_user()
    now_iso = datetime.now().isoformat()
    if draft_comment:
        draft_by_name = user_info["display_name"] if user_info else None
        cache_updates["draft_comment"] = draft_comment
        cache_updates["draft_by_name"] = draft_by_name
        cache_updates["draft_at"] = now_iso

    if cache_updates:
        cache_updates["updated_at"] = now_iso
        update_cache_request(request_id, cache_updates)

    auto_submit = data.get('AUTO_SUBMIT', False)
    submit_comment = data.get('SUBMIT_COMMENT')
    chain = []

    if auto_submit:
        cache_conn2 = get_cache_connection()
        try:
            cur2 = cache_conn2.cursor()
            cur2.execute("SELECT created_by_employee_id, theater, on_behalf_of_employee_id FROM cached_investment_requests WHERE request_id = ?", (request_id,))
            row2 = cur2.fetchone()
            ae_employee_id = row2["on_behalf_of_employee_id"] or row2["created_by_employee_id"] if row2 else None
            theater = row2["theater"] if row2 else None
        finally:
            cache_conn2.close()

        chain = resolve_approval_chain(ae_employee_id, theater) if ae_employee_id and theater else []
        next_approver_name = chain[0]["name"] if chain else None
        next_approver_title = chain[0]["title"] if chain else None
        next_approver_eid = chain[0]["employee_id"] if chain else None
        submitted_by_name = user_info["display_name"] if user_info else None

        submit_updates = {
            "status": "SUBMITTED",
            "current_approval_level": 1,
            "next_approver_name": next_approver_name,
            "next_approver_title": next_approver_title,
            "next_approver_id": next_approver_eid,
            "submitted_comment": submit_comment,
            "submitted_by_name": submitted_by_name,
            "submitted_at": now_iso,
            "updated_at": now_iso
        }
        update_cache_request(request_id, submit_updates)
        if chain:
            insert_approval_steps_cache(request_id, chain)

    chain_for_sync = list(chain)

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            updates = []
            params = []
            for key in col_map:
                if key in data:
                    updates.append(f"{key} = %s")
                    params.append(data[key])
            if draft_comment:
                updates.append("DRAFT_COMMENT = %s")
                params.append(draft_comment)
                updates.append("DRAFT_BY_NAME = %s")
                params.append(user_info["display_name"] if user_info else None)
                updates.append("DRAFT_AT = CURRENT_TIMESTAMP()")
            if auto_submit:
                updates.append("STATUS = 'SUBMITTED'")
                updates.append("CURRENT_APPROVAL_LEVEL = 1")
                updates.append("NEXT_APPROVER_NAME = %s")
                params.append(chain_for_sync[0]["name"] if chain_for_sync else None)
                updates.append("NEXT_APPROVER_TITLE = %s")
                params.append(chain_for_sync[0]["title"] if chain_for_sync else None)
                updates.append("NEXT_APPROVER_ID = %s")
                params.append(chain_for_sync[0]["employee_id"] if chain_for_sync else None)
                updates.append("SUBMITTED_COMMENT = %s")
                params.append(submit_comment)
                updates.append("SUBMITTED_BY_NAME = %s")
                params.append(user_info["display_name"] if user_info else None)
                updates.append("SUBMITTED_AT = CURRENT_TIMESTAMP()")
            if updates:
                updates.append("UPDATED_AT = CURRENT_TIMESTAMP()")
                params.append(request_id)
                cur.execute(f"""
                    UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                    SET {', '.join(updates)}
                    WHERE REQUEST_ID = %s
                """, params)

                if auto_submit and chain_for_sync:
                    cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS WHERE REQUEST_ID = %s", (request_id,))
                    for i, step in enumerate(chain_for_sync):
                        cur.execute("""
                            INSERT INTO TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS
                            (REQUEST_ID, STEP_ORDER, APPROVER_EMPLOYEE_ID, APPROVER_NAME, APPROVER_TITLE, STATUS, IS_FINAL_STEP)
                            VALUES (%s, %s, %s, %s, %s, 'PENDING', %s)
                        """, (request_id, i + 1, step["employee_id"], step["name"], step["title"], step.get("is_final", False)))

                sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    resp = {"message": "Request updated"}
    if auto_submit:
        resp["message"] = "Request updated and submitted"
        resp["chain"] = chain
    return jsonify(resp)

@app.route('/api/requests/<int:request_id>', methods=['DELETE'])
def delete_request(request_id):
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row["status"] != 'DRAFT':
            return jsonify({"error": "Cannot delete request that is not in DRAFT status"}), 400
    finally:
        cache_conn.close()

    delete_cache_request(request_id)

    cache_conn2 = get_cache_connection()
    try:
        cache_conn2.cursor().execute("DELETE FROM cached_approval_steps WHERE request_id = ?", (request_id,))
        cache_conn2.commit()
    finally:
        cache_conn2.close()

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS WHERE REQUEST_ID = %s", (request_id,))
            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.REQUEST_OPPORTUNITIES WHERE REQUEST_ID = %s", (request_id,))
            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.REQUEST_CONTRIBUTORS WHERE REQUEST_ID = %s", (request_id,))
            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.SUGGESTED_CHANGES WHERE REQUEST_ID = %s", (request_id,))
            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE REQUEST_ID = %s", (request_id,))
            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    return jsonify({"message": "Request deleted"})

@app.route('/api/requests/<int:request_id>/submit', methods=['POST'])
def submit_request(request_id):
    data = request.json or {}
    comment = data.get('COMMENT')

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status, created_by_employee_id, theater, on_behalf_of_employee_id FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row["status"] != 'DRAFT':
            return jsonify({"error": "Can only submit requests in DRAFT status"}), 400
        ae_employee_id = row["on_behalf_of_employee_id"] or row["created_by_employee_id"]
        theater = row["theater"]
    finally:
        cache_conn.close()

    chain = resolve_approval_chain(ae_employee_id, theater) if ae_employee_id and theater else []

    user_info = get_effective_user()
    submitted_by_name = user_info["display_name"] if user_info else None
    now_iso = datetime.now().isoformat()

    next_approver_name = chain[0]["name"] if chain else None
    next_approver_title = chain[0]["title"] if chain else None
    next_approver_eid = chain[0]["employee_id"] if chain else None

    cache_updates = {
        "status": "SUBMITTED",
        "current_approval_level": 1,
        "next_approver_name": next_approver_name,
        "next_approver_title": next_approver_title,
        "next_approver_id": next_approver_eid,
        "submitted_comment": comment,
        "submitted_by_name": submitted_by_name,
        "submitted_at": now_iso,
        "updated_at": now_iso
    }
    update_cache_request(request_id, cache_updates)

    if chain:
        insert_approval_steps_cache(request_id, chain)

    chain_for_sync = list(chain)

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            cur.execute("""
                UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                SET STATUS = 'SUBMITTED', CURRENT_APPROVAL_LEVEL = 1,
                    NEXT_APPROVER_NAME = %s, NEXT_APPROVER_TITLE = %s, NEXT_APPROVER_ID = %s,
                    SUBMITTED_COMMENT = %s, SUBMITTED_BY_NAME = %s, SUBMITTED_AT = CURRENT_TIMESTAMP(),
                    UPDATED_AT = CURRENT_TIMESTAMP()
                WHERE REQUEST_ID = %s
            """, (next_approver_name, next_approver_title, next_approver_eid, comment, submitted_by_name, request_id))

            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS WHERE REQUEST_ID = %s", (request_id,))
            for i, step in enumerate(chain_for_sync):
                cur.execute("""
                    INSERT INTO TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS
                    (REQUEST_ID, STEP_ORDER, APPROVER_EMPLOYEE_ID, APPROVER_NAME, APPROVER_TITLE, STATUS, IS_FINAL_STEP)
                    VALUES (%s, %s, %s, %s, %s, 'PENDING', %s)
                """, (request_id, i + 1, step["employee_id"], step["name"], step["title"], step.get("is_final", False)))

            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    return jsonify({"message": "Request submitted for approval", "chain": chain})

@app.route('/api/requests/<int:request_id>/withdraw', methods=['POST'])
def withdraw_request(request_id):
    data = request.json or {}
    comment = data.get('COMMENT', '')

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        current_status = row["status"]
        if current_status not in ['SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED'] and current_status != 'SUBMITTED':
            if not has_approval_steps(request_id) and current_status not in ['SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED']:
                return jsonify({"error": "Cannot withdraw request in current status"}), 400
    finally:
        cache_conn.close()

    user_info = get_effective_user()
    current_user = user_info["username"] if user_info else "UNKNOWN"
    withdrawn_by_name = user_info["display_name"] if user_info else current_user
    now_iso = datetime.now().isoformat()

    update_cache_request(request_id, {
        "status": "DRAFT",
        "current_approval_level": 0,
        "next_approver_name": None, "next_approver_title": None, "next_approver_id": None,
        "dm_approved_by": None, "dm_approved_by_title": None, "dm_approved_at": None, "dm_comments": None,
        "rd_approved_by": None, "rd_approved_by_title": None, "rd_approved_at": None, "rd_comments": None,
        "avp_approved_by": None, "avp_approved_by_title": None, "avp_approved_at": None, "avp_comments": None,
        "gvp_approved_by": None, "gvp_approved_by_title": None, "gvp_approved_at": None, "gvp_comments": None,
        "withdrawn_by": current_user, "withdrawn_by_name": withdrawn_by_name,
        "withdrawn_at": now_iso, "withdrawn_comment": comment,
        "updated_at": now_iso
    })

    cache_conn2 = get_cache_connection()
    try:
        cache_conn2.cursor().execute("DELETE FROM cached_approval_steps WHERE request_id = ?", (request_id,))
        cache_conn2.commit()
    finally:
        cache_conn2.close()

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS WHERE REQUEST_ID = %s", (request_id,))
            cur.execute("""
                UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                SET STATUS = 'DRAFT', CURRENT_APPROVAL_LEVEL = 0,
                    NEXT_APPROVER_NAME = NULL, NEXT_APPROVER_TITLE = NULL, NEXT_APPROVER_ID = NULL,
                    DM_APPROVED_BY = NULL, DM_APPROVED_BY_TITLE = NULL, DM_APPROVED_AT = NULL, DM_COMMENTS = NULL,
                    RD_APPROVED_BY = NULL, RD_APPROVED_BY_TITLE = NULL, RD_APPROVED_AT = NULL, RD_COMMENTS = NULL,
                    AVP_APPROVED_BY = NULL, AVP_APPROVED_BY_TITLE = NULL, AVP_APPROVED_AT = NULL, AVP_COMMENTS = NULL,
                    GVP_APPROVED_BY = NULL, GVP_APPROVED_BY_TITLE = NULL, GVP_APPROVED_AT = NULL, GVP_COMMENTS = NULL,
                    WITHDRAWN_BY = %s, WITHDRAWN_BY_NAME = %s, WITHDRAWN_AT = CURRENT_TIMESTAMP(), WITHDRAWN_COMMENT = %s,
                    UPDATED_AT = CURRENT_TIMESTAMP()
                WHERE REQUEST_ID = %s
            """, (current_user, withdrawn_by_name, comment, request_id))
            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    return jsonify({"message": "Request withdrawn to draft"})

@app.route('/api/requests/<int:request_id>/approve', methods=['POST'])
def approve_request(request_id):
    data = request.json or {}
    comments = data.get('COMMENTS')

    user_info = get_effective_user()
    approver_name = user_info["display_name"] if user_info else "UNKNOWN"
    approver_title = user_info["title"] if user_info else None
    approver_eid = user_info["employee_id"] if user_info else None

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status, current_approval_level FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        current_status = row["status"]
    finally:
        cache_conn.close()

    use_dynamic = has_approval_steps(request_id)

    if use_dynamic:
        steps = get_cached_approval_steps(request_id)
        current_step = next((s for s in steps if s["STATUS"] == "PENDING"), None)
        if not current_step:
            return jsonify({"error": "No pending approval step found"}), 400

        now_iso = datetime.now().isoformat()
        step_order = current_step["STEP_ORDER"]
        is_final = current_step["IS_FINAL_STEP"]

        cache_conn2 = get_cache_connection()
        try:
            cache_conn2.cursor().execute("""
                UPDATE cached_approval_steps
                SET status = 'APPROVED', approved_at = ?, comments = ?
                WHERE request_id = ? AND step_order = ?
            """, (now_iso, comments, request_id, step_order))
            cache_conn2.commit()
        finally:
            cache_conn2.close()

        if is_final:
            new_status = "FINAL_APPROVED"
            next_name = None
            next_title = None
            next_eid = None
        else:
            next_step = next((s for s in steps if s["STEP_ORDER"] == step_order + 1), None)
            new_status = "SUBMITTED"
            next_name = next_step["APPROVER_NAME"] if next_step else None
            next_title = next_step["APPROVER_TITLE"] if next_step else None
            next_eid = next_step["APPROVER_EMPLOYEE_ID"] if next_step else None

        legacy_col_map = {1: "dm", 2: "rd", 3: "avp", 4: "gvp"}
        legacy_prefix = legacy_col_map.get(step_order)
        legacy_updates = {}
        if legacy_prefix:
            legacy_updates[f"{legacy_prefix}_approved_by"] = approver_name
            legacy_updates[f"{legacy_prefix}_approved_by_title"] = approver_title
            legacy_updates[f"{legacy_prefix}_approved_at"] = now_iso
            legacy_updates[f"{legacy_prefix}_comments"] = comments

        cache_update = {
            "status": new_status,
            "current_approval_level": step_order + 1 if not is_final else step_order,
            "next_approver_name": next_name,
            "next_approver_title": next_title,
            "next_approver_id": next_eid,
            "updated_at": now_iso,
            **legacy_updates
        }
        update_cache_request(request_id, cache_update)

        sf_step_order = step_order
        sf_is_final = is_final
        sf_new_status = new_status
        sf_next_name = next_name
        sf_next_title = next_title
        sf_next_eid = next_eid

        def _sync():
            sf_conn = get_snowflake_connection()
            try:
                sf_cur = sf_conn.cursor()
                sf_cur.execute("""
                    UPDATE TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS
                    SET STATUS = 'APPROVED', APPROVED_AT = CURRENT_TIMESTAMP(), COMMENTS = %s
                    WHERE REQUEST_ID = %s AND STEP_ORDER = %s
                """, (comments, request_id, sf_step_order))

                sf_updates = ["STATUS = %s", "CURRENT_APPROVAL_LEVEL = %s",
                              "NEXT_APPROVER_NAME = %s", "NEXT_APPROVER_TITLE = %s", "NEXT_APPROVER_ID = %s",
                              "UPDATED_AT = CURRENT_TIMESTAMP()"]
                sf_params = [sf_new_status, sf_step_order + 1 if not sf_is_final else sf_step_order,
                             sf_next_name, sf_next_title, sf_next_eid]

                lp = legacy_col_map.get(sf_step_order)
                if lp:
                    sf_updates.extend([
                        f"{lp.upper()}_APPROVED_BY = %s",
                        f"{lp.upper()}_APPROVED_BY_TITLE = %s",
                        f"{lp.upper()}_APPROVED_AT = CURRENT_TIMESTAMP()",
                        f"{lp.upper()}_COMMENTS = %s"
                    ])
                    sf_params.extend([approver_name, approver_title, comments])

                sf_params.append(request_id)
                sf_cur.execute(f"""
                    UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                    SET {', '.join(sf_updates)}
                    WHERE REQUEST_ID = %s
                """, sf_params)
                sf_conn.commit()
            finally:
                sf_conn.close()

        sync_to_snowflake(_sync)
        return jsonify({"message": f"Request approved, new status: {new_status}"})

    else:
        status_transitions = {
            'SUBMITTED': ('DM_APPROVED', 'dm_approved_by', 'dm_approved_by_title', 'dm_approved_at', 'dm_comments', 2),
            'DM_APPROVED': ('RD_APPROVED', 'rd_approved_by', 'rd_approved_by_title', 'rd_approved_at', 'rd_comments', 3),
            'RD_APPROVED': ('AVP_APPROVED', 'avp_approved_by', 'avp_approved_by_title', 'avp_approved_at', 'avp_comments', 4),
            'AVP_APPROVED': ('FINAL_APPROVED', 'gvp_approved_by', 'gvp_approved_by_title', 'gvp_approved_at', 'gvp_comments', 5)
        }

        if current_status not in status_transitions:
            return jsonify({"error": "Request cannot be approved in current status"}), 400

        new_status, approver_col, title_col, time_col, comments_col, new_level = status_transitions[current_status]
        now_iso = datetime.now().isoformat()

        update_cache_request(request_id, {
            "status": new_status,
            approver_col: approver_name,
            title_col: approver_title,
            time_col: now_iso,
            comments_col: comments,
            "current_approval_level": new_level,
            "updated_at": now_iso
        })

        sf_transitions = {
            'SUBMITTED': ('DM_APPROVED', 'DM_APPROVED_BY', 'DM_APPROVED_BY_TITLE', 'DM_APPROVED_AT', 'DM_COMMENTS', 2),
            'DM_APPROVED': ('RD_APPROVED', 'RD_APPROVED_BY', 'RD_APPROVED_BY_TITLE', 'RD_APPROVED_AT', 'RD_COMMENTS', 3),
            'RD_APPROVED': ('AVP_APPROVED', 'AVP_APPROVED_BY', 'AVP_APPROVED_BY_TITLE', 'AVP_APPROVED_AT', 'AVP_COMMENTS', 4),
            'AVP_APPROVED': ('FINAL_APPROVED', 'GVP_APPROVED_BY', 'GVP_APPROVED_BY_TITLE', 'GVP_APPROVED_AT', 'GVP_COMMENTS', 5)
        }

        def _sync():
            sf_new_status, sf_approver_col, sf_title_col, sf_time_col, sf_comments_col, sf_new_level = sf_transitions[current_status]
            sf_conn = get_snowflake_connection()
            try:
                cur = sf_conn.cursor()
                cur.execute(f"""
                    UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                    SET STATUS = %s, {sf_approver_col} = %s, {sf_title_col} = %s, {sf_time_col} = CURRENT_TIMESTAMP(), {sf_comments_col} = %s,
                        CURRENT_APPROVAL_LEVEL = %s, UPDATED_AT = CURRENT_TIMESTAMP()
                    WHERE REQUEST_ID = %s
                """, (sf_new_status, approver_name, approver_title, comments, sf_new_level, request_id))
                sf_conn.commit()
            finally:
                sf_conn.close()

        sync_to_snowflake(_sync)
        return jsonify({"message": f"Request approved, new status: {new_status}"})

@app.route('/api/requests/<int:request_id>/reject', methods=['POST'])
def reject_request(request_id):
    data = request.json or {}
    comments = data.get('COMMENTS')

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row["status"] not in ['SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED']:
            return jsonify({"error": "Request cannot be rejected in current status"}), 400
    finally:
        cache_conn.close()

    user_info = get_effective_user()
    now_iso = datetime.now().isoformat()

    update_cache_request(request_id, {
        "status": "REJECTED",
        "gvp_comments": comments,
        "updated_at": now_iso
    })

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            cur.execute("""
                UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                SET STATUS = 'REJECTED', GVP_COMMENTS = %s, UPDATED_AT = CURRENT_TIMESTAMP()
                WHERE REQUEST_ID = %s
            """, (comments, request_id))
            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    return jsonify({"message": "Request rejected"})

@app.route('/api/requests/<int:request_id>/revise', methods=['POST'])
def revise_request(request_id):
    data = request.json or {}
    justification = data.get('BUSINESS_JUSTIFICATION')
    outcome = data.get('EXPECTED_OUTCOME')
    risk = data.get('RISK_ASSESSMENT')
    submit = data.get('SUBMIT', False)
    comment = data.get('COMMENT')

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row["status"] != 'REJECTED':
            return jsonify({"error": "Only rejected requests can be revised"}), 400
    finally:
        cache_conn.close()

    new_status = 'SUBMITTED' if submit else 'DRAFT'
    user_info = get_effective_user()
    submitted_by_name = user_info["display_name"] if user_info else None
    now_iso = datetime.now().isoformat()

    cache_updates = {
        "business_justification": justification,
        "expected_outcome": outcome,
        "risk_assessment": risk,
        "status": new_status,
        "updated_at": now_iso
    }
    if submit:
        cache_updates["submitted_comment"] = comment
        cache_updates["submitted_by_name"] = submitted_by_name
        cache_updates["submitted_at"] = now_iso
    else:
        if comment:
            cache_updates["draft_comment"] = comment
            cache_updates["draft_by_name"] = submitted_by_name
            cache_updates["draft_at"] = now_iso

    update_cache_request(request_id, cache_updates)

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            if submit:
                cur.execute("""
                    UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                    SET BUSINESS_JUSTIFICATION = %s,
                        EXPECTED_OUTCOME = %s,
                        RISK_ASSESSMENT = %s,
                        STATUS = %s,
                        SUBMITTED_COMMENT = %s, SUBMITTED_BY_NAME = %s, SUBMITTED_AT = CURRENT_TIMESTAMP(),
                        UPDATED_AT = CURRENT_TIMESTAMP()
                    WHERE REQUEST_ID = %s
                """, (justification, outcome, risk, new_status, comment, submitted_by_name, request_id))
            else:
                if comment:
                    cur.execute("""
                        UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                        SET BUSINESS_JUSTIFICATION = %s,
                            EXPECTED_OUTCOME = %s,
                            RISK_ASSESSMENT = %s,
                            STATUS = %s,
                            DRAFT_COMMENT = %s, DRAFT_BY_NAME = %s, DRAFT_AT = CURRENT_TIMESTAMP(),
                            UPDATED_AT = CURRENT_TIMESTAMP()
                        WHERE REQUEST_ID = %s
                    """, (justification, outcome, risk, new_status, comment, submitted_by_name, request_id))
                else:
                    cur.execute("""
                        UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                        SET BUSINESS_JUSTIFICATION = %s,
                            EXPECTED_OUTCOME = %s,
                            RISK_ASSESSMENT = %s,
                            STATUS = %s,
                            UPDATED_AT = CURRENT_TIMESTAMP()
                        WHERE REQUEST_ID = %s
                    """, (justification, outcome, risk, new_status, request_id))
            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    return jsonify({"message": "Request revised successfully"})

@app.route('/api/requests/<int:request_id>/send-back', methods=['POST'])
def send_back_for_revision(request_id):
    data = request.json or {}
    comments = data.get('COMMENTS')

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row["status"] not in ['SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED']:
            return jsonify({"error": "Request cannot be sent back in current status"}), 400
    finally:
        cache_conn.close()

    now_iso = datetime.now().isoformat()

    update_cache_request(request_id, {
        "status": "DRAFT",
        "current_approval_level": 0,
        "next_approver_name": None, "next_approver_title": None, "next_approver_id": None,
        "gvp_comments": comments,
        "updated_at": now_iso
    })

    cache_conn2 = get_cache_connection()
    try:
        cache_conn2.cursor().execute("DELETE FROM cached_approval_steps WHERE request_id = ?", (request_id,))
        cache_conn2.commit()
    finally:
        cache_conn2.close()

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.APPROVAL_STEPS WHERE REQUEST_ID = %s", (request_id,))
            cur.execute("""
                UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                SET STATUS = 'DRAFT', CURRENT_APPROVAL_LEVEL = 0,
                    NEXT_APPROVER_NAME = NULL, NEXT_APPROVER_TITLE = NULL, NEXT_APPROVER_ID = NULL,
                    GVP_COMMENTS = %s,
                    UPDATED_AT = CURRENT_TIMESTAMP()
                WHERE REQUEST_ID = %s
            """, (comments, request_id))
            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    return jsonify({"message": "Request sent back for revision"})

@app.route('/api/requests/<int:request_id>/deny', methods=['POST'])
def deny_request(request_id):
    data = request.json or {}
    comments = data.get('COMMENTS')

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT status FROM cached_investment_requests WHERE request_id = ?", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row["status"] not in ['SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED']:
            return jsonify({"error": "Request cannot be denied in current status"}), 400
    finally:
        cache_conn.close()

    now_iso = datetime.now().isoformat()

    update_cache_request(request_id, {
        "status": "DENIED",
        "gvp_comments": comments,
        "updated_at": now_iso
    })

    def _sync():
        sf_conn = get_snowflake_connection()
        try:
            cur = sf_conn.cursor()
            cur.execute("""
                UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                SET STATUS = 'DENIED',
                    GVP_COMMENTS = %s,
                    UPDATED_AT = CURRENT_TIMESTAMP()
                WHERE REQUEST_ID = %s
            """, (comments, request_id))
            sf_conn.commit()
        finally:
            sf_conn.close()

    sync_to_snowflake(_sync)

    return jsonify({"message": "Request denied"})

@app.route('/api/accounts/search')
def search_accounts():
    query = request.args.get('q', '')
    if len(query) < 2:
        return jsonify({"accounts": [], "total_matches": 0})

    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("""
            SELECT COUNT(*) FROM cached_accounts
            WHERE UPPER(account_name) LIKE UPPER(?)
        """, (f'%{query}%',))
        total = cur.fetchone()[0]

        cur.execute("""
            SELECT account_id, account_name, theater, industry_segment
            FROM cached_accounts
            WHERE UPPER(account_name) LIKE UPPER(?)
            ORDER BY account_name
            LIMIT 20
        """, (f'%{query}%',))
        rows = cur.fetchall()

        return jsonify({
            "accounts": [{
                "ACCOUNT_ID": row[0],
                "ACCOUNT_NAME": row[1],
                "THEATER": row[2],
                "INDUSTRY_SEGMENT": row[3]
            } for row in rows],
            "total_matches": total
        })
    except Exception as e:
        print(f"Error searching accounts from cache: {e}")
        return jsonify([])
    finally:
        cache_conn.close()

@app.route('/api/lookup/theaters-industries')
def get_theaters_industries():
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("""
            SELECT DISTINCT theater FROM cached_accounts
            WHERE theater IS NOT NULL AND theater != ''
            ORDER BY theater
        """)
        theaters = [row[0] for row in cur.fetchall()]

        cur.execute("""
            SELECT DISTINCT industry_segment FROM cached_accounts
            WHERE industry_segment IS NOT NULL AND industry_segment != ''
            ORDER BY industry_segment
        """)
        industries = [row[0] for row in cur.fetchall()]

        cur.execute("""
            SELECT DISTINCT theater, industry_segment FROM cached_accounts
            WHERE theater IS NOT NULL AND theater != ''
              AND industry_segment IS NOT NULL AND industry_segment != ''
            ORDER BY theater, industry_segment
        """)
        combos = {}
        for row in cur.fetchall():
            combos.setdefault(row[0], []).append(row[1])

        return jsonify({
            "theaters": theaters,
            "industries": industries,
            "industries_by_theater": combos
        })
    except Exception as e:
        print(f"Error fetching theater/industry lookups: {e}")
        return jsonify({"theaters": [], "industries": [], "industries_by_theater": {}})
    finally:
        cache_conn.close()

@app.route('/api/accounts/<account_id>/opportunities')
def get_account_opportunities(account_id):
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        cur.execute("""
            SELECT OPPORTUNITY_ID, OPPORTUNITY_NAME, ACCOUNT_ID, ACCOUNT_NAME,
                   STAGE_NAME, AMOUNT, CLOSE_DATE, OWNER_NAME
            FROM SFDC_SHARED.SFDC_VIEWS.OPPORTUNITIES
            WHERE ACCOUNT_ID = %s
            ORDER BY CLOSE_DATE DESC
            LIMIT 50
        """, (account_id,))
        rows = cur.fetchall()

        return jsonify([{
            "OPPORTUNITY_ID": row[0],
            "OPPORTUNITY_NAME": row[1],
            "ACCOUNT_ID": row[2],
            "ACCOUNT_NAME": row[3],
            "STAGE": row[4],
            "AMOUNT": float(row[5]) if row[5] else None,
            "CLOSE_DATE": row[6].isoformat() if row[6] else None,
            "OWNER_NAME": row[7]
        } for row in rows])
    except Exception as e:
        print(f"Error fetching opportunities: {e}")
        return jsonify([])
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>/opportunities')
def get_request_opportunities(request_id):
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        cur.execute("""
            SELECT o.OPPORTUNITY_ID, o.OPPORTUNITY_NAME, o.ACCOUNT_ID, o.ACCOUNT_NAME,
                   o.STAGE_NAME, o.AMOUNT, o.CLOSE_DATE, o.OWNER_NAME
            FROM TEMP.INVESTMENT_GOVERNANCE.REQUEST_OPPORTUNITIES ro
            JOIN SFDC_SHARED.SFDC_VIEWS.OPPORTUNITIES o ON ro.OPPORTUNITY_ID = o.OPPORTUNITY_ID
            WHERE ro.REQUEST_ID = %s
        """, (request_id,))
        rows = cur.fetchall()

        return jsonify([{
            "OPPORTUNITY_ID": row[0],
            "OPPORTUNITY_NAME": row[1],
            "ACCOUNT_ID": row[2],
            "ACCOUNT_NAME": row[3],
            "STAGE": row[4],
            "AMOUNT": float(row[5]) if row[5] else None,
            "CLOSE_DATE": row[6].isoformat() if row[6] else None,
            "OWNER_NAME": row[7]
        } for row in rows])
    except Exception as e:
        print(f"Error fetching request opportunities: {e}")
        return jsonify([])
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>/opportunities', methods=['POST'])
def link_opportunity(request_id):
    data = request.json
    opportunity_id = data.get('OPPORTUNITY_ID')

    if not opportunity_id:
        return jsonify({"error": "OPPORTUNITY_ID required"}), 400

    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()

        effective = get_effective_user()
        current_user = effective["username"] if effective else "UNKNOWN"

        cur.execute("""
            INSERT INTO TEMP.INVESTMENT_GOVERNANCE.REQUEST_OPPORTUNITIES
            (REQUEST_ID, OPPORTUNITY_ID, LINKED_BY)
            VALUES (%s, %s, %s)
        """, (request_id, opportunity_id, current_user))
        sf_conn.commit()

        return jsonify({"message": "Opportunity linked"}), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>/opportunities/<opportunity_id>', methods=['DELETE'])
def unlink_opportunity(request_id, opportunity_id):
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        cur.execute("""
            DELETE FROM TEMP.INVESTMENT_GOVERNANCE.REQUEST_OPPORTUNITIES
            WHERE REQUEST_ID = %s AND OPPORTUNITY_ID = %s
        """, (request_id, opportunity_id))
        sf_conn.commit()

        return jsonify({"message": "Opportunity unlinked"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

if __name__ == '__main__':
    print(f"Starting Investment Governance API Server on port {API_PORT}")
    print(f"Using Snowflake connection: {CONNECTION_NAME}")
    print(f"Cache database: {CACHE_DB_PATH}")

    init_cache_db()

    threading.Thread(target=startup_cache_check, daemon=True).start()

    app.run(host='127.0.0.1', port=API_PORT, debug=False, threaded=True)
