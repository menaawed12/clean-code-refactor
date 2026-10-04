import re

_PART = re.compile(r"(\d+)([hms])")
_SECONDS = {"h": 3600, "m": 60, "s": 1}


def parse_duration(text):
    """Parse durations such as '1h30m' or '45s' into seconds."""
    if not text or not re.fullmatch(r"(\d+[hms])+", text):
        raise ValueError(f"invalid duration: {text!r}")
    return sum(int(amount) * _SECONDS[unit] for amount, unit in _PART.findall(text))
