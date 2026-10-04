import re

_NON_ALPHANUMERIC = re.compile(r"[^a-z0-9]+")


def slug(text):
    return _NON_ALPHANUMERIC.sub("-", text.strip().lower()).strip("-")


def slug_with_prefix(prefix, text):
    text_slug = slug(text)
    return f"{prefix}-{text_slug}" if text_slug else prefix
