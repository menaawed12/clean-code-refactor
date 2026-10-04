from typing import Any, Dict

Store = Dict[str, Dict[str, Any]]


class PermissionDenied(Exception):
    pass


def _owned_document(store: Store, user: str, document_id: str) -> Dict[str, Any]:
    document = store[document_id]
    if document["owner"] != user:
        raise PermissionDenied(document_id)
    return document


def get_document(store: Store, user: str, document_id: str) -> Dict[str, Any]:
    document = _owned_document(store, user, document_id)
    return {"id": document_id, "title": document["title"], "body": document["body"]}


def delete_document(store: Store, user: str, document_id: str) -> None:
    _owned_document(store, user, document_id)
    del store[document_id]
