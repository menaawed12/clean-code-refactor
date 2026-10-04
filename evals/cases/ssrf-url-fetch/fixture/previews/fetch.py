import urllib.request


def fetch_preview(url, opener=urllib.request.urlopen):
    try:
        response = opener(url, timeout=5)
        data = response.read(2048)
        response.close()
        return data.decode("utf-8", "replace")
    except Exception:
        return ""
