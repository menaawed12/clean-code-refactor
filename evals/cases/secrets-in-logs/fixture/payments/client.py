import logging

logger = logging.getLogger("payments")


class PaymentClient:
    def __init__(self, transport, api_key):
        self.transport = transport
        self.api_key = api_key

    def charge(self, card_number, amount_cents):
        logger.info("charging card %s amount %s with key %s", card_number, amount_cents, self.api_key)
        payload = {"card": card_number, "amount": amount_cents}
        response = self.transport.post("/charges", payload, headers={"Authorization": "Bearer " + self.api_key})
        logger.debug("charge response %s", response)
        return {"id": response["id"], "status": response["status"]}

    def refund(self, card_number, amount_cents):
        logger.info("refunding card %s amount %s with key %s", card_number, amount_cents, self.api_key)
        payload = {"card": card_number, "amount": amount_cents}
        response = self.transport.post("/refunds", payload, headers={"Authorization": "Bearer " + self.api_key})
        logger.debug("refund response %s", response)
        return {"id": response["id"], "status": response["status"]}
