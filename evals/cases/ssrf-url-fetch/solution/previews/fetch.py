import ipaddress
import socket
import urllib.error
import urllib.request
from urllib.parse import urlsplit

PREVIEW_BYTES = 2048
ALLOWED_SCHEMES = {"http", "https"}


class UnsafeUrl(ValueError):
    """The URL points somewhere the server must not fetch (CWE-918)."""


def _check_public_url(url):
    parts = urlsplit(url)
    if parts.scheme not in ALLOWED_SCHEMES or not parts.hostname:
        raise UnsafeUrl(f"only http and https URLs are allowed: {url!r}")
    try:
        addresses = {info[4][0] for info in socket.getaddrinfo(parts.hostname, parts.port)}
    except socket.gaierror as error:
        raise UnsafeUrl(f"cannot resolve {parts.hostname!r}") from error
    for address in addresses:
        if not ipaddress.ip_address(address).is_global:
            raise UnsafeUrl(f"{parts.hostname!r} resolves to a non-public address")


def fetch_preview(url, opener=urllib.request.urlopen):
    """Return the first bytes of a public web page as text, or "" when it cannot be fetched.

    Raises UnsafeUrl for URLs that point at internal or non-HTTP targets.
    """
    _check_public_url(url)
    try:
        response = opener(url, timeout=5)
    except (urllib.error.URLError, OSError, ValueError):
        return ""
    try:
        return response.read(PREVIEW_BYTES).decode("utf-8", "replace")
    finally:
        response.close()
