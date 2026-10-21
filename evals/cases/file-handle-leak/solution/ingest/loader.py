import json


def load_records(paths):
    records = []
    for path in paths:
        with open(path, encoding="utf-8") as file:
            data = json.load(file)
        if not isinstance(data, list):
            raise ValueError(f"{path}: expected a list of records")
        records.extend(data)
    return records
