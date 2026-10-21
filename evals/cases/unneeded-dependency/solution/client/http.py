import json
import time

MAX_ATTEMPTS = 3
BASE_DELAY_SECONDS = 0.5


class TransientError(Exception):
    """A failure worth retrying, such as a timeout or a 503."""


def fetch_json(transport, url, sleep=time.sleep):
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            body = transport.get(url)
        except TransientError:
            if attempt == MAX_ATTEMPTS:
                raise
            sleep(BASE_DELAY_SECONDS * 2 ** (attempt - 1))
        else:
            return json.loads(body)
    raise AssertionError("unreachable")
