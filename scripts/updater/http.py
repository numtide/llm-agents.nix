"""HTTP utilities for fetching data from URLs."""

import json
import os
import urllib.request
from typing import Any
from urllib.parse import urlparse

# Only these hosts receive the Authorization header. Matched against the
# parsed hostname, never a substring: "api.github.com" appears inside
# attacker-shaped hosts like api.github.com.evil.com or evil.com/?api.github.com.
GITHUB_API_HOSTS = frozenset({"api.github.com"})


def _is_github_api(url: str) -> bool:
    """Return True only when url's host is exactly a GitHub API host."""
    return urlparse(url).hostname in GITHUB_API_HOSTS


def _github_request(url: str) -> urllib.request.Request:
    """Build an authenticated GitHub API request.

    Uses the GITHUB_TOKEN environment variable so that CI jobs don't hit
    the unauthenticated rate limit (60 req/h → 5 000 req/h).
    """
    req = urllib.request.Request(url)
    token = os.environ.get("GITHUB_TOKEN", "")
    if token:
        req.add_header("Authorization", f"token {token}")
    return req


# Default user-agent avoids 403s from servers that block Python's default.
DEFAULT_USER_AGENT = "llm-agents-updater"


def json_string_at_path(obj: object, dotted_path: str) -> str:
    """Read a string field from nested JSON objects using a dotted key path."""
    current = obj
    for key in dotted_path.split("."):
        if not isinstance(current, dict):
            msg = f"JSON path {dotted_path!r} hit a non-object at {key!r}"
            raise TypeError(msg)
        current = current[key]
    if not isinstance(current, str):
        msg = f"JSON path {dotted_path!r} is not a string"
        raise TypeError(msg)
    return current


def fetch_text(
    url: str, *, timeout: int = 30, user_agent: str = DEFAULT_USER_AGENT
) -> str:
    """Fetch text content from a URL.

    Args:
        url: URL to fetch
        timeout: Request timeout in seconds
        user_agent: User-Agent header value

    Returns:
        Response body as text

    Raises:
        urllib.error.URLError: If the request fails

    """
    req = _github_request(url) if _is_github_api(url) else urllib.request.Request(url)
    req.add_header("User-Agent", user_agent)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        data: bytes = response.read()
        return data.decode("utf-8")


def fetch_json(url: str, *, timeout: int = 30) -> dict[str, Any] | list[Any]:
    """Fetch and parse JSON from a URL.

    Args:
        url: URL to fetch
        timeout: Request timeout in seconds

    Returns:
        Parsed JSON data (dict or list)

    Raises:
        urllib.error.URLError: If the request fails
        json.JSONDecodeError: If response is not valid JSON

    """
    text = fetch_text(url, timeout=timeout)
    result: dict[str, Any] | list[Any] = json.loads(text)
    return result
