import json


def load_records(paths):
    records = []
    for p in paths:
        f = open(p, encoding="utf-8")
        data = json.load(f)
        if not isinstance(data, list):
            raise ValueError(f"{p}: expected a list of records")
        records.extend(data)
        f.close()
    return records
