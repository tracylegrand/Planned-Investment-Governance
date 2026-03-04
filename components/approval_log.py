import streamlit as st
from helpers import format_date


def render_approval_log(request, steps=None):
    created_by = request.get("created_by_name") or request.get("created_by") or ""
    created_at = request.get("created_at") or ""
    created_title = request.get("created_by_title") or ""

    if created_by:
        with st.container():
            st.markdown(f":material/description: **Created** by {created_by}")
            if created_title:
                st.caption(f"{created_title}")
            if created_at:
                st.caption(format_date(created_at))
        st.divider()

    draft_by = request.get("draft_by_name") or ""
    draft_at = request.get("draft_at") or ""
    draft_comment = request.get("draft_comment") or ""
    if draft_by:
        with st.container():
            st.markdown(f":material/edit: **Saved as Draft** by {draft_by}")
            if draft_at:
                st.caption(format_date(draft_at))
            if draft_comment:
                st.info(draft_comment, icon=":material/chat:")
        st.divider()

    submitted_by = request.get("submitted_by_name") or ""
    submitted_at = request.get("submitted_at") or ""
    submitted_comment = request.get("submitted_comment") or ""
    if submitted_by:
        with st.container():
            st.markdown(f":material/send: **Submitted** by {submitted_by}")
            if submitted_at:
                st.caption(format_date(submitted_at))
            if submitted_comment:
                st.info(submitted_comment, icon=":material/chat:")
        st.divider()

    if steps:
        for step in steps:
            step_status = step.get("status", "")
            approver = step.get("approver_name") or step.get("approver_id") or ""
            approver_title = step.get("approver_title") or ""
            acted_at = step.get("acted_at") or ""
            comments = step.get("comments") or ""
            step_label = step.get("step_label") or f"Step {step.get('step_order', '')}"

            if step_status == "APPROVED":
                with st.container():
                    st.markdown(f":material/check_circle: **{step_label} — Approved** by {approver}")
                    if approver_title:
                        st.caption(approver_title)
                    if acted_at:
                        st.caption(format_date(acted_at))
                    if comments:
                        st.success(comments, icon=":material/chat:")
                st.divider()
            elif step_status == "REJECTED":
                with st.container():
                    st.markdown(f":material/cancel: **{step_label} — Rejected** by {approver}")
                    if approver_title:
                        st.caption(approver_title)
                    if acted_at:
                        st.caption(format_date(acted_at))
                    if comments:
                        st.error(comments, icon=":material/chat:")
                st.divider()
            elif step_status == "PENDING":
                with st.container():
                    st.markdown(f":material/schedule: **{step_label} — Pending** — {approver}")
                    if approver_title:
                        st.caption(approver_title)
                st.divider()
    else:
        _render_legacy_approvals(request)

    withdrawn_by = request.get("withdrawn_by_name") or ""
    withdrawn_at = request.get("withdrawn_at") or ""
    withdrawn_comment = request.get("withdrawn_comment") or ""
    if withdrawn_by:
        with st.container():
            st.markdown(f":material/undo: **Withdrawn** by {withdrawn_by}")
            if withdrawn_at:
                st.caption(format_date(withdrawn_at))
            if withdrawn_comment:
                st.warning(withdrawn_comment, icon=":material/chat:")


def _render_legacy_approvals(request):
    levels = [
        ("DM", "dm"),
        ("RD", "rd"),
        ("AVP", "avp"),
        ("GVP", "gvp"),
    ]
    for label, prefix in levels:
        approved_by = request.get(f"{prefix}_approved_by_name") or request.get(f"{prefix}_approved_by") or ""
        approved_at = request.get(f"{prefix}_approved_at") or ""
        comments = request.get(f"{prefix}_approval_comments") or ""
        rejected = request.get(f"{prefix}_rejected")

        if not approved_by and not approved_at:
            continue

        if rejected:
            with st.container():
                st.markdown(f":material/cancel: **{label} Review — Rejected** by {approved_by}")
                if approved_at:
                    st.caption(format_date(approved_at))
                if comments:
                    st.error(comments, icon=":material/chat:")
            st.divider()
        elif approved_by:
            with st.container():
                st.markdown(f":material/check_circle: **{label} Review — Approved** by {approved_by}")
                if approved_at:
                    st.caption(format_date(approved_at))
                if comments:
                    st.success(comments, icon=":material/chat:")
            st.divider()
