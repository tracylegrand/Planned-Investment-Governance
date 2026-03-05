import streamlit as st
import db
from helpers import (
    INVESTMENT_TYPES,
    ROI_OPTIONS,
    THEATERS_DISPLAY,
    STATUS_DISPLAY,
    STATUS_COLORS,
    format_currency,
    format_date,
    get_all_quarter_options_flat,
    get_current_fiscal_quarter,
    portfolios_for_theater,
    normalize_theater,
    portfolio_name_for_region,
    can_edit,
    can_revise,
    can_withdraw,
    is_owner,
    is_next_approver,
)
from components.approval_log import render_approval_log


@st.dialog("New investment request", width="large")
def new_request_dialog():
    _request_form(mode="new")


@st.dialog("Edit request", width="large")
def edit_request_dialog(request):
    _request_form(mode="edit", request=request)


@st.dialog("Request details", width="large")
def view_request_dialog(request):
    _render_request_details(request, readonly=True)


@st.dialog("Revise request", width="large")
def revise_request_dialog(request):
    _request_form(mode="revise", request=request)


@st.dialog("Review request", width="large")
def review_request_dialog(request):
    _render_request_details(request, readonly=True)

    st.divider()
    st.subheader("Decision")
    comments = st.text_area("Comments", key="review_comments", height=100)

    c1, c2, c3 = st.columns(3)
    with c1:
        if st.button(
            "Send Back",
            type="secondary",
            icon=":material/undo:",
            use_container_width=True,
        ):
            try:
                db.send_back_request(request["request_id"], comments)
                st.toast("Request sent back for revision", icon=":material/undo:")
                st.rerun()
            except Exception as e:
                st.error(str(e))
    with c2:
        if st.button(
            "Deny",
            type="secondary",
            icon=":material/block:",
            use_container_width=True,
        ):
            try:
                db.deny_request(request["request_id"], comments)
                st.toast("Request denied", icon=":material/block:")
                st.rerun()
            except Exception as e:
                st.error(str(e))
    with c3:
        if st.button(
            "Approve",
            type="primary",
            icon=":material/check_circle:",
            use_container_width=True,
        ):
            try:
                db.approve_request(request["request_id"], comments)
                st.toast("Request approved", icon=":material/check_circle:")
                st.rerun()
            except Exception as e:
                st.error(str(e))


@st.dialog("Withdraw request", width="small")
def withdraw_request_dialog(request):
    st.write(f"Withdraw **{request.get('request_title', '')}**?")
    st.caption("This will reset the request to Draft status and clear all approvals.")
    reason = st.text_area("Reason", key="withdraw_reason")

    c1, c2 = st.columns(2)
    with c1:
        if st.button("Withdraw", type="primary", icon=":material/warning:"):
            try:
                db.withdraw_request(request["request_id"], reason)
                st.toast("Request withdrawn", icon=":material/undo:")
                st.rerun()
            except Exception as e:
                st.error(str(e))
    with c2:
        if st.button("Cancel", key="withdraw_cancel"):
            st.rerun()


def _request_form(mode="new", request=None):
    is_edit = mode == "edit" and request is not None
    is_revise = mode == "revise" and request is not None
    defaults = request or {}

    st.subheader("Request Details")

    title = st.text_input(
        "Title *",
        value=defaults.get("request_title", ""),
        key="form_title",
    )

    account_search = st.text_input(
        "Account *",
        value=defaults.get("account_name", ""),
        key="form_account_search",
        placeholder="Type to search accounts...",
    )

    selected_account = None
    if len(account_search) >= 2 and account_search != defaults.get("account_name", ""):
        try:
            results, total_matches = db.search_accounts(account_search)
            if results:
                def _account_label(a):
                    label = a['account_name']
                    geo_parts = []
                    t = normalize_theater(a.get('theater') or '')
                    r = portfolio_name_for_region(a.get('region') or '')
                    if t and r:
                        geo_parts.append(f"{t} · {r}")
                    elif t:
                        geo_parts.append(t)
                    loc_parts = [x for x in [a.get('billing_city'), a.get('billing_state'), a.get('billing_country')] if x]
                    if loc_parts:
                        geo_parts.append(', '.join(loc_parts))
                    if geo_parts:
                        label += '  —  ' + ' | '.join(geo_parts)
                    return label
                options = {_account_label(a): a for a in results}
                choice = st.selectbox("Select account", list(options.keys()), key="form_account_select")
                if choice:
                    selected_account = options[choice]
                if total_matches > 20:
                    st.caption(f"{total_matches - 20} more matches — type more to narrow results")
        except Exception:
            pass

    c1, c2 = st.columns(2)
    with c1:
        inv_type = st.selectbox(
            "Investment Type",
            INVESTMENT_TYPES,
            index=INVESTMENT_TYPES.index(defaults.get("investment_type", "Professional Services")) if defaults.get("investment_type") in INVESTMENT_TYPES else 0,
            key="form_type",
        )
    with c2:
        amount = st.number_input(
            "Amount Requested ($) *",
            min_value=0,
            step=1000,
            value=int(defaults.get("requested_amount", 0) or 0),
            key="form_amount",
        )

    c3, c4 = st.columns(2)
    with c3:
        roi = st.selectbox(
            "Expected ROI",
            ROI_OPTIONS,
            index=ROI_OPTIONS.index(defaults.get("expected_roi", "10x")) if defaults.get("expected_roi") in ROI_OPTIONS else 5,
            key="form_roi",
        )
    with c4:
        quarters = get_all_quarter_options_flat()
        current_q = get_current_fiscal_quarter()
        default_idx = quarters.index(current_q) if current_q in quarters else 0
        if defaults.get("investment_quarter") in quarters:
            default_idx = quarters.index(defaults["investment_quarter"])
        quarter = st.selectbox("Quarter", quarters, index=default_idx, key="form_quarter")

    c5, c6 = st.columns(2)
    with c5:
        theater_val = ""
        if selected_account:
            theater_val = normalize_theater(selected_account.get("theater", ""))
        elif defaults.get("theater"):
            theater_val = normalize_theater(defaults["theater"])
        theater_options = THEATERS_DISPLAY
        theater_idx = 0
        if theater_val in theater_options:
            theater_idx = theater_options.index(theater_val)
        theater = st.selectbox("Theater", theater_options, index=theater_idx, key="form_theater")
    with c6:
        effective_theater = theater_val if selected_account and theater_val else theater
        region_options = portfolios_for_theater(effective_theater)
        ind_default = ""
        if selected_account:
            raw_region = selected_account.get("region", "")
            ind_default = portfolio_name_for_region(raw_region)
        elif defaults.get("industry_segment"):
            ind_default = defaults["industry_segment"]
        region_idx = 0
        if ind_default in region_options:
            region_idx = region_options.index(ind_default)
        if region_options:
            industry = st.selectbox("Region", region_options, index=region_idx, key="form_industry")
        else:
            industry = st.text_input("Region", value=ind_default, key="form_industry")

    sfdc_url = st.text_input(
        "Salesforce Opportunity URL (Optional Until Approved for IC)",
        value=defaults.get("sfdc_opportunity_link", ""),
        key="form_sfdc_url",
    )

    st.subheader("Business Case")
    justification = st.text_area(
        "Business Justification",
        value=defaults.get("business_justification", ""),
        height=120,
        key="form_justification",
    )
    outcome = st.text_area(
        "Expected Outcome",
        value=defaults.get("expected_outcome", ""),
        height=120,
        key="form_outcome",
    )
    risk = st.text_area(
        "Risk Assessment",
        value=defaults.get("risk_assessment", ""),
        height=120,
        key="form_risk",
    )

    comment = st.text_input("Comment", key="form_comment")

    if not title:
        st.warning("Title is required")

    account_id = None
    account_name = account_search
    if selected_account:
        account_id = selected_account.get("account_id")
        account_name = selected_account.get("account_name", account_search)
    elif defaults.get("account_id"):
        account_id = defaults["account_id"]

    data = {
        "REQUEST_TITLE": title,
        "ACCOUNT_ID": account_id,
        "ACCOUNT_NAME": account_name,
        "INVESTMENT_TYPE": inv_type,
        "REQUESTED_AMOUNT": amount,
        "EXPECTED_ROI": roi,
        "INVESTMENT_QUARTER": quarter,
        "THEATER": theater,
        "INDUSTRY_SEGMENT": industry,
        "SFDC_OPPORTUNITY_LINK": sfdc_url,
        "BUSINESS_JUSTIFICATION": justification,
        "EXPECTED_OUTCOME": outcome,
        "RISK_ASSESSMENT": risk,
        "COMMENT": comment,
    }

    c1, c2, c3, c4 = st.columns(4)
    with c1:
        if st.button("Save as Draft", type="secondary", disabled=not title):
            try:
                if is_revise:
                    db.revise_request(request["request_id"], data)
                    st.toast("Request saved as draft", icon=":material/check:")
                elif is_edit:
                    db.update_request(request["request_id"], data)
                    st.toast("Request updated", icon=":material/check:")
                else:
                    db.create_request(data)
                    st.toast("Request created", icon=":material/check:")
                st.session_state["requests_data"] = db.get_requests()
                st.rerun()
            except Exception as e:
                st.error(str(e))
    with c2:
        if st.button("Submit for Approval", type="primary", disabled=not title):
            data["SUBMIT" if is_revise else "AUTO_SUBMIT"] = True
            try:
                if is_revise:
                    db.revise_request(request["request_id"], data)
                    st.toast("Request revised and submitted", icon=":material/send:")
                elif is_edit:
                    db.update_request(request["request_id"], data)
                    st.toast("Request submitted", icon=":material/send:")
                else:
                    db.create_request(data)
                    st.toast("Request created and submitted", icon=":material/send:")
                st.session_state["requests_data"] = db.get_requests()
                st.rerun()
            except Exception as e:
                st.error(str(e))
    with c3:
        if is_edit and request.get("status") != "CANCELLED":
            is_draft = request.get("status") == "DRAFT"
            btn_label = "Withdraw" if is_draft else "Cancel Request"
            btn_icon = ":material/warning:" if is_draft else ":material/cancel:"
            if st.button(btn_label, type="secondary", icon=btn_icon, key="form_cancel_request"):
                st.session_state["confirm_cancel_request"] = request["request_id"]
    with c4:
        if st.button("Close", key="form_cancel"):
            st.rerun()

    if is_edit and st.session_state.get("confirm_cancel_request") == request.get("request_id"):
        is_draft = request.get("status") == "DRAFT"
        msg = "Withdraw this draft request? It will be marked as Cancelled." if is_draft else "Are you sure you want to cancel this request? This cannot be undone."
        st.warning(msg)
        cc1, cc2 = st.columns(2)
        with cc1:
            confirm_label = "Yes, Withdraw" if is_draft else "Yes, Cancel Request"
            if st.button(confirm_label, type="primary", key="confirm_cancel_yes"):
                try:
                    db.cancel_request(request["request_id"])
                    toast_msg = "Request withdrawn" if is_draft else "Request cancelled"
                    st.toast(toast_msg, icon=":material/cancel:")
                    st.session_state.pop("confirm_cancel_request", None)
                    st.rerun()
                except Exception as e:
                    st.error(str(e))
        with cc2:
            if st.button("No, Keep Request", key="confirm_cancel_no"):
                st.session_state.pop("confirm_cancel_request", None)
                st.rerun()

    if is_edit or is_revise:
        _render_approval_sections(request, key_suffix="_form")


def _render_request_details(request, readonly=True, show_business_case=True):
    status = request.get("status", "")
    color = STATUS_COLORS.get(status, "gray")
    display = STATUS_DISPLAY.get(status, status)

    st.badge(display, color=color)

    st.subheader("Request Details")

    st.markdown(f"**Title:** {request.get('request_title', 'N/A')}")
    st.markdown(f"**Account:** {request.get('account_name', 'N/A')}")

    c1, c2 = st.columns(2)
    with c1:
        st.markdown(f"**Investment Type:** {request.get('investment_type', 'N/A')}")
    with c2:
        st.markdown(f"**Amount:** {format_currency(request.get('requested_amount'))}")

    c3, c4 = st.columns(2)
    with c3:
        st.markdown(f"**Expected ROI:** {request.get('expected_roi', 'N/A')}")
    with c4:
        st.markdown(f"**Quarter:** {request.get('investment_quarter', 'N/A')}")

    c5, c6 = st.columns(2)
    with c5:
        st.markdown(f"**Theater:** {normalize_theater(request.get('theater', 'N/A'))}")
    with c6:
        st.markdown(f"**Region:** {request.get('industry_segment', 'N/A')}")

    if request.get("sfdc_opportunity_link"):
        st.markdown(f"**Salesforce Opportunity URL:** [{request['sfdc_opportunity_link']}]({request['sfdc_opportunity_link']})")

    if request.get("next_approver_name"):
        st.markdown(f"**Next Approver:** {request['next_approver_name']}")

    if show_business_case:
        st.divider()
        st.subheader("Business Case")
        if request.get("business_justification"):
            st.markdown("**Business Justification**")
            st.text(request["business_justification"])
        if request.get("expected_outcome"):
            st.markdown("**Expected Outcome**")
            st.text(request["expected_outcome"])
        if request.get("risk_assessment"):
            st.markdown("**Risk Assessment**")
            st.text(request["risk_assessment"])

    _render_approval_sections(request)


def _render_approval_sections(request, key_suffix=""):
    status = request.get("status", "")

    if status == "REJECTED":
        rejection_comments = (
            request.get("dm_approval_comments")
            or request.get("rd_approval_comments")
            or request.get("avp_approval_comments")
            or ""
        )
        if rejection_comments:
            st.divider()
            st.error(f"**Rejection Feedback:** {rejection_comments}")

    st.divider()
    st.subheader("Pre-IC Request Approval")
    steps = None
    try:
        steps = db.get_request_steps(request["request_id"])
    except Exception:
        pass
    render_approval_log(request, steps)

    if status == "FINAL_APPROVED":
        st.divider()
        st.subheader("Salesforce Investment Status")
        sfdc_link = request.get("sfdc_opportunity_link", "")
        if sfdc_link:
            try:
                sfdc_status = db.get_sfdc_opportunity_status_by_url(sfdc_link)
                if sfdc_status and not sfdc_status.get("error"):
                    c1, c2 = st.columns(2)
                    with c1:
                        st.markdown(f"**Opportunity:** {sfdc_status.get('opportunity_name', 'N/A')}")
                        st.markdown(f"**Stage:** {sfdc_status.get('stage_name', 'N/A')}")
                    with c2:
                        approval = sfdc_status.get("approval_status", "N/A")
                        color_map = {"Approved": "green", "Pending": "orange", "Rejected": "red"}
                        color = color_map.get(approval, "gray")
                        st.markdown(f"**SFDC Approval Status:** :{color}[{approval}]")
                    if st.button("🔄 Refresh Salesforce Status", key=f"refresh_sfdc_status{key_suffix}"):
                        st.rerun()
                else:
                    st.warning("Could not load Salesforce opportunity status")
            except Exception as e:
                st.warning(f"Error loading Salesforce status: {e}")
        else:
            st.info("Link a Salesforce Opportunity to track investment status")
            sfdc_input = st.text_input(
                "Salesforce Opportunity URL",
                key=f"sfdc_link_input{key_suffix}",
                placeholder="https://snowflakecomputing.my.salesforce.com/...",
            )
            if st.button("Save SFDC Link", disabled=not sfdc_input, key=f"save_sfdc_link{key_suffix}"):
                try:
                    db.update_sfdc_link(request["request_id"], sfdc_input)
                    st.toast("Salesforce link saved", icon=":material/check:")
                    st.rerun()
                except Exception as e:
                    st.error(f"Error saving link: {e}")
