#!/usr/bin/env python3
"""Unified API Usage Dashboard Backend Daemon.

Polls multiple API services (Firecrawl, SerpAPI, Claude) and serves
usage data, history, and velocity via a local HTTP API.
"""

import argparse
import json
import logging
import os
import signal
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

log = logging.getLogger("api-dashboard")

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
DATA_DIR = Path(os.environ.get(
    "XDG_DATA_HOME", Path.home() / ".local" / "share")) / "api-dashboard"
HISTORY_FILE = DATA_DIR / "history.json"
CONFIG_FILE = Path(os.environ.get(
    "XDG_CONFIG_HOME", Path.home() / ".config")) / "api-dashboard" / "config.json"

CACHE_TTL = 60  # seconds
HISTORY_MAX_DAYS = 28

# ---------------------------------------------------------------------------
# Thread-safe state
# ---------------------------------------------------------------------------
_lock = threading.Lock()
_usage_cache: dict[str, dict] = {}       # service_id -> {data, timestamp}
_history: dict[str, list[dict]] = {}     # service_id -> [{timestamp, value, ...}]
_config: dict = {
    "refresh_interval": 300,
    "services": {}
}

# ---------------------------------------------------------------------------
# History persistence
# ---------------------------------------------------------------------------

def _load_history() -> dict[str, list[dict]]:
    try:
        if HISTORY_FILE.exists():
            return json.loads(HISTORY_FILE.read_text())
    except Exception as e:
        log.warning("Failed to load history: %s", e)
    return {}


def _save_history():
    with _lock:
        snapshot = json.dumps(_history, indent=2)
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        HISTORY_FILE.write_text(snapshot)
    except Exception as e:
        log.warning("Failed to save history: %s", e)


def _prune_history():
    cutoff = (datetime.now(timezone.utc) - timedelta(days=HISTORY_MAX_DAYS)).isoformat() + "Z"
    for svc in _history:
        _history[svc] = [e for e in _history[svc] if e.get("timestamp", "") > cutoff]


def _record_usage(service_id: str, value: float, extra: dict | None = None):
    with _lock:
        if service_id not in _history:
            _history[service_id] = []
        entry = {"timestamp": datetime.now(timezone.utc).isoformat() + "Z", "value": round(value, 1)}
        if extra:
            entry.update(extra)
        _history[service_id].append(entry)
        _prune_history()
    _save_history()

# ---------------------------------------------------------------------------
# History query & analytics
# ---------------------------------------------------------------------------

def _get_history(service_id: str, period: str = "24h") -> list[dict]:
    with _lock:
        raw = _history.get(service_id, [])

    hours_map = {"24h": 24, "7d": 168, "28d": 672}
    hours = hours_map.get(period, 24)
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat() + "Z"
    return [e for e in raw if e.get("timestamp", "") > cutoff]


def _calculate_velocity(service_id: str) -> dict | None:
    with _lock:
        raw = _history.get(service_id, [])
    if len(raw) < 2:
        return None

    cutoff = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat() + "Z"
    recent = [e for e in raw if e.get("timestamp", "") > cutoff]
    if len(recent) < 2:
        recent = raw[-10:]
    if len(recent) < 2:
        return None

    first, last = recent[0], recent[-1]
    try:
        t0 = datetime.fromisoformat(first["timestamp"].rstrip("Z"))
        t1 = datetime.fromisoformat(last["timestamp"].rstrip("Z"))
    except (KeyError, ValueError):
        return None

    dt_hours = (t1 - t0).total_seconds() / 3600
    if dt_hours <= 0:
        return None

    vel = (last["value"] - first["value"]) / dt_hours
    current = last["value"]

    if vel <= 0:
        minutes_to_limit = -1
    elif current >= 100:
        minutes_to_limit = 0
    else:
        minutes_to_limit = int((100 - current) / vel * 60)

    return {
        "current": current,
        "velocity_per_hour": round(vel, 2),
        "minutes_to_limit": minutes_to_limit,
    }

# ---------------------------------------------------------------------------
# Service adapters
# ---------------------------------------------------------------------------

def _http_get(url: str, headers: dict | None = None, timeout: int = 15) -> tuple[int, str]:
    req = Request(url, headers=headers or {})
    req.add_header("User-Agent", "ApiDashboard/1.0")
    try:
        with urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode()
    except HTTPError as e:
        return e.code, e.read().decode() if hasattr(e, "read") else ""
    except URLError as e:
        raise ConnectionError(str(e.reason)) from e


def _fetch_firecrawl(cfg: dict) -> dict:
    api_key = _keyring_get("firecrawl")
    if not api_key:
        return _error_result("firecrawl", "Firecrawl", "No API key configured")

    try:
        status, body = _http_get(
            "https://api.firecrawl.dev/v2/team/credit-usage",
            {"Authorization": f"Bearer {api_key}"}
        )
    except ConnectionError as e:
        return _error_result("firecrawl", "Firecrawl", f"Connection failed: {e}")

    if status == 401:
        return _error_result("firecrawl", "Firecrawl", "Invalid API key")
    if status != 200:
        return _error_result("firecrawl", "Firecrawl", f"HTTP {status}")

    try:
        d = json.loads(body)
        inner = d.get("data", d)
        total = inner.get("planCredits", 1)
        remaining = inner.get("remainingCredits", 0)
        used = total - remaining
        pct = round(used / total * 100, 1) if total > 0 else 0

        reset_day = cfg.get("reset_day", 16)
        return {
            "id": "firecrawl",
            "name": "Firecrawl",
            "icon": "cloud-download",
            "percentage": pct,
            "used": used,
            "total": total,
            "unit": "credits",
            "plan_name": f"{total:,} credits/mo",
            "reset_info": _reset_countdown(reset_day),
            "details": {},
            "error": "",
            "last_updated": datetime.now(timezone.utc).isoformat() + "Z",
        }
    except (json.JSONDecodeError, KeyError) as e:
        return _error_result("firecrawl", "Firecrawl", f"Parse error: {e}")


def _fetch_serpapi(cfg: dict) -> dict:
    api_key = _keyring_get("serpapi")
    if not api_key:
        return _error_result("serpapi", "SerpAPI", "No API key configured")

    try:
        from urllib.parse import quote
        status, body = _http_get(
            f"https://serpapi.com/account.json?api_key={quote(api_key)}"
        )
    except ConnectionError as e:
        return _error_result("serpapi", "SerpAPI", f"Connection failed: {e}")
    except Exception:
        return _error_result("serpapi", "SerpAPI", "Request failed")

    if status != 200:
        return _error_result("serpapi", "SerpAPI", f"HTTP {status}")

    try:
        d = json.loads(body)
        if d.get("error"):
            return _error_result("serpapi", "SerpAPI", d["error"])

        total = d.get("searches_per_month", 1)
        remaining = d.get("total_searches_left", d.get("plan_searches_left", 0))
        used = total - remaining
        pct = round(used / total * 100, 1) if total > 0 else 0

        reset_day = cfg.get("reset_day", 19)
        return {
            "id": "serpapi",
            "name": "SerpAPI",
            "icon": "search",
            "percentage": pct,
            "used": used,
            "total": total,
            "unit": "searches",
            "plan_name": d.get("plan_name", "Plan"),
            "reset_info": _reset_countdown(reset_day),
            "details": {"hourly": d.get("last_hour_searches", 0)},
            "error": "",
            "last_updated": datetime.now(timezone.utc).isoformat() + "Z",
        }
    except (json.JSONDecodeError, KeyError) as e:
        return _error_result("serpapi", "SerpAPI", f"Parse error: {e}")


def _fetch_claude(service_id: str, cfg: dict) -> dict:
    label = cfg.get("label", service_id.replace("claude_", "").title())
    name = f"Claude ({label})"
    browser = cfg.get("browser", "chrome")

    try:
        cookies = _get_claude_cookies(browser, cfg.get("profile_path"))
    except Exception as e:
        return _error_result(service_id, name, f"Cookie extraction failed: {e}")

    if not cookies or "sessionKey" not in cookies:
        return _error_result(service_id, name, "No session cookie found")

    cookie_header = "; ".join(f"{k}={v}" for k, v in cookies.items())
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Cookie": cookie_header,
    }

    # Fetch organizations
    try:
        status, body = _http_get("https://claude.ai/api/organizations", headers)
    except ConnectionError as e:
        return _error_result(service_id, name, f"Connection failed: {e}")

    if status in (401, 403):
        return _error_result(service_id, name, "Session expired")
    if status != 200:
        return _error_result(service_id, name, f"HTTP {status} fetching orgs")

    try:
        orgs = json.loads(body)
        if not orgs:
            return _error_result(service_id, name, "No organizations found")
        org = orgs[0]
        org_id = org.get("uuid", "")
        org_name = org.get("name", "")
        plan_type = "free"
        caps = org.get("capabilities", [])
        if "max" in str(caps).lower():
            plan_type = "max"
        elif "pro" in str(caps).lower():
            plan_type = "pro"
    except (json.JSONDecodeError, IndexError) as e:
        return _error_result(service_id, name, f"Parse error (orgs): {e}")

    # Fetch usage
    try:
        status, body = _http_get(
            f"https://claude.ai/api/organizations/{org_id}/usage", headers
        )
    except ConnectionError as e:
        return _error_result(service_id, name, f"Connection failed: {e}")

    if status != 200:
        return _error_result(service_id, name, f"HTTP {status} fetching usage")

    try:
        usage = json.loads(body)
        five_hour = usage.get("five_hour") or {}
        seven_day = usage.get("seven_day") or {}
        sonnet = usage.get("seven_day_sonnet") or {}

        # Claude API returns utilization as 0-1 fraction OR as percentage (>1).
        # Normalize: if > 1, it's already a percentage; otherwise multiply by 100.
        def _norm_pct(val):
            if val > 1:
                return min(round(val, 1), 100.0)
            return min(round(val * 100, 1), 100.0)

        fh_pct = _norm_pct(five_hour.get("utilization", 0))
        sd_pct = _norm_pct(seven_day.get("utilization", 0))
        so_pct = _norm_pct(sonnet.get("utilization", 0))

        fh_reset = _parse_reset_minutes(five_hour.get("resets_at"))
        sd_reset = _parse_reset_minutes(seven_day.get("resets_at"))

        primary_pct = max(fh_pct, sd_pct)

        return {
            "id": service_id,
            "name": name,
            "icon": "dialog-messages",
            "percentage": primary_pct,
            "used": primary_pct,
            "total": 100,
            "unit": "%",
            "plan_name": plan_type.title(),
            "reset_info": _format_minutes(fh_reset) if fh_reset > 0 else "",
            "details": {
                "org_name": org_name,
                "five_hour_usage": fh_pct,
                "five_hour_reset_minutes": fh_reset,
                "seven_day_usage": sd_pct,
                "seven_day_reset_minutes": sd_reset,
                "sonnet_usage": so_pct,
            },
            "error": "",
            "last_updated": datetime.now(timezone.utc).isoformat() + "Z",
        }
    except (json.JSONDecodeError, KeyError) as e:
        return _error_result(service_id, name, f"Parse error (usage): {e}")

# ---------------------------------------------------------------------------
# Claude cookie extraction
# ---------------------------------------------------------------------------

def _get_claude_cookies(browser: str, profile_path: str | None = None) -> dict:
    try:
        import browser_cookie3
    except ImportError:
        raise RuntimeError("browser_cookie3 not installed")

    if browser == "chrome":
        jar = browser_cookie3.chrome(domain_name=".claude.ai")
    elif browser == "brave":
        jar = browser_cookie3.brave(domain_name=".claude.ai")
    elif browser in ("helium", "chromium"):
        cookie_file = None
        if profile_path:
            cookie_file = os.path.join(os.path.expanduser(profile_path), "Cookies")
        elif browser == "helium":
            default = Path.home() / ".config" / "net.imput.helium" / "Default" / "Cookies"
            if default.exists():
                cookie_file = str(default)
        if cookie_file:
            jar = browser_cookie3.chrome(cookie_file=cookie_file, domain_name=".claude.ai")
        else:
            jar = browser_cookie3.chromium(domain_name=".claude.ai")
    elif browser == "firefox":
        jar = browser_cookie3.firefox(domain_name=".claude.ai")
    else:
        raise ValueError(f"Unsupported browser: {browser}")

    return {c.name: c.value for c in jar}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _keyring_get(key: str) -> str:
    try:
        import keyring
        return keyring.get_password("api-dashboard", key) or ""
    except Exception:
        return ""


def _error_result(service_id: str, name: str, error: str) -> dict:
    return {
        "id": service_id,
        "name": name,
        "icon": "",
        "percentage": 0,
        "used": 0,
        "total": 1,
        "unit": "",
        "plan_name": "",
        "reset_info": "",
        "details": {},
        "error": error,
        "last_updated": datetime.now(timezone.utc).isoformat() + "Z",
    }


def _reset_countdown(day: int) -> str:
    now = datetime.now(timezone.utc)
    reset = now.replace(day=min(day, 28))
    if reset <= now:
        if now.month == 12:
            reset = reset.replace(year=now.year + 1, month=1)
        else:
            reset = reset.replace(month=now.month + 1)
    delta = reset - now
    days = delta.days
    hours = delta.seconds // 3600
    return f"{days}d {hours}h"


def _parse_reset_minutes(resets_at: str | None) -> int:
    if not resets_at:
        return 0
    try:
        reset_time = datetime.fromisoformat(resets_at.rstrip("Z"))
        delta = reset_time - datetime.now(timezone.utc)
        return max(0, int(delta.total_seconds() / 60))
    except (ValueError, TypeError):
        return 0


def _format_minutes(minutes: int) -> str:
    if minutes <= 0:
        return ""
    if minutes >= 1440:
        return f"{minutes // 1440}d {(minutes % 1440) // 60}h"
    if minutes >= 60:
        return f"{minutes // 60}h {minutes % 60}m"
    return f"{minutes}m"

# ---------------------------------------------------------------------------
# Adapter dispatch
# ---------------------------------------------------------------------------
ADAPTERS = {
    "firecrawl": _fetch_firecrawl,
    "serpapi": _fetch_serpapi,
    "claude_work": lambda cfg: _fetch_claude("claude_work", cfg),
    "claude_private": lambda cfg: _fetch_claude("claude_private", cfg),
}


def _poll_all():
    """Poll all enabled services."""
    with _lock:
        services = dict(_config.get("services", {}))
    for svc_id, cfg in services.items():
        if not cfg.get("enabled", False):
            continue
        adapter = ADAPTERS.get(svc_id)
        if not adapter:
            continue
        try:
            result = adapter(cfg)
            with _lock:
                _usage_cache[svc_id] = {"data": result, "timestamp": time.time()}
            if not result.get("error"):
                _record_usage(svc_id, result["percentage"], result.get("details"))
        except Exception as e:
            log.error("Error polling %s: %s", svc_id, e)
            with _lock:
                _usage_cache[svc_id] = {
                    "data": _error_result(svc_id, svc_id, str(e)),
                    "timestamp": time.time(),
                }

# ---------------------------------------------------------------------------
# Background poller
# ---------------------------------------------------------------------------

class Poller(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self._stop_event = threading.Event()

    def run(self):
        while not self._stop_event.is_set():
            try:
                _poll_all()
            except Exception as e:
                log.error("Poller error: %s", e)
            with _lock:
                interval = _config.get("refresh_interval", 300)
            self._stop_event.wait(interval)

    def stop(self):
        self._stop_event.set()

# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        log.debug(format, *args)

    def _send_json(self, data, status_code=200):
        body = json.dumps(data).encode()
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        qs = parse_qs(parsed.query)

        if path == "/health":
            self._send_json({"status": "ok"})

        elif path == "/usage":
            self._handle_usage_all()

        elif path.startswith("/usage/"):
            svc_id = path.split("/usage/", 1)[1]
            self._handle_usage(svc_id)

        elif path.startswith("/history/"):
            svc_id = path.split("/history/", 1)[1]
            period = qs.get("period", ["24h"])[0]
            self._handle_history(svc_id, period)

        elif path.startswith("/velocity/"):
            svc_id = path.split("/velocity/", 1)[1]
            self._handle_velocity(svc_id)

        else:
            self._send_json({"error": "Not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path == "/config":
            self._handle_config_update()
        elif path == "/refresh":
            threading.Thread(target=_poll_all, daemon=True).start()
            self._send_json({"status": "refreshing"})
        else:
            self._send_json({"error": "Not found"}, 404)

    def _handle_usage_all(self):
        services = []
        with _lock:
            for svc_id in _config.get("services", {}):
                if not _config["services"][svc_id].get("enabled", False):
                    continue
                cached = _usage_cache.get(svc_id)
                if cached:
                    services.append(cached["data"])
                else:
                    services.append(_error_result(svc_id, svc_id, "Not yet polled"))
        self._send_json({"services": services})

    def _handle_usage(self, svc_id: str):
        with _lock:
            cached = _usage_cache.get(svc_id)
        if cached and (time.time() - cached["timestamp"]) < CACHE_TTL:
            self._send_json(cached["data"])
        else:
            cfg = _config.get("services", {}).get(svc_id, {})
            adapter = ADAPTERS.get(svc_id)
            if not adapter:
                self._send_json({"error": f"Unknown service: {svc_id}"}, 404)
                return
            result = adapter(cfg)
            with _lock:
                _usage_cache[svc_id] = {"data": result, "timestamp": time.time()}
            if not result.get("error"):
                threading.Thread(
                    target=_record_usage,
                    args=(svc_id, result["percentage"], result.get("details")),
                    daemon=True,
                ).start()
            self._send_json(result)

    def _handle_history(self, svc_id: str, period: str):
        data = _get_history(svc_id, period)
        self._send_json({
            "service_id": svc_id,
            "period": period,
            "data": data,
        })

    def _handle_velocity(self, svc_id: str):
        vel = _calculate_velocity(svc_id)
        if vel is None:
            self._send_json({
                "service_id": svc_id,
                "error": "Insufficient data",
            })
        else:
            self._send_json({"service_id": svc_id, **vel})

    def _handle_config_update(self):
        MAX_CONFIG_SIZE = 64 * 1024  # 64 KB
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > MAX_CONFIG_SIZE:
                self._send_json({"error": "Payload too large"}, 413)
                return
            body = self.rfile.read(length).decode()
            new_config = json.loads(body)
        except (ValueError, json.JSONDecodeError) as e:
            self._send_json({"error": f"Invalid JSON: {e}"}, 400)
            return

        global _config
        with _lock:
            _config.update(new_config)
            # Strip sensitive keys before persisting
            safe_config = json.loads(json.dumps(_config))
            for svc in safe_config.get("services", {}).values():
                svc.pop("api_key", None)
            config_snapshot = json.dumps(safe_config, indent=2)

        # Persist config with restricted permissions
        try:
            CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
            CONFIG_FILE.write_text(config_snapshot)
            CONFIG_FILE.chmod(0o600)
        except Exception as e:
            log.warning("Failed to persist config: %s", e)

        self._send_json({"status": "ok"})

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

def run_server(port: int = 19853):
    global _history

    with _lock:
        _history = _load_history()

    # Load persisted config
    if CONFIG_FILE.exists():
        try:
            loaded = json.loads(CONFIG_FILE.read_text())
            with _lock:
                _config.update(loaded)
            # Ensure restrictive permissions on existing config
            CONFIG_FILE.chmod(0o600)
            log.info("Loaded config from %s", CONFIG_FILE)
        except Exception as e:
            log.warning("Failed to load config: %s", e)

    server = HTTPServer(("127.0.0.1", port), Handler)
    log.info("API Dashboard daemon listening on 127.0.0.1:%d", port)

    poller = Poller()
    poller.start()

    def shutdown(signum, frame):
        log.info("Shutting down...")
        poller.stop()
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        poller.stop()
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description="API Usage Dashboard Backend")
    parser.add_argument("--port", type=int, default=19853)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )
    run_server(args.port)


if __name__ == "__main__":
    main()
