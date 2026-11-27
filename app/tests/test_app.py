"""Unit tests for the AutoDeploy demo application."""
import pytest

from app import create_app


@pytest.fixture()
def client():
    application = create_app()
    application.config.update(TESTING=True)
    return application.test_client()


def test_health_returns_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.get_json()
    assert body["status"] == "ok"
    assert "version" in body
    assert body["uptime_seconds"] >= 0


def test_index_page_renders(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"AutoDeploy" in response.data
    assert b"Version" in response.data


def test_info_endpoint(client):
    response = client.get("/api/info")
    assert response.status_code == 200
    body = response.get_json()
    for key in ("name", "version", "environment", "hostname", "python"):
        assert key in body


def test_unknown_route_returns_json_404(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
    assert response.get_json()["error"] == "not found"


def test_wrong_method_returns_405(client):
    response = client.post("/health")
    assert response.status_code == 405


def test_metrics_exposes_prometheus_format(client):
    client.get("/health")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.mimetype == "text/plain"
    text = response.get_data(as_text=True)
    assert "http_requests_total" in text
    assert "http_request_duration_seconds_bucket" in text
    assert "autodeploy_app_info" in text
    assert "autodeploy_app_uptime_seconds" in text


def test_metrics_use_route_template_not_raw_path(client):
    client.get("/some/random/scanner/path")
    text = client.get("/metrics").get_data(as_text=True)
    assert 'endpoint="unmatched"' in text
    assert "/some/random/scanner/path" not in text


def test_simulate_returns_requested_status(client):
    response = client.get("/api/simulate?delay_ms=0&status=503")
    assert response.status_code == 503
    assert response.get_json()["simulated"] is True


@pytest.mark.parametrize(
    "query",
    ["delay_ms=abc", "status=xyz", "delay_ms=99999", "delay_ms=-1", "status=99", "status=700"],
)
def test_simulate_rejects_bad_input(client, query):
    assert client.get(f"/api/simulate?{query}").status_code == 400


def test_simulate_can_be_disabled():
    application = create_app()
    application.config.update(TESTING=True, ENABLE_SIMULATE=False)
    response = application.test_client().get("/api/simulate")
    assert response.status_code == 404
