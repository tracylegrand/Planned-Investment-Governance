from datetime import date, datetime
import db as _db

_sfdc_cache = {}

def _load_sfdc_lookups():
    if _sfdc_cache:
        return _sfdc_cache
    try:
        data = _db.get_theaters_industries()
        if data and data.get("theaters"):
            _sfdc_cache["theaters"] = data["theaters"]
            _sfdc_cache["industries"] = data.get("industries", [])
            _sfdc_cache["industries_by_theater"] = data.get("industries_by_theater", {})
    except Exception:
        pass
    return _sfdc_cache

STATUS_COLORS = {
    "DRAFT": "gray",
    "SUBMITTED": "orange",
    "DM_APPROVED": "blue",
    "RD_APPROVED": "blue",
    "AVP_APPROVED": "blue",
    "FINAL_APPROVED": "green",
    "REJECTED": "red",
    "DENIED": "red",
    "CANCELLED": "gray",
}

STATUS_DISPLAY = {
    "DRAFT": "Draft",
    "SUBMITTED": "Submitted",
    "DM_APPROVED": "DM Approved",
    "RD_APPROVED": "RD Approved",
    "AVP_APPROVED": "AVP Approved",
    "FINAL_APPROVED": "Approved for IC",
    "REJECTED": "Rejected",
    "DENIED": "Denied",
    "CANCELLED": "Cancelled",
}

IN_REVIEW_STATUSES = {"SUBMITTED", "DM_APPROVED", "RD_APPROVED", "AVP_APPROVED"}

INVESTMENT_TYPES = [
    "Professional Services",
    "Customer Success",
    "Training",
    "Support",
    "Partnership",
    "Other",
]

ROI_OPTIONS = ["5x", "6x", "7x", "8x", "9x", "10x", "12x", "15x", "20x", "> 20x"]

PIPELINE_STAGES = [
    ("Draft", "DRAFT", "#9e9e9e"),
    ("Submitted", "SUBMITTED", "#ff9800"),
    ("DM Review", "DM_APPROVED", "#2196f3"),
    ("RD Review", "RD_APPROVED", "#1976d2"),
    ("AVP Review", "AVP_APPROVED", "#1565c0"),
    ("Rejected", "REJECTED", "#f44336"),
    ("Approved for IC", "FINAL_APPROVED", "#4caf50"),
]

_THEATERS_DISPLAY_FALLBACK = [
    "US Majors",
    "US Public Sector",
    "Americas Enterprise",
    "Americas Acquisition",
    "EMEA",
    "APJ",
]

_THEATER_DB_CODES = {
    "US Majors": ["USMajors"],
    "US Public Sector": ["USPubSec"],
    "Americas Enterprise": ["AMSExpansion", "AMSPartner", "AMSEnt"],
    "Americas Acquisition": ["AMSAcquisition"],
    "EMEA": ["EMEA"],
    "APJ": ["APJ", "APAC"],
}

_DB_TO_DISPLAY = {}
for _display, _codes in _THEATER_DB_CODES.items():
    for _c in _codes:
        _DB_TO_DISPLAY[_c] = _display


def get_theaters_display():
    data = _load_sfdc_lookups()
    return data.get("theaters", _THEATERS_DISPLAY_FALLBACK)


def get_portfolios_by_theater():
    data = _load_sfdc_lookups()
    return data.get("industries_by_theater", {})

INDUSTRY_ABBREVIATIONS = {
    "CME (TMT)": "CME",
    "FSI": "FSI",
    "FSIGlobals": "FSIG",
    "HCLS": "HCLS",
    "MFG": "MFG",
    "RCG": "RCG",
}


def display_name_for_theater(db_code):
    return _DB_TO_DISPLAY.get(db_code, db_code)


def db_codes_for_theater(display):
    return _THEATER_DB_CODES.get(display, [display])


def normalize_theater(value):
    if value in _DB_TO_DISPLAY:
        return _DB_TO_DISPLAY[value]
    return value


def portfolios_for_theater(theater):
    pbt = get_portfolios_by_theater()
    if theater is None:
        return sorted(set(p for ps in pbt.values() for p in ps))
    return pbt.get(theater, [])


def abbreviate_industry(industry):
    return INDUSTRY_ABBREVIATIONS.get(industry, industry)


def format_currency(amount):
    if amount is None:
        return "$0"
    try:
        val = float(amount)
    except (ValueError, TypeError):
        return "$0"
    if val >= 0:
        return f"${val:,.0f}"
    return f"<${abs(val):,.0f}>"


def format_date(dt_string):
    if not dt_string:
        return ""
    for fmt in (
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d",
    ):
        try:
            dt = datetime.strptime(dt_string, fmt)
            return dt.strftime("%b %d, %Y %I:%M %p")
        except ValueError:
            continue
    return dt_string


def format_date_short(dt_string):
    if not dt_string:
        return ""
    for fmt in (
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d",
    ):
        try:
            dt = datetime.strptime(dt_string, fmt)
            return dt.strftime("%b %d, %Y")
        except ValueError:
            continue
    return dt_string


def _fiscal_month(d):
    return d.month


def _fiscal_quarter_num(d):
    m = d.month
    if m in (2, 3, 4):
        return 1
    if m in (5, 6, 7):
        return 2
    if m in (8, 9, 10):
        return 3
    return 4


def _fiscal_year(d):
    if d.month >= 2:
        return d.year + 1
    return d.year


def get_current_fiscal_quarter():
    today = date.today()
    fy = _fiscal_year(today)
    q = _fiscal_quarter_num(today)
    return f"FY{fy}-Q{q}"


def get_fiscal_year_quarters(fy_num):
    return [f"FY{fy_num}-Q{q}" for q in range(1, 5)]


def get_quarter_options():
    today = date.today()
    fy = _fiscal_year(today)
    q = _fiscal_quarter_num(today)
    prev_fy = fy - 1
    groups = {}
    groups[f"FY{prev_fy}"] = get_fiscal_year_quarters(prev_fy)
    groups[f"FY{fy}"] = get_fiscal_year_quarters(fy)
    if q == 4:
        next_fy = fy + 1
        groups[f"FY{next_fy}"] = [f"FY{next_fy}-Q1", f"FY{next_fy}-Q2"]
    return groups


def get_all_quarter_options_flat():
    groups = get_quarter_options()
    flat = []
    for quarters in groups.values():
        flat.extend(quarters)
    return flat


def fiscal_quarter_from_string(q_str):
    return q_str


def is_next_approver(request, user):
    if not user or not request:
        return False
    return user.get("employee_id") == request.get("next_approver_id")


def is_owner(request, user):
    if not user or not request:
        return False
    uid = user.get("employee_id") or user.get("user_id")
    rid = request.get("created_by_employee_id")
    if uid and rid:
        return str(uid) == str(rid)
    return (user.get("snowflake_username") or "").upper() == (request.get("created_by") or "").upper()


def can_withdraw(request, user):
    return is_owner(request, user) and request.get("status") in IN_REVIEW_STATUSES


def can_edit(request):
    return request.get("status") == "DRAFT"


def can_revise(request, user):
    return request.get("status") == "REJECTED" and is_owner(request, user)
