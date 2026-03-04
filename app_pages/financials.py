import streamlit as st
import pandas as pd
import csv
import os
import db
from helpers import (
    format_currency,
    normalize_theater,
    get_current_fiscal_quarter,
    get_fiscal_year_quarters,
    get_portfolios_by_theater,
)
from components.filters import render_filters

BUDGET_CSV = os.path.join(os.path.dirname(os.path.dirname(__file__)), "budget_data", "budget_data.csv")


def run():
    st.subheader("Financials — Approved vs Budget")

    user = st.session_state.get("user_data", {})
    if user.get("is_admin"):
        with st.expander("Admin: Import Budget Data"):
            st.caption(f"Source: `{BUDGET_CSV}`")
            if st.button("Import from budget_data.csv", key="fin_import_btn"):
                try:
                    rows = []
                    with open(BUDGET_CSV, newline="") as f:
                        reader = csv.DictReader(f)
                        for r in reader:
                            rows.append({
                                "fiscal_year": r["fiscal_year"],
                                "portfolio": r["portfolio"],
                                "theater": r.get("theater", "US Majors"),
                                "q1_budget": float(r["q1_budget"]),
                                "q2_budget": float(r["q2_budget"]),
                                "q3_budget": float(r["q3_budget"]),
                                "q4_budget": float(r["q4_budget"]),
                                "budget_amount": float(r["budget_amount"]),
                            })
                    result = db.import_budgets(rows)
                    st.success(f"Imported {result.get('imported', 0)} budget rows.")
                    st.rerun()
                except Exception as e:
                    st.error(f"Import failed: {e}")

    filters = render_filters("fin", show_quarters=False, show_status=False)

    try:
        budgets = db.get_budgets()
    except Exception as e:
        st.error(f"Failed to load budgets: {e}")
        budgets = []

    all_requests = st.session_state.get("requests_data", [])
    approved = [r for r in all_requests if r.get("status") == "FINAL_APPROVED"]

    current_q = get_current_fiscal_quarter()
    current_fy = current_q.split("-")[0] if "-" in current_q else "FY26"
    fy_num = int(current_fy.replace("FY", ""))
    quarters = get_fiscal_year_quarters(fy_num)
    quarter_labels = ["Q1", "Q2", "Q3", "Q4"]

    budgets_for_fy = [b for b in budgets if b.get("fiscal_year") == current_fy]

    budget_map = {}
    for b in budgets_for_fy:
        theater = normalize_theater(b.get("theater") or "")
        industry = b.get("industry_segment") or b.get("portfolio") or ""
        key = (theater, industry)
        budget_map[key] = {
            "q1": float(b.get("q1_budget") or 0),
            "q2": float(b.get("q2_budget") or 0),
            "q3": float(b.get("q3_budget") or 0),
            "q4": float(b.get("q4_budget") or 0),
            "total": float(b.get("budget_amount") or 0),
        }

    fy_approved = [r for r in approved if r.get("investment_quarter", "") in quarters]

    approved_map = {}
    for r in fy_approved:
        theater = normalize_theater(r.get("theater") or "")
        industry = r.get("industry_segment") or ""
        q = r.get("investment_quarter") or ""
        amt = float(r.get("requested_amount") or 0)

        key = (theater, industry)
        if key not in approved_map:
            approved_map[key] = {"q1": 0, "q2": 0, "q3": 0, "q4": 0, "count_q1": 0, "count_q2": 0, "count_q3": 0, "count_q4": 0}

        for i, fq in enumerate(quarters):
            if q == fq:
                qi = f"q{i+1}"
                approved_map[key][qi] += amt
                approved_map[key][f"count_{qi}"] += 1

    all_keys = set(list(budget_map.keys()) + list(approved_map.keys()))
    pbt = get_portfolios_by_theater()
    for theater_key in set(k[0] for k in all_keys):
        for p in pbt.get(theater_key, []):
            all_keys.add((theater_key, p))

    if filters.get("theater"):
        all_keys = {k for k in all_keys if k[0] == filters["theater"]}
    if filters.get("industries"):
        all_keys = {k for k in all_keys if k[1] in filters["industries"]}

    theater_groups = {}
    for theater, industry in sorted(all_keys):
        theater_groups.setdefault(theater, []).append(industry)

    rows = []
    for theater in sorted(theater_groups.keys()):
        industries = sorted(theater_groups[theater])

        theater_row = {"Theater / Industry": theater}
        for i, ql in enumerate(quarter_labels):
            qi = f"q{i+1}"
            t_approved = sum(approved_map.get((theater, ind), {}).get(qi, 0) for ind in industries)
            t_budget = sum(budget_map.get((theater, ind), {}).get(qi, 0) for ind in industries)
            t_count = sum(approved_map.get((theater, ind), {}).get(f"count_{qi}", 0) for ind in industries)
            t_remaining = t_budget - t_approved
            theater_row[f"{ql} #"] = t_count
            theater_row[f"{ql} Approved"] = t_approved
            theater_row[f"{ql} Budget"] = t_budget
            theater_row[f"{ql} Remaining"] = t_remaining

        fy_approved = sum(theater_row.get(f"{ql} Approved", 0) for ql in quarter_labels)
        fy_budget = sum(theater_row.get(f"{ql} Budget", 0) for ql in quarter_labels)
        fy_count = sum(theater_row.get(f"{ql} #", 0) for ql in quarter_labels)
        theater_row["FY #"] = fy_count
        theater_row["FY Approved"] = fy_approved
        theater_row["FY Budget"] = fy_budget
        theater_row["FY Remaining"] = fy_budget - fy_approved
        rows.append(theater_row)

        for industry in industries:
            ind_row = {"Theater / Industry": f"    {industry}"}
            bud = budget_map.get((theater, industry), {})
            appr = approved_map.get((theater, industry), {})
            for i, ql in enumerate(quarter_labels):
                qi = f"q{i+1}"
                a = appr.get(qi, 0)
                b = bud.get(qi, 0)
                c = appr.get(f"count_{qi}", 0)
                ind_row[f"{ql} #"] = c
                ind_row[f"{ql} Approved"] = a
                ind_row[f"{ql} Budget"] = b
                ind_row[f"{ql} Remaining"] = b - a

            fy_a = sum(ind_row.get(f"{ql} Approved", 0) for ql in quarter_labels)
            fy_b = sum(ind_row.get(f"{ql} Budget", 0) for ql in quarter_labels)
            fy_c = sum(ind_row.get(f"{ql} #", 0) for ql in quarter_labels)
            ind_row["FY #"] = fy_c
            ind_row["FY Approved"] = fy_a
            ind_row["FY Budget"] = fy_b
            ind_row["FY Remaining"] = fy_b - fy_a
            rows.append(ind_row)

    if not rows:
        st.info("No financial data available.")
        return

    df = pd.DataFrame(rows)

    remaining_cols = [f"{ql} Remaining" for ql in quarter_labels + ["FY"]]
    currency_cols = []
    for ql in quarter_labels + ["FY"]:
        currency_cols.extend([f"{ql} Approved", f"{ql} Budget"])

    for col in currency_cols:
        df[col] = df[col].apply(lambda v: f"${v:,.0f}" if pd.notna(v) else "")

    for col in remaining_cols:
        df[col] = df[col].apply(
            lambda v: f"<${abs(v):,.0f}>" if pd.notna(v) and v < 0 else f"${v:,.0f}" if pd.notna(v) else ""
        )

    for ql in quarter_labels + ["FY"]:
        df[f"{ql} #"] = df[f"{ql} #"].apply(lambda v: f"{int(v)}" if pd.notna(v) else "")

    def highlight_overages(row):
        styles = [""] * len(row)
        for i, col in enumerate(row.index):
            if col in remaining_cols and isinstance(row[col], str) and row[col].startswith("<"):
                styles[i] = "color: red"
        return styles

    styled = df.style.apply(highlight_overages, axis=1).set_properties(
        subset=["Theater / Industry"], **{"font-weight": "normal"}
    )

    for idx, row in df.iterrows():
        if not str(row["Theater / Industry"]).startswith("    "):
            styled = styled.set_properties(subset=pd.IndexSlice[idx, :], **{"font-weight": "bold"})

    st.dataframe(
        styled,
        use_container_width=True,
        hide_index=True,
    )


run()
