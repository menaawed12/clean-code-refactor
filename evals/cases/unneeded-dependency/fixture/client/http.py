import json
import time


class TransientError(Exception):
    """A failure worth retrying, such as a timeout or a 503."""


def fetch_json(transport, url, sleep=time.sleep):
    body = transport.get(url)
    return json.loads(body)
