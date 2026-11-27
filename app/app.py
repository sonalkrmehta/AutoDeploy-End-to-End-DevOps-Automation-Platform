"""AutoDeploy demo web application.

A small, production-style Flask service. It is the *payload* that the
AutoDeploy pipeline builds, containerises, ships to AWS and monitors.

Endpoints
---------
GET /                 HTML status page (shows the deployed version)
GET /health           Liveness/readiness probe used by Docker, CI and Ansible
GET /api/info         Build / runtime information as JSON
GET /api/simulate     Demo helper: inject latency / HTTP errors (see below)
GET /metrics          Prometheus metrics (blocked at the Nginx edge)

Metrics are served from the default prometheus_client registry, so the
container runs a single Gunicorn worker with several threads (see the
Dockerfile). That keeps the metrics consistent without multiprocess mode.
"""
import os
import platform
import socket
import time
from datetime import datetime, timezone

from flask import Flask, Response, g, jsonify, render_template, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

START_TIME = time.time()

APP_NAME = os.getenv("APP_NAME", "AutoDeploy")
APP_VERSION = os.getenv("APP_VERSION", "dev")
APP_ENV = os.getenv("APP_ENV", "local")

MAX_SIMULATED_DELAY_MS = 2000

# --------------------------------------------------------------------------
# Prometheus metrics
# --------------------------------------------------------------------------
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total number of HTTP requests handled by the application.",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds.",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
REQUESTS_IN_PROGRESS = Gauge(
    "http_requests_in_progress",
    "Number of HTTP requests currently being processed.",
)
APP_INFO = Gauge(
    "autodeploy_app_info",
    "Static information about the running build (value is always 1).",
    ["version", "environment"],
)
APP_INFO.labels(version=APP_VERSION, environment=APP_ENV).set(1)
APP_UPTIME = Gauge(
    "autodeploy_app_uptime_seconds",
    "Seconds since the application process started.",
)
APP_UPTIME.set_function(lambda: time.time() - START_TIME)


def _uptime_seconds() -> float:
    return round(time.time() - START_TIME, 1)


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def create_app() -> Flask:
    """Application factory."""
    app = Flask(__name__)
    app.json.sort_keys = False
    app.config["ENABLE_SIMULATE"] = os.getenv("ENABLE_SIMULATE", "true").lower() in (
        "1",
        "true",
        "yes",
    )

    # ---------------------------------------------------------------- hooks
    @app.before_request
    def _start_timer():
        if request.path == "/metrics":
            return
        g.start_time = time.perf_counter()
        REQUESTS_IN_PROGRESS.inc()

    @app.after_request
    def _record_metrics(response):
        if request.path == "/metrics" or not hasattr(g, "start_time"):
            return response
        # Use the route template (not the raw path) so that scanners hitting
        # random URLs cannot create unbounded label cardinality.
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        elapsed = time.perf_counter() - g.start_time
        REQUEST_COUNT.labels(request.method, endpoint, str(response.status_code)).inc()
        REQUEST_LATENCY.labels(request.method, endpoint).observe(elapsed)
        REQUESTS_IN_PROGRESS.dec()
        return response

    # --------------------------------------------------------------- routes
    @app.get("/")
    def index():
        return render_template(
            "index.html",
            name=APP_NAME,
            version=APP_VERSION,
            environment=APP_ENV,
            hostname=socket.gethostname(),
            python_version=platform.python_version(),
            uptime=_uptime_seconds(),
        )

    @app.get("/health")
    def health():
        return jsonify(
            status="ok",
            service=APP_NAME,
            version=APP_VERSION,
            uptime_seconds=_uptime_seconds(),
            timestamp=_utc_now(),
        )

    @app.get("/api/info")
    def info():
        return jsonify(
            name=APP_NAME,
            version=APP_VERSION,
            environment=APP_ENV,
            hostname=socket.gethostname(),
            python=platform.python_version(),
            uptime_seconds=_uptime_seconds(),
            timestamp=_utc_now(),
        )

    @app.get("/api/simulate")
    def simulate():
        """Demo helper to make dashboards and alerts interesting.

        /api/simulate?delay_ms=300&status=500
        Disable in production with ENABLE_SIMULATE=false.
        """
        if not app.config["ENABLE_SIMULATE"]:
            return jsonify(error="simulation endpoint is disabled"), 404
        try:
            delay_ms = int(request.args.get("delay_ms", 0))
            status = int(request.args.get("status", 200))
        except ValueError:
            return jsonify(error="delay_ms and status must be integers"), 400
        if not 0 <= delay_ms <= MAX_SIMULATED_DELAY_MS:
            return (
                jsonify(error=f"delay_ms must be between 0 and {MAX_SIMULATED_DELAY_MS}"),
                400,
            )
        if not 200 <= status <= 599:
            return jsonify(error="status must be between 200 and 599"), 400
        time.sleep(delay_ms / 1000)
        return jsonify(simulated=True, delay_ms=delay_ms, status=status), status

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    # ------------------------------------------------------- error handlers
    @app.errorhandler(404)
    def not_found(_error):
        return jsonify(error="not found", path=request.path), 404

    @app.errorhandler(405)
    def method_not_allowed(_error):
        return jsonify(error="method not allowed"), 405

    return app


app = create_app()

if __name__ == "__main__":  # pragma: no cover - local debugging only
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
