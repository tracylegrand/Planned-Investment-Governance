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

cache_lock = threading.Lock()
progress_lock = threading.Lock()

cache_progress = {
    "status": "idle",
    "current_step": "",
    "steps_completed": 0,
    "total_steps": 4,
    "message": ""
}

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
            updated_at TEXT
        )
    """)
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS cached_accounts (
            account_id TEXT PRIMARY KEY,
            account_name TEXT,
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
    
    cur.execute("CREATE INDEX IF NOT EXISTS idx_requests_status ON cached_investment_requests(status)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_requests_theater ON cached_investment_requests(theater)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_requests_quarter ON cached_investment_requests(investment_quarter)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_accounts_name ON cached_accounts(account_name)")
    
    conn.commit()
    conn.close()
    print("Cache database initialized")

_sf_timestamps_cache = None
_sf_timestamps_cache_time = None
SF_TIMESTAMPS_TTL = 60

def get_snowflake_timestamps():
    global _sf_timestamps_cache, _sf_timestamps_cache_time
    
    now = datetime.now()
    if _sf_timestamps_cache is not None and _sf_timestamps_cache_time is not None:
        age = (now - _sf_timestamps_cache_time).total_seconds()
        if age < SF_TIMESTAMPS_TTL:
            return _sf_timestamps_cache
    
    conn = get_snowflake_connection()
    try:
        cur = conn.cursor()
        cur.execute("SELECT DATA_SOURCE, LAST_MODIFIED FROM TEMP.INVESTMENT_GOVERNANCE.VW_DATA_SOURCE_TIMESTAMPS")
        _sf_timestamps_cache = {row[0]: row[1].isoformat() if row[1] else None for row in cur.fetchall()}
        _sf_timestamps_cache_time = now
        return _sf_timestamps_cache
    except Exception as e:
        print(f"Error getting Snowflake timestamps: {e}")
        return {}
    finally:
        conn.close()

def invalidate_timestamps_cache():
    global _sf_timestamps_cache, _sf_timestamps_cache_time
    _sf_timestamps_cache = None
    _sf_timestamps_cache_time = None

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

def update_progress(step_name, steps_completed, message=""):
    global cache_progress
    with progress_lock:
        cache_progress["status"] = "loading"
        cache_progress["current_step"] = step_name
        cache_progress["steps_completed"] = steps_completed
        cache_progress["message"] = message

def refresh_users_cache():
    update_progress("users", 0, "Loading user data...")
    print("Refreshing users cache...")
    sf_conn = get_snowflake_connection()
    cache_conn = get_cache_connection()
    try:
        sf_cur = sf_conn.cursor()
        sf_cur.execute("""
            SELECT USER_ID, SNOWFLAKE_USERNAME, EMPLOYEE_ID, DISPLAY_NAME, TITLE, ROLE,
                   THEATER, INDUSTRY_SEGMENT, MANAGER_ID, MANAGER_NAME, APPROVAL_LEVEL, IS_FINAL_APPROVER
            FROM TEMP.INVESTMENT_GOVERNANCE.USERS
        """)
        rows = sf_cur.fetchall()
        
        cache_cur = cache_conn.cursor()
        cache_cur.execute("DELETE FROM cached_users")
        cache_cur.executemany(
            "INSERT OR REPLACE INTO cached_users VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            rows
        )
        cache_conn.commit()
        
        sf_timestamps = get_snowflake_timestamps()
        update_cache_timestamp('USERS', sf_timestamps.get('USERS'))
        print(f"Cached {len(rows)} users")
    except Exception as e:
        print(f"Error refreshing users cache: {e}")
    finally:
        sf_conn.close()
        cache_conn.close()

def refresh_current_user_cache():
    print("Refreshing current user cache...")
    sf_conn = get_snowflake_connection()
    cache_conn = get_cache_connection()
    try:
        sf_cur = sf_conn.cursor()
        sf_cur.execute("""
            SELECT SNOWFLAKE_USERNAME, USER_ID, EMPLOYEE_ID, DISPLAY_NAME, TITLE, ROLE,
                   THEATER, INDUSTRY_SEGMENT, MANAGER_ID, MANAGER_NAME, APPROVAL_LEVEL, IS_FINAL_APPROVER
            FROM TEMP.INVESTMENT_GOVERNANCE.VW_CURRENT_USER_INFO
        """)
        row = sf_cur.fetchone()
        
        if row:
            cache_cur = cache_conn.cursor()
            cache_cur.execute("DELETE FROM cached_current_user")
            cache_cur.execute(
                "INSERT INTO cached_current_user VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                row
            )
            cache_conn.commit()
            print(f"Cached current user: {row[0]}")
    except Exception as e:
        print(f"Error refreshing current user cache: {e}")
    finally:
        sf_conn.close()
        cache_conn.close()

def refresh_investment_requests_cache():
    update_progress("requests", 1, "Loading investment requests...")
    print("Refreshing investment requests cache...")
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
                   AVP_APPROVED_AT, AVP_COMMENTS, GVP_APPROVED_BY, GVP_APPROVED_BY_TITLE, GVP_APPROVED_AT, GVP_COMMENTS, UPDATED_AT
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
        cache_cur.executemany(
            """INSERT OR REPLACE INTO cached_investment_requests VALUES
               (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            [convert_row(row) for row in rows]
        )
        cache_conn.commit()
        
        sf_timestamps = get_snowflake_timestamps()
        update_cache_timestamp('INVESTMENT_REQUESTS', sf_timestamps.get('INVESTMENT_REQUESTS'))
        print(f"Cached {len(rows)} investment requests")
    except Exception as e:
        print(f"Error refreshing investment requests cache: {e}")
    finally:
        sf_conn.close()
        cache_conn.close()

def refresh_accounts_cache():
    update_progress("accounts", 2, "Loading SFDC accounts...")
    print("Refreshing accounts cache...")
    sf_conn = get_snowflake_connection()
    cache_conn = get_cache_connection()
    try:
        sf_cur = sf_conn.cursor()
        sf_cur.execute("""
            SELECT ACCOUNT_ID, ACCOUNT_NAME, THEATER, INDUSTRY
            FROM SFDC_SHARED.SFDC_VIEWS.ACCOUNTS
            WHERE ACCOUNT_NAME IS NOT NULL
            ORDER BY ACCOUNT_NAME
        """)
        rows = sf_cur.fetchall()
        
        cache_cur = cache_conn.cursor()
        cache_cur.execute("DELETE FROM cached_accounts")
        cache_cur.executemany(
            "INSERT OR REPLACE INTO cached_accounts VALUES (?, ?, ?, ?)",
            rows
        )
        cache_conn.commit()
        print(f"Cached {len(rows)} accounts")
    except Exception as e:
        print(f"Error refreshing accounts cache: {e}")
    finally:
        sf_conn.close()
        cache_conn.close()

def full_cache_refresh():
    print("Starting full cache refresh...")
    with cache_lock:
        try:
            refresh_users_cache()
            refresh_current_user_cache()
            refresh_investment_requests_cache()
            refresh_accounts_cache()
            
            with progress_lock:
                cache_progress["status"] = "complete"
                cache_progress["steps_completed"] = 4
                cache_progress["message"] = "Cache refresh complete"
            
            print("Full cache refresh complete")
        except Exception as e:
            print(f"Error during cache refresh: {e}")
            with progress_lock:
                cache_progress["status"] = "error"
                cache_progress["message"] = str(e)

def startup_cache_check():
    if needs_refresh(['INVESTMENT_REQUESTS', 'USERS']):
        full_cache_refresh()
    else:
        with progress_lock:
            cache_progress["status"] = "complete"
            cache_progress["message"] = "Cache is fresh"
        print("Cache is fresh, no refresh needed")

@app.route('/api/health')
def health():
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

@app.route('/api/cache/progress')
def get_cache_progress():
    with progress_lock:
        return jsonify(cache_progress)

@app.route('/api/user')
def get_current_user():
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("SELECT * FROM cached_current_user LIMIT 1")
        row = cur.fetchone()
        
        if row:
            return jsonify({
                "USER_ID": row["user_id"],
                "SNOWFLAKE_USERNAME": row["snowflake_username"],
                "EMPLOYEE_ID": row["employee_id"],
                "DISPLAY_NAME": row["display_name"],
                "TITLE": row["title"],
                "ROLE": row["role"],
                "THEATER": row["theater"],
                "INDUSTRY_SEGMENT": row["industry_segment"],
                "MANAGER_ID": row["manager_id"],
                "MANAGER_NAME": row["manager_name"],
                "APPROVAL_LEVEL": row["approval_level"],
                "IS_FINAL_APPROVER": bool(row["is_final_approver"])
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
                "IS_FINAL_APPROVER": False
            })
        finally:
            sf_conn.close()
    finally:
        cache_conn.close()

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
        
        cur.execute("SELECT * FROM cached_current_user LIMIT 1")
        user_row = cur.fetchone()
        current_user_name = user_row["display_name"] if user_row else None
        
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
        
        requests_list = []
        for row in rows:
            requests_list.append({
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
                "UPDATED_AT": row["updated_at"]
            })
        
        return jsonify(requests_list)
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
        
        return jsonify({
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
            "UPDATED_AT": row["updated_at"]
        })
    finally:
        cache_conn.close()

@app.route('/api/requests', methods=['POST'])
def create_request():
    data = request.json
    
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        
        cur.execute("SELECT CURRENT_USER()")
        current_user = cur.fetchone()[0]
        
        cur.execute("""
            SELECT DISPLAY_NAME, EMPLOYEE_ID, MANAGER_NAME
            FROM TEMP.INVESTMENT_GOVERNANCE.USERS
            WHERE SNOWFLAKE_USERNAME = %s
        """, (current_user,))
        user_info = cur.fetchone()
        created_by_name = user_info[0] if user_info else current_user
        employee_id = user_info[1] if user_info else None
        manager_name = user_info[2] if user_info else None
        
        cur.execute("""
            INSERT INTO TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
            (REQUEST_TITLE, ACCOUNT_ID, ACCOUNT_NAME, INVESTMENT_TYPE, REQUESTED_AMOUNT,
             INVESTMENT_QUARTER, BUSINESS_JUSTIFICATION, EXPECTED_OUTCOME, RISK_ASSESSMENT,
             CREATED_BY, CREATED_BY_NAME, CREATED_BY_EMPLOYEE_ID, THEATER, INDUSTRY_SEGMENT,
             STATUS, NEXT_APPROVER_NAME)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            data.get('REQUEST_TITLE'),
            data.get('ACCOUNT_ID'),
            data.get('ACCOUNT_NAME'),
            data.get('INVESTMENT_TYPE'),
            data.get('REQUESTED_AMOUNT'),
            data.get('INVESTMENT_QUARTER'),
            data.get('BUSINESS_JUSTIFICATION'),
            data.get('EXPECTED_OUTCOME'),
            data.get('RISK_ASSESSMENT'),
            current_user,
            created_by_name,
            employee_id,
            data.get('THEATER'),
            data.get('INDUSTRY_SEGMENT'),
            'DRAFT',
            manager_name
        ))
        
        cur.execute("SELECT MAX(REQUEST_ID) FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE CREATED_BY = %s", (current_user,))
        request_id = cur.fetchone()[0]
        
        sf_conn.commit()
        
        invalidate_timestamps_cache()
        threading.Thread(target=refresh_investment_requests_cache).start()
        
        return jsonify({"REQUEST_ID": request_id, "message": "Request created"}), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>', methods=['PUT'])
def update_request(request_id):
    data = request.json
    
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        
        cur.execute("SELECT STATUS FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE REQUEST_ID = %s", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row[0] != 'DRAFT':
            return jsonify({"error": "Cannot edit request that is not in DRAFT status"}), 400
        
        updates = []
        params = []
        for key in ['REQUEST_TITLE', 'ACCOUNT_ID', 'ACCOUNT_NAME', 'INVESTMENT_TYPE', 
                    'REQUESTED_AMOUNT', 'INVESTMENT_QUARTER', 'BUSINESS_JUSTIFICATION',
                    'EXPECTED_OUTCOME', 'RISK_ASSESSMENT', 'THEATER', 'INDUSTRY_SEGMENT']:
            if key in data:
                updates.append(f"{key} = %s")
                params.append(data[key])
        
        if updates:
            updates.append("UPDATED_AT = CURRENT_TIMESTAMP()")
            params.append(request_id)
            cur.execute(f"""
                UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
                SET {', '.join(updates)}
                WHERE REQUEST_ID = %s
            """, params)
            sf_conn.commit()
        
        invalidate_timestamps_cache()
        threading.Thread(target=refresh_investment_requests_cache).start()
        
        return jsonify({"message": "Request updated"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>', methods=['DELETE'])
def delete_request(request_id):
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        
        cur.execute("SELECT STATUS FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE REQUEST_ID = %s", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row[0] != 'DRAFT':
            return jsonify({"error": "Cannot delete request that is not in DRAFT status"}), 400
        
        cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.REQUEST_OPPORTUNITIES WHERE REQUEST_ID = %s", (request_id,))
        cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.REQUEST_CONTRIBUTORS WHERE REQUEST_ID = %s", (request_id,))
        cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.SUGGESTED_CHANGES WHERE REQUEST_ID = %s", (request_id,))
        cur.execute("DELETE FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE REQUEST_ID = %s", (request_id,))
        sf_conn.commit()
        
        invalidate_timestamps_cache()
        threading.Thread(target=refresh_investment_requests_cache).start()
        
        return jsonify({"message": "Request deleted"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>/submit', methods=['POST'])
def submit_request(request_id):
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        
        cur.execute("""
            SELECT STATUS, CREATED_BY FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS 
            WHERE REQUEST_ID = %s
        """, (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row[0] != 'DRAFT':
            return jsonify({"error": "Can only submit requests in DRAFT status"}), 400
        
        created_by = row[1]
        cur.execute("""
            SELECT MANAGER_NAME FROM TEMP.INVESTMENT_GOVERNANCE.USERS
            WHERE SNOWFLAKE_USERNAME = %s
        """, (created_by,))
        manager_row = cur.fetchone()
        next_approver = manager_row[0] if manager_row else None
        
        cur.execute("""
            UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
            SET STATUS = 'SUBMITTED', CURRENT_APPROVAL_LEVEL = 1, NEXT_APPROVER_NAME = %s, UPDATED_AT = CURRENT_TIMESTAMP()
            WHERE REQUEST_ID = %s
        """, (next_approver, request_id))
        sf_conn.commit()
        
        invalidate_timestamps_cache()
        threading.Thread(target=refresh_investment_requests_cache).start()
        
        return jsonify({"message": "Request submitted for approval"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>/withdraw', methods=['POST'])
def withdraw_request(request_id):
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        
        cur.execute("SELECT STATUS FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE REQUEST_ID = %s", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row[0] not in ['SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED']:
            return jsonify({"error": "Cannot withdraw request in current status"}), 400
        
        cur.execute("""
            UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
            SET STATUS = 'DRAFT', CURRENT_APPROVAL_LEVEL = 0,
                DM_APPROVED_BY = NULL, DM_APPROVED_BY_TITLE = NULL, DM_APPROVED_AT = NULL, DM_COMMENTS = NULL,
                RD_APPROVED_BY = NULL, RD_APPROVED_BY_TITLE = NULL, RD_APPROVED_AT = NULL, RD_COMMENTS = NULL,
                AVP_APPROVED_BY = NULL, AVP_APPROVED_BY_TITLE = NULL, AVP_APPROVED_AT = NULL, AVP_COMMENTS = NULL,
                GVP_APPROVED_BY = NULL, GVP_APPROVED_BY_TITLE = NULL, GVP_APPROVED_AT = NULL, GVP_COMMENTS = NULL,
                UPDATED_AT = CURRENT_TIMESTAMP()
            WHERE REQUEST_ID = %s
        """, (request_id,))
        sf_conn.commit()
        
        invalidate_timestamps_cache()
        threading.Thread(target=refresh_investment_requests_cache).start()
        
        return jsonify({"message": "Request withdrawn to draft"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>/approve', methods=['POST'])
def approve_request(request_id):
    data = request.json or {}
    comments = data.get('COMMENTS')
    
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        
        cur.execute("SELECT CURRENT_USER()")
        current_user = cur.fetchone()[0]
        
        cur.execute("SELECT DISPLAY_NAME, TITLE FROM TEMP.INVESTMENT_GOVERNANCE.VW_CURRENT_USER_INFO")
        user_row = cur.fetchone()
        approver_name = user_row[0] if user_row else current_user
        approver_title = user_row[1] if user_row and len(user_row) > 1 else None
        
        cur.execute("SELECT STATUS, CURRENT_APPROVAL_LEVEL FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE REQUEST_ID = %s", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        
        current_status = row[0]
        current_level = row[1] or 0
        
        status_transitions = {
            'SUBMITTED': ('DM_APPROVED', 'DM_APPROVED_BY', 'DM_APPROVED_BY_TITLE', 'DM_APPROVED_AT', 'DM_COMMENTS', 2),
            'DM_APPROVED': ('RD_APPROVED', 'RD_APPROVED_BY', 'RD_APPROVED_BY_TITLE', 'RD_APPROVED_AT', 'RD_COMMENTS', 3),
            'RD_APPROVED': ('AVP_APPROVED', 'AVP_APPROVED_BY', 'AVP_APPROVED_BY_TITLE', 'AVP_APPROVED_AT', 'AVP_COMMENTS', 4),
            'AVP_APPROVED': ('FINAL_APPROVED', 'GVP_APPROVED_BY', 'GVP_APPROVED_BY_TITLE', 'GVP_APPROVED_AT', 'GVP_COMMENTS', 5)
        }
        
        if current_status not in status_transitions:
            return jsonify({"error": "Request cannot be approved in current status"}), 400
        
        new_status, approver_col, title_col, time_col, comments_col, new_level = status_transitions[current_status]
        
        cur.execute(f"""
            UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
            SET STATUS = %s, {approver_col} = %s, {title_col} = %s, {time_col} = CURRENT_TIMESTAMP(), {comments_col} = %s,
                CURRENT_APPROVAL_LEVEL = %s, UPDATED_AT = CURRENT_TIMESTAMP()
            WHERE REQUEST_ID = %s
        """, (new_status, approver_name, approver_title, comments, new_level, request_id))
        sf_conn.commit()
        
        invalidate_timestamps_cache()
        threading.Thread(target=refresh_investment_requests_cache).start()
        
        return jsonify({"message": f"Request approved, new status: {new_status}"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/requests/<int:request_id>/reject', methods=['POST'])
def reject_request(request_id):
    data = request.json or {}
    comments = data.get('COMMENTS')
    
    sf_conn = get_snowflake_connection()
    try:
        cur = sf_conn.cursor()
        
        cur.execute("SELECT STATUS FROM TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS WHERE REQUEST_ID = %s", (request_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Request not found"}), 404
        if row[0] not in ['SUBMITTED', 'DM_APPROVED', 'RD_APPROVED', 'AVP_APPROVED']:
            return jsonify({"error": "Request cannot be rejected in current status"}), 400
        
        cur.execute("""
            UPDATE TEMP.INVESTMENT_GOVERNANCE.INVESTMENT_REQUESTS
            SET STATUS = 'REJECTED', UPDATED_AT = CURRENT_TIMESTAMP()
            WHERE REQUEST_ID = %s
        """, (request_id,))
        sf_conn.commit()
        
        invalidate_timestamps_cache()
        threading.Thread(target=refresh_investment_requests_cache).start()
        
        return jsonify({"message": "Request rejected"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sf_conn.close()

@app.route('/api/accounts/search')
def search_accounts():
    query = request.args.get('q', '')
    if len(query) < 2:
        return jsonify([])
    
    cache_conn = get_cache_connection()
    try:
        cur = cache_conn.cursor()
        cur.execute("""
            SELECT account_id, account_name, theater, industry_segment
            FROM cached_accounts
            WHERE UPPER(account_name) LIKE UPPER(?)
            ORDER BY account_name
            LIMIT 20
        """, (f'%{query}%',))
        rows = cur.fetchall()
        
        return jsonify([{
            "ACCOUNT_ID": row[0],
            "ACCOUNT_NAME": row[1],
            "THEATER": row[2],
            "INDUSTRY_SEGMENT": row[3]
        } for row in rows])
    except Exception as e:
        print(f"Error searching accounts from cache: {e}")
        return jsonify([])
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
        
        cur.execute("SELECT CURRENT_USER()")
        current_user = cur.fetchone()[0]
        
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
