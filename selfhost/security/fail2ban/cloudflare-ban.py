#!/usr/bin/env python3
"""Create or remove a Cloudflare IP block rule. Invoked by fail2ban."""

import ipaddress
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENV_PATH = Path("/etc/fail2ban/cloudflare.env")
NOTE = "fail2ban selfhost"
API = "https://api.cloudflare.com/client/v4"


def load_env(path):
    if not path.is_file():
        sys.exit("missing {}".format(path))
    values = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def call(method, url, token, body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "selfhost-fail2ban")
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return 200, "", json.load(response)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        return exc.code, detail, None


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("ban", "unban"):
        sys.exit("usage: cloudflare-ban ban|unban <ip>")
    action, ip = sys.argv[1], sys.argv[2]
    try:
        parsed = ipaddress.ip_address(ip)
    except ValueError:
        sys.exit("not an IP address: {}".format(ip))

    env = load_env(ENV_PATH)
    token = env.get("CF_API_TOKEN", "")
    zone = env.get("CF_ZONE_ID", "")
    if (
        not token
        or not zone
        or token.startswith("replace-with")
        or zone.startswith("replace-with")
    ):
        sys.exit("set CF_API_TOKEN and CF_ZONE_ID in /etc/fail2ban/cloudflare.env")

    target = "ip6" if parsed.version == 6 else "ip"
    base = "{}/zones/{}/firewall/access_rules/rules".format(
        API, urllib.parse.quote(zone)
    )

    if action == "ban":
        _code, detail, payload = call(
            "POST",
            base,
            token,
            {
                "mode": "block",
                "configuration": {"target": target, "value": ip},
                "notes": NOTE,
            },
        )
        if payload and payload.get("success"):
            return
        if "10009" in detail or "duplicate" in detail.lower():
            return
        sys.exit("cloudflare ban failed: {}".format(detail or payload))

    quoted = urllib.parse.quote(ip)
    _code, detail, payload = call(
        "GET", "{}?per_page=50&configuration.value={}".format(base, quoted), token
    )
    if not payload or not payload.get("success"):
        sys.exit("cloudflare list failed: {}".format(detail or payload))
    for rule in payload.get("result") or []:
        if rule.get("notes") != NOTE:
            continue
        rule_id = rule.get("id")
        if not rule_id:
            continue
        _dcode, ddetail, dpayload = call(
            "DELETE", "{}/{}".format(base, urllib.parse.quote(rule_id)), token
        )
        if not dpayload or not dpayload.get("success"):
            sys.exit("cloudflare unban failed: {}".format(ddetail or dpayload))


if __name__ == "__main__":
    main()
