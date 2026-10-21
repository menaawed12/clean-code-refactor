import logging

logger = logging.getLogger("payments")


def _masked(card_number):
    return "****" + card_number[-4:]


class PaymentClient:
    def __init__(self, transport, api_key):
        self.transport = transport
        self.api_key = api_key

    def _submit(self, action, path, card_number, amount_cents):
        # Never log the API key or the full card number (CWE-532).
        logger.info("%s card %s amount %s", action, _masked(card_number), amount_cents)
        payload = {"card": card_number, "amount": amount_cents}
        response = self.transport.post(path, payload, headers={"Authorization": "Bearer " + self.api_key})
        logger.debug("%s response id=%s status=%s", action, response["id"], response["status"])
        return {"id": response["id"], "status": response["status"]}

    def charge(self, card_number, amount_cents):
        return self._submit("charging", "/charges", card_number, amount_cents)

    def refund(self, card_number, amount_cents):
        return self._submit("refunding", "/refunds", card_number, amount_cents)
