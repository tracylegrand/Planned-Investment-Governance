import streamlit as st
from helpers import STATUS_COLORS, STATUS_DISPLAY, abbreviate_industry


def status_badge(status):
    color = STATUS_COLORS.get(status, "gray")
    label = STATUS_DISPLAY.get(status, status)
    st.badge(label, color=color)


def status_badge_markdown(status):
    color = STATUS_COLORS.get(status, "gray")
    label = STATUS_DISPLAY.get(status, status)
    return f":{color}-badge[{label}]"


def industry_badge(industry):
    abbr = abbreviate_industry(industry)
    return abbr
