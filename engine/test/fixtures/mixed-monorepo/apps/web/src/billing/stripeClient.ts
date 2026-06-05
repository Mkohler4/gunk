import Stripe from "stripe";
import { billingConfig } from "./billingConfig";
export async function createCheckoutSession(planId: string) {
  const stripe = new Stripe(billingConfig.secretKey);
  return stripe.checkout.sessions.create({
    mode: "subscription",
    line_items: [{ price: planId, quantity: 1 }],
  });
}
