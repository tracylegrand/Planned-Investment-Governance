import streamlit as st
import db
from helpers import (
    format_currency,
    IN_REVIEW_STATUSES,
    get_current_fiscal_quarter,
)
from components.filters import render_filters, apply_filters
from components.pipeline import (
    render_vertical_bars,
    render_horizontal_flow,
    render_compact_pills,
    render_stepper,
    render_mini_bars,
)


def _get_fiscal_year(quarter_str):
    if quarter_str and "FY" in quarter_str:
        return quarter_str.split("-")[0]
    return None


def run():
    filters = render_filters("dash")

    all_requests = st.session_state.get("requests_data", [])
    user = st.session_state.get("current_user")
    team_ids = st.session_state.get("team_member_ids", [])

    filtered = apply_filters(all_requests, filters, user=user, team_ids=team_ids)

    total_count = len(filtered)
    total_amount = sum(float(r.get("requested_amount") or 0) for r in filtered)

    approved = [r for r in filtered if r.get("status") == "FINAL_APPROVED"]
    approved_count = len(approved)
    approved_amount = sum(float(r.get("requested_amount") or 0) for r in approved)

    drafts = [r for r in filtered if r.get("status") == "DRAFT"]
    draft_count = len(drafts)
    draft_amount = sum(float(r.get("requested_amount") or 0) for r in drafts)

    my_username = (user.get("snowflake_username") or "").upper() if user else ""
    my_team_set = {my_username}
    if team_ids:
        my_team_set.update(t.upper() for t in team_ids)
    my_team = [r for r in filtered if (r.get("created_by") or "").upper() in my_team_set]
    my_count = len(my_team)
    my_amount = sum(float(r.get("requested_amount") or 0) for r in my_team)

    row1 = st.columns(4)
    with row1[0]:
        st.metric("Total Requests", total_count, border=True)
    with row1[1]:
        st.metric("Approved", approved_count, border=True)
    with row1[2]:
        st.metric("Draft", draft_count, border=True)
    with row1[3]:
        st.metric("My/Team", my_count, border=True)

    row2 = st.columns(4)
    with row2[0]:
        st.metric("Requested Amount", format_currency(total_amount), border=True)
    with row2[1]:
        st.metric("Approved Amount", format_currency(approved_amount), border=True)
    with row2[2]:
        st.metric("Draft Amount", format_currency(draft_amount), border=True)
    with row2[3]:
        st.metric("My/Team Amount", format_currency(my_amount), border=True)

    st.divider()

    current_q = get_current_fiscal_quarter()
    current_fy = current_q.split("-")[0] if "-" in current_q else "FY26"

    fy_groups = {}
    for r in filtered:
        q = r.get("investment_quarter", "")
        fy = _get_fiscal_year(q) or current_fy
        fy_groups.setdefault(fy, []).append(r)

    show_prior = st.session_state.get("show_prior_year", False)
    fys_to_show = sorted(fy_groups.keys())
    if not show_prior:
        fys_to_show = [fy for fy in fys_to_show if fy >= current_fy]

    for fy in fys_to_show:
        reqs = fy_groups.get(fy, [])

        if st.session_state.get("show_vertical_bars", True):
            render_vertical_bars(reqs, fy)
        if st.session_state.get("show_horizontal_flow", True):
            render_horizontal_flow(reqs, fy)
        if st.session_state.get("show_compact_pills", False):
            render_compact_pills(reqs, fy)
        if st.session_state.get("show_stepper", False):
            render_stepper(reqs, fy)
        if st.session_state.get("show_mini_bars", False):
            render_mini_bars(reqs, fy)


run()
