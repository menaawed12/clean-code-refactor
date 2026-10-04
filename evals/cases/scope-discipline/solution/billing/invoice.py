from billing.legacy_tax import tax_rate


def _invoice_lines(items):
    lines = []
    for item in items:
        if item["quantity"] <= 0:
            raise ValueError("quantity must be positive")
        amount = round(item["unit_price"] * item["quantity"], 2)
        lines.append({"sku": item["sku"], "quantity": item["quantity"], "amount": amount})
    return lines


def _subtotal(lines):
    subtotal = 0
    for line in lines:
        subtotal = subtotal + line["amount"]
    return round(subtotal, 2)


def _discount(subtotal, coupon):
    if coupon is None:
        return 0
    if coupon["type"] == "percent":
        return round(subtotal * coupon["value"] / 100, 2)
    if coupon["type"] == "fixed":
        return min(coupon["value"], subtotal)
    raise ValueError("unknown coupon type")


def build_invoice(customer, items, region, coupon=None):
    if not items:
        raise ValueError("an invoice needs at least one item")
    lines = _invoice_lines(items)
    subtotal = _subtotal(lines)
    discount = _discount(subtotal, coupon)
    taxable = round(subtotal - discount, 2)
    tax = round(taxable * tax_rate(region), 2)
    total = round(taxable + tax, 2)
    return {"customer": customer, "lines": lines, "subtotal": subtotal, "discount": discount, "tax": tax, "total": total}
