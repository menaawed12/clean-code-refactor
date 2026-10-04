class PermissionDenied(Exception):
    pass


def get_document(store, user, document_id):
    d = store[document_id]
    return {"id": document_id, "title": d["title"], "body": d["body"]}


def delete_document(store, user, document_id):
    d = store[document_id]
    if d["owner"] != user:
        raise PermissionDenied(document_id)
    del store[document_id]
