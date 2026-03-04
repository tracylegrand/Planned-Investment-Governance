import streamlit as st
import db

st.set_page_config(
    page_title="Investment Governance",
    page_icon=":material/account_balance:",
    layout="wide",
)

if "current_user" not in st.session_state:
    try:
        st.session_state["current_user"] = db.get_user()
    except Exception:
        st.session_state["current_user"] = None

if "requests_data" not in st.session_state:
    try:
        st.session_state["requests_data"] = db.get_requests()
    except Exception:
        st.session_state["requests_data"] = []

if "team_member_ids" not in st.session_state:
    try:
        members = db.get_team_members()
        st.session_state["team_member_ids"] = [m.get("snowflake_username", "") for m in members if m.get("snowflake_username")]
    except Exception:
        st.session_state["team_member_ids"] = []

for k, v in {
    "show_prior_year": False,
    "show_vertical_bars": True,
    "show_horizontal_flow": True,
    "show_compact_pills": False,
    "show_stepper": False,
    "show_mini_bars": False,
}.items():
    if k not in st.session_state:
        st.session_state[k] = v

user = st.session_state.get("current_user")
is_admin = user and user.get("is_admin", False)


@st.dialog("Act as employee")
def act_as_dialog():
    query = st.text_input("Search employees", key="impersonate_search", placeholder="Name or email...")
    if query and len(query) >= 2:
        try:
            results = db.search_employees(query)
            if results:
                for emp in results[:10]:
                    name = emp.get("full_name") or emp.get("display_name") or ""
                    title = emp.get("title") or ""
                    emp_id = emp.get("employee_id") or ""
                    if st.button(f"{name} — {title}", key=f"imp_{emp_id}"):
                        db.impersonate(emp_id)
                        st.session_state["current_user"] = db.get_user()
                        st.session_state["requests_data"] = db.get_requests()
                        try:
                            members = db.get_team_members()
                            st.session_state["team_member_ids"] = [m.get("snowflake_username", "") for m in members if m.get("snowflake_username")]
                        except Exception:
                            st.session_state["team_member_ids"] = []
                        st.rerun()
            else:
                st.caption("No results")
        except Exception as e:
            st.error(str(e))


@st.dialog("Settings")
def settings_dialog():
    st.subheader("Pipeline Display")
    st.session_state["show_vertical_bars"] = st.toggle("Vertical Bars", value=st.session_state.get("show_vertical_bars", True), key="set_vbars")
    st.session_state["show_horizontal_flow"] = st.toggle("Horizontal Flow", value=st.session_state.get("show_horizontal_flow", True), key="set_hflow")
    st.session_state["show_compact_pills"] = st.toggle("Compact Pills", value=st.session_state.get("show_compact_pills", False), key="set_pills")
    st.session_state["show_stepper"] = st.toggle("Stepper", value=st.session_state.get("show_stepper", False), key="set_stepper")
    st.session_state["show_mini_bars"] = st.toggle("Mini Bars", value=st.session_state.get("show_mini_bars", False), key="set_mbars")

    st.divider()
    st.subheader("Data Range")
    st.session_state["show_prior_year"] = st.toggle("Show Prior Fiscal Year", value=st.session_state.get("show_prior_year", False), key="set_prior")

    if st.button("Close"):
        st.rerun()


impersonating = False
if user:
    impersonating = user.get("is_impersonating", False)
if not impersonating:
    try:
        imp_status = db.get_impersonation_status()
        impersonating = imp_status.get("active", False)
    except Exception:
        pass

if impersonating and user:
    imp_name = user.get("full_name") or user.get("display_name") or ""
    imp_title = user.get("title") or ""
    col_warn, col_stop = st.columns([5, 1])
    with col_warn:
        st.warning(f"Acting as: {imp_name} ({imp_title})", icon=":material/person:")
    with col_stop:
        if st.button("Stop", type="secondary"):
            db.stop_impersonate()
            st.session_state["current_user"] = db.get_user()
            st.session_state["requests_data"] = db.get_requests()
            try:
                members = db.get_team_members()
                st.session_state["team_member_ids"] = [m.get("snowflake_username", "") for m in members if m.get("snowflake_username")]
            except Exception:
                st.session_state["team_member_ids"] = []
            st.rerun()

header = st.columns([4, 1, 1, 1])
with header[0]:
    if user:
        name = user.get("full_name") or user.get("display_name") or user.get("snowflake_username") or ""
        title = user.get("title") or ""
        if impersonating:
            st.markdown(f"**:orange[{name}]** — {title}")
        else:
            st.markdown(f"**{name}** — {title}")
with header[1]:
    pending_count = len([r for r in st.session_state.get("requests_data", []) if user and r.get("next_approver_id") == user.get("employee_id")])
    if st.button(f"My Requests ({pending_count})", type="tertiary"):
        st.session_state["nav_filter_my_requests"] = True
        st.session_state["nav_filter_pending"] = True
with header[2]:
    if is_admin:
        if st.button("Act As", type="tertiary", icon=":material/person:"):
            act_as_dialog()
with header[3]:
    if st.button("", type="tertiary", icon=":material/settings:"):
        settings_dialog()

if st.button("Refresh Data", type="tertiary", icon=":material/refresh:"):
    try:
        db.refresh_cache()
        st.session_state["requests_data"] = db.get_requests()
        st.session_state["current_user"] = db.get_user()
        st.toast("Data refreshed", icon=":material/refresh:")
    except Exception as e:
        st.error(str(e))

page = st.navigation(
    [
        st.Page("app_pages/dashboard.py", title="Dashboard", icon=":material/pie_chart:"),
        st.Page("app_pages/requests.py", title="Requests", icon=":material/list_alt:"),
        st.Page("app_pages/financials.py", title="Financials", icon=":material/attach_money:"),
    ],
    position="top",
)
page.run()
