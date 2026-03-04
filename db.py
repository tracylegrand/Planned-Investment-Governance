import os
import requests as _requests

API_BASE_URL = os.getenv("PIG_API_URL", "http://localhost:8770")


def _normalize(obj):
    if isinstance(obj, dict):
        return {k.lower(): _normalize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_normalize(i) for i in obj]
    return obj


def _get(path, params=None):
    resp = _requests.get(f"{API_BASE_URL}{path}", params=params, timeout=30)
    resp.raise_for_status()
    return _normalize(resp.json())


def _post(path, json=None):
    resp = _requests.post(f"{API_BASE_URL}{path}", json=json, timeout=30)
    resp.raise_for_status()
    return _normalize(resp.json())


def _put(path, json=None):
    resp = _requests.put(f"{API_BASE_URL}{path}", json=json, timeout=30)
    resp.raise_for_status()
    return _normalize(resp.json())


def _delete(path):
    resp = _requests.delete(f"{API_BASE_URL}{path}", timeout=30)
    resp.raise_for_status()
    return _normalize(resp.json())


def health():
    return _get("/api/health")


def refresh_cache():
    return _post("/api/cache/refresh")


def get_user():
    return _get("/api/user")


def search_employees(q):
    return _get("/api/employees/search", params={"q": q})


def impersonate(employee_id):
    return _post("/api/impersonate", json={"EMPLOYEE_ID": employee_id})


def stop_impersonate():
    return _post("/api/stop-impersonate")


def get_impersonation_status():
    return _get("/api/impersonate/status")


def get_requests(**filters):
    params = {k: v for k, v in filters.items() if v}
    return _get("/api/requests", params=params)


def get_request(request_id):
    return _get(f"/api/requests/{request_id}")


def get_request_steps(request_id):
    return _get(f"/api/requests/{request_id}/steps")


def get_budgets():
    return _get("/api/budgets")


def import_budgets(budgets):
    return _post("/api/budgets/import", json={"budgets": budgets})


def get_summary():
    return _get("/api/summary")


def get_theaters_industries():
    return _get("/api/lookup/theaters-industries")


def get_team_members():
    return _get("/api/team-members")


def get_approval_chain(employee_id, theater):
    return _get("/api/approval-chain", params={"employee_id": employee_id, "theater": theater})


def create_request(data):
    return _post("/api/requests", json=data)


def update_request(request_id, data):
    return _put(f"/api/requests/{request_id}", json=data)


def delete_request(request_id):
    return _delete(f"/api/requests/{request_id}")


def submit_request(request_id, comment=""):
    return _post(f"/api/requests/{request_id}/submit", json={"COMMENT": comment})


def withdraw_request(request_id, comment=""):
    return _post(f"/api/requests/{request_id}/withdraw", json={"COMMENT": comment})


def cancel_request(request_id):
    return _post(f"/api/requests/{request_id}/cancel", json={})


def approve_request(request_id, comments=""):
    return _post(f"/api/requests/{request_id}/approve", json={"COMMENTS": comments})


def reject_request(request_id, comments=""):
    return _post(f"/api/requests/{request_id}/reject", json={"COMMENTS": comments})


def revise_request(request_id, data):
    return _post(f"/api/requests/{request_id}/revise", json=data)


def send_back_request(request_id, comments=""):
    return _post(f"/api/requests/{request_id}/send-back", json={"COMMENTS": comments})


def deny_request(request_id, comments=""):
    return _post(f"/api/requests/{request_id}/deny", json={"COMMENTS": comments})


def search_accounts(q):
    return _get("/api/accounts/search", params={"q": q})


def get_account_opportunities(account_id):
    return _get(f"/api/accounts/{account_id}/opportunities")


def get_request_opportunities(request_id):
    return _get(f"/api/requests/{request_id}/opportunities")


def link_opportunity(request_id, opp_id):
    return _post(f"/api/requests/{request_id}/opportunities", json={"OPPORTUNITY_ID": opp_id})


def unlink_opportunity(request_id, opp_id):
    return _delete(f"/api/requests/{request_id}/opportunities/{opp_id}")


def get_sfdc_opportunity_status_by_url(url):
    return _get("/api/sfdc/opportunity-status-by-url", params={"url": url})


def update_sfdc_link(request_id, url):
    return _put(f"/api/requests/{request_id}/sfdc-link", json={"SFDC_OPPORTUNITY_LINK": url})
