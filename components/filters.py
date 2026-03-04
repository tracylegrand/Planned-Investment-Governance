import streamlit as st
from helpers import (
    get_theaters_display,
    STATUS_DISPLAY,
    IN_REVIEW_STATUSES,
    portfolios_for_theater,
    get_all_quarter_options_flat,
    normalize_theater,
    db_codes_for_theater,
)


def render_filters(key_prefix, show_search=False, show_pending=False, show_my_requests=False, show_quarters=True, show_status=True):
    col_widths = [1.5, 2] + ([2] if show_quarters else []) + ([1.5] if show_status else []) + ([2] if show_search else []) + ([0.5] if show_pending else []) + ([0.5] if show_my_requests else []) + [0.5]
    cols = st.columns(col_widths)
    idx = 0

    with cols[idx]:
        theater_options = ["All"] + get_theaters_display()
        theater = st.selectbox(
            "Theater",
            theater_options,
            key=f"{key_prefix}_theater",
            placeholder="Theater",
        )
    idx += 1

    with cols[idx]:
        port = portfolios_for_theater(theater if theater != "All" else None)
        industries = st.multiselect(
            "Region",
            port,
            key=f"{key_prefix}_industries",
            placeholder="All Regions",
        )
    idx += 1

    quarters = []
    if show_quarters:
        with cols[idx]:
            all_quarters = get_all_quarter_options_flat()
            quarters = st.multiselect(
                "Quarters",
                all_quarters,
                key=f"{key_prefix}_quarters",
                placeholder="All Quarters",
            )
        idx += 1

    status = "All"
    if show_status:
        with cols[idx]:
            status_options = ["All"] + list(STATUS_DISPLAY.keys())
            status_options.insert(status_options.index("SUBMITTED") + 1, "IN_REVIEW")
            status = st.selectbox(
                "Status",
                status_options,
                format_func=lambda x: "Pending Approval" if x == "IN_REVIEW" else STATUS_DISPLAY.get(x, x),
                key=f"{key_prefix}_status",
                placeholder="Status",
            )
        idx += 1

    search_text = ""
    if show_search:
        with cols[idx]:
            search_text = st.text_input(
                "Search",
                key=f"{key_prefix}_search",
                placeholder="Search requests...",
            )
        idx += 1

    pending = False
    if show_pending:
        with cols[idx]:
            st.markdown("<div style='height:24px'></div>", unsafe_allow_html=True)
            pending = st.toggle("Pending", key=f"{key_prefix}_pending", help="Pending my approval")
        idx += 1

    my_reqs = False
    if show_my_requests:
        with cols[idx]:
            st.markdown("<div style='height:24px'></div>", unsafe_allow_html=True)
            my_reqs = st.toggle("Mine", key=f"{key_prefix}_mine", help="My/Team requests")
        idx += 1

    with cols[idx]:
        st.markdown("<div style='height:24px'></div>", unsafe_allow_html=True)
        if st.button("Clear", key=f"{key_prefix}_clear", type="tertiary"):
            for k in list(st.session_state.keys()):
                if k.startswith(f"{key_prefix}_"):
                    del st.session_state[k]
            st.rerun()

    return {
        "theater": theater if theater != "All" else None,
        "industries": industries,
        "quarters": quarters,
        "status": status if status != "All" else None,
        "search": search_text,
        "pending_my_approval": pending,
        "my_requests": my_reqs,
    }


def apply_filters(requests_list, filters, user=None, team_ids=None):
    result = list(requests_list)

    if filters.get("theater"):
        codes = db_codes_for_theater(filters["theater"])
        result = [r for r in result if normalize_theater(r.get("theater", "")) == filters["theater"] or r.get("theater", "") in codes]

    if filters.get("industries"):
        result = [r for r in result if r.get("industry_segment") in filters["industries"]]

    if filters.get("quarters"):
        result = [r for r in result if r.get("investment_quarter") in filters["quarters"]]

    if filters.get("status"):
        if filters["status"] == "IN_REVIEW":
            result = [r for r in result if r.get("status") in IN_REVIEW_STATUSES]
        else:
            result = [r for r in result if r.get("status") == filters["status"]]

    if filters.get("search"):
        q = filters["search"].lower()
        result = [
            r for r in result
            if q in (r.get("request_title") or "").lower()
            or q in (r.get("account_name") or "").lower()
        ]

    if filters.get("pending_my_approval") and user:
        emp_id = user.get("employee_id")
        result = [r for r in result if r.get("next_approver_id") == emp_id]

    if filters.get("my_requests") and user:
        uname = (user.get("snowflake_username") or "").upper()
        allowed = {uname}
        if team_ids:
            allowed.update(tid.upper() for tid in team_ids)
        result = [r for r in result if (r.get("created_by") or "").upper() in allowed]

    return result
