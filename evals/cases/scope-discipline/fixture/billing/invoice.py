from billing.legacy_tax import tax_rate


def build_invoice(customer, items, region, coupon=None):
    if not items:
        raise ValueError("an invoice needs at least one item")
    lines = []
    subtotal = 0
    for item in items:
        if item["quantity"] <= 0:
            raise ValueError("quantity must be positive")
        amount = round(item["unit_price"] * item["quantity"], 2)
        lines.append({"sku": item["sku"], "quantity": item["quantity"], "amount": amount})
        subtotal = subtotal + amount
    subtotal = round(subtotal, 2)
    discount = 0
    if coupon is not None:
        if coupon["type"] == "percent":
            discount = round(subtotal * coupon["value"] / 100, 2)
        elif coupon["type"] == "fixed":
            discount = min(coupon["value"], subtotal)
        else:
            raise ValueError("unknown coupon type")
    taxable = round(subtotal - discount, 2)
    tax = round(taxable * tax_rate(region), 2)
    total = round(taxable + tax, 2)
    return {
        "customer": customer,
        "lines": lines,
        "subtotal": subtotal,
        "discount": discount,
        "tax": tax,
        "total": total,
    }
