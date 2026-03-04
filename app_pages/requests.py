import streamlit as st
import pandas as pd
import db
from helpers import (
    format_currency,
    normalize_theater,
    STATUS_DISPLAY,
    STATUS_COLORS,
    IN_REVIEW_STATUSES,
    is_owner,
    is_next_approver,
    can_edit,
    can_revise,
    can_withdraw,
    abbreviate_industry,
)
from components.filters import render_filters, apply_filters
from components.badges import status_badge_markdown
from components.dialogs import (
    new_request_dialog,
    edit_request_dialog,
    view_request_dialog,
    revise_request_dialog,
    review_request_dialog,
    withdraw_request_dialog,
)


def run():
    user = st.session_state.get("current_user")
    team_ids = st.session_state.get("team_member_ids", [])

    header_cols = st.columns([2, 4, 2, 2])
    with header_cols[0]:
        if st.button("New Request", type="primary", icon=":material/add:"):
            new_request_dialog()
    with header_cols[2]:
        all_requests = st.session_state.get("requests_data", [])
        st.badge(f"Requests: {len(all_requests)}", color="blue")
    with header_cols[3]:
        total_val = sum(float(r.get("requested_amount") or 0) for r in all_requests)
        st.badge(f"Value: {format_currency(total_val)}", color="green")

    nav_status = st.session_state.pop("nav_filter_status", None)
    nav_my = st.session_state.pop("nav_filter_my_requests", None)
    nav_pending = st.session_state.pop("nav_filter_pending", None)

    if nav_status:
        st.session_state["req_status"] = nav_status
    if nav_my:
        st.session_state["req_mine"] = True
    if nav_pending:
        st.session_state["req_pending"] = True

    filters = render_filters("req", show_search=True, show_pending=True, show_my_requests=True)

    all_requests = st.session_state.get("requests_data", [])
    filtered = apply_filters(all_requests, filters, user=user, team_ids=team_ids)

    if not filtered:
        st.info("No requests match the current filters.")
        return

    rows = []
    for r in filtered:
        rows.append({
            "id": r.get("request_id"),
            "Company": r.get("account_name", ""),
            "Investment Request": r.get("request_title", ""),
            "Theater": normalize_theater(r.get("theater", "")),
            "Industry": abbreviate_industry(r.get("industry_segment", "")),
            "Quarter": r.get("investment_quarter", ""),
            "Amount": float(r.get("requested_amount") or 0),
            "Status": STATUS_DISPLAY.get(r.get("status", ""), r.get("status", "")),
            "Next Approver": r.get("next_approver_name", ""),
        })

    df = pd.DataFrame(rows)

    event = st.dataframe(
        df[["Company", "Investment Request", "Theater", "Industry", "Quarter", "Amount", "Status", "Next Approver"]],
        column_config={
            "Amount": st.column_config.NumberColumn(format="$%,.0f"),
        },
        use_container_width=True,
        hide_index=True,
        on_select="rerun",
        selection_mode="single-row",
        key="requests_table",
    )

    selected_rows = event.selection.rows if event and event.selection else []
    if not selected_rows:
        return

    idx = selected_rows[0]
    selected_id = rows[idx]["id"]

    selected_request = None
    for r in filtered:
        if r.get("request_id") == selected_id:
            selected_request = r
            break

    if not selected_request:
        return

    status = selected_request.get("status", "")

    action_cols = st.columns(5)

    if can_edit(selected_request) and is_owner(selected_request, user):
        with action_cols[0]:
            if st.button("Edit", type="secondary", icon=":material/edit:"):
                edit_request_dialog(selected_request)
        with action_cols[1]:
            if st.button("Delete", type="secondary", icon=":material/delete:"):
                try:
                    db.delete_request(selected_id)
                    st.toast("Request deleted", icon=":material/delete:")
                    st.session_state["requests_data"] = db.get_requests()
                    st.rerun()
                except Exception as e:
                    st.error(str(e))

    elif status in IN_REVIEW_STATUSES:
        if is_next_approver(selected_request, user):
            with action_cols[0]:
                if st.button("Review", type="primary", icon=":material/rate_review:"):
                    review_request_dialog(selected_request)
        else:
            with action_cols[0]:
                if st.button("View", type="secondary", icon=":material/visibility:"):
                    view_request_dialog(selected_request)

        if can_withdraw(selected_request, user):
            with action_cols[1]:
                if st.button("Withdraw", type="secondary", icon=":material/undo:"):
                    withdraw_request_dialog(selected_request)

    elif status == "REJECTED" and can_revise(selected_request, user):
        with action_cols[0]:
            if st.button("Revise", type="secondary", icon=":material/edit_note:"):
                revise_request_dialog(selected_request)
        with action_cols[1]:
            if st.button("View", type="secondary", icon=":material/visibility:"):
                view_request_dialog(selected_request)

    else:
        with action_cols[0]:
            if st.button("View", type="secondary", icon=":material/visibility:"):
                view_request_dialog(selected_request)


run()
