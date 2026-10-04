class ValidationError(ValueError):
    pass


def _validated_profile(name, email):
    """Return the normalized (name, email) pair or raise ValidationError."""
    if name is None or len(name.strip()) < 2:
        raise ValidationError("name must have at least 2 characters")
    if email is None or "@" not in email or email.startswith("@") or email.endswith("@"):
        raise ValidationError("email is invalid")
    return name.strip(), email.strip().lower()


def register_user(store, name, email):
    name, email = _validated_profile(name, email)
    if email in store:
        raise ValidationError("email is already registered")
    store[email] = {"name": name, "email": email}
    return store[email]


def update_user(store, current_email, name, email):
    if current_email not in store:
        raise KeyError(current_email)
    name, email = _validated_profile(name, email)
    if email != current_email and email in store:
        raise ValidationError("email is already registered")
    record = store.pop(current_email)
    record.update({"name": name, "email": email})
    store[email] = record
    return record
