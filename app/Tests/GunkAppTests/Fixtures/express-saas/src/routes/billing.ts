import { createSubscription } from "../services/stripeBilling";

export async function billingCheckout(req, res) {
  const checkout = await createSubscription(req.body.customerId, req.body.priceId);
  res.json(checkout);
}
