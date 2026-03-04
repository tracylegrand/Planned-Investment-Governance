import streamlit as st
import altair as alt
import pandas as pd
from helpers import PIPELINE_STAGES, normalize_theater


def _build_pipeline_data(requests_list, fy_label):
    stage_counts = {}
    stage_amounts = {}
    for label, status, color in PIPELINE_STAGES:
        stage_counts[label] = 0
        stage_amounts[label] = 0.0

    for r in requests_list:
        s = r.get("status", "")
        for label, status_code, color in PIPELINE_STAGES:
            if s == status_code:
                stage_counts[label] += 1
                stage_amounts[label] += float(r.get("requested_amount") or 0)
                break

    rows = []
    for i, (label, status, color) in enumerate(PIPELINE_STAGES):
        rows.append({
            "stage": label,
            "count": stage_counts[label],
            "amount": stage_amounts[label],
            "color": color,
            "order": i,
            "fy": fy_label,
        })
    return rows


def render_vertical_bars(requests_list, fy_label):
    data = _build_pipeline_data(requests_list, fy_label)
    df = pd.DataFrame(data)

    color_scale = alt.Scale(
        domain=[row["stage"] for row in data],
        range=[row["color"] for row in data],
    )

    chart = (
        alt.Chart(df)
        .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
        .encode(
            x=alt.X("stage:N", sort=[row["stage"] for row in data], title=None, axis=alt.Axis(labelAngle=0)),
            y=alt.Y("count:Q", title="Count"),
            color=alt.Color("stage:N", scale=color_scale, legend=None),
            tooltip=[
                alt.Tooltip("stage:N", title="Stage"),
                alt.Tooltip("count:Q", title="Count"),
                alt.Tooltip("amount:Q", title="Amount", format="$,.0f"),
            ],
        )
        .properties(height=250, title=f"Pipeline — {fy_label}")
    )

    text = chart.mark_text(dy=-10, fontSize=12, fontWeight="bold").encode(
        text="count:Q"
    )

    st.altair_chart(chart + text, width="stretch")


def render_horizontal_flow(requests_list, fy_label):
    data = _build_pipeline_data(requests_list, fy_label)
    st.markdown(f"**Pipeline Flow — {fy_label}**")
    cols = st.columns(len(data))
    for i, (col, row) in enumerate(zip(cols, data)):
        with col:
            color = row["color"]
            st.markdown(
                f"<div style='background:{color};color:white;border-radius:8px;"
                f"padding:8px;text-align:center;font-size:13px;'>"
                f"<b>{row['stage']}</b><br>{row['count']}<br>"
                f"<span style='font-size:11px;'>${row['amount']:,.0f}</span></div>",
                unsafe_allow_html=True,
            )


def render_compact_pills(requests_list, fy_label):
    data = _build_pipeline_data(requests_list, fy_label)
    parts = []
    for row in data:
        parts.append(f":{_badge_color(row['color'])}-badge[{row['stage']}: {row['count']}]")
    st.markdown(f"**{fy_label}** &nbsp; " + " › ".join(parts))


def render_stepper(requests_list, fy_label):
    data = _build_pipeline_data(requests_list, fy_label)
    df = pd.DataFrame(data)

    points = (
        alt.Chart(df)
        .mark_point(size=200, filled=True, strokeWidth=2)
        .encode(
            x=alt.X("order:Q", title=None, axis=alt.Axis(
                values=list(range(len(data))),
                labelExpr="[" + ",".join(f"'{r['stage']}'" for r in data) + "][datum.value]",
            )),
            color=alt.Color("stage:N", scale=alt.Scale(
                domain=[r["stage"] for r in data],
                range=[r["color"] for r in data],
            ), legend=None),
            tooltip=[
                alt.Tooltip("stage:N"),
                alt.Tooltip("count:Q"),
                alt.Tooltip("amount:Q", format="$,.0f"),
            ],
        )
    )

    line = (
        alt.Chart(pd.DataFrame({"x": [0], "x2": [len(data) - 1]}))
        .mark_rule(color="#ccc", strokeWidth=2)
        .encode(x="x:Q", x2="x2:Q")
    )

    labels = points.mark_text(dy=-18, fontSize=11, fontWeight="bold").encode(
        text="count:Q"
    )

    st.altair_chart(
        (line + points + labels).properties(height=80, title=f"Pipeline — {fy_label}"),
        width="stretch",
    )


def render_mini_bars(requests_list, fy_label):
    data = _build_pipeline_data(requests_list, fy_label)
    df = pd.DataFrame(data)

    chart = (
        alt.Chart(df)
        .mark_bar(cornerRadiusEnd=3, height=20)
        .encode(
            x=alt.X("count:Q", title=None, axis=None),
            y=alt.Y("stage:N", sort=[r["stage"] for r in data], title=None),
            color=alt.Color("stage:N", scale=alt.Scale(
                domain=[r["stage"] for r in data],
                range=[r["color"] for r in data],
            ), legend=None),
            tooltip=[
                alt.Tooltip("stage:N"),
                alt.Tooltip("count:Q"),
                alt.Tooltip("amount:Q", format="$,.0f"),
            ],
        )
        .properties(height=180, title=f"Pipeline — {fy_label}")
    )

    st.altair_chart(chart, width="stretch")


def _badge_color(hex_color):
    mapping = {
        "#9e9e9e": "gray",
        "#ff9800": "orange",
        "#2196f3": "blue",
        "#1976d2": "blue",
        "#1565c0": "blue",
        "#f44336": "red",
        "#4caf50": "green",
    }
    return mapping.get(hex_color, "gray")
