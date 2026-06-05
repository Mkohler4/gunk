import Stripe from "stripe";
import { stripeConfig } from "../config/stripe";
import type { BillingCheckout } from "../types/billing";

const stripe = new Stripe(stripeConfig.secretKey);

export async function createSubscription(customerId: string, priceId: string): Promise<BillingCheckout> {
  const session = await stripe.checkout.sessions.create({
    customer: customerId,
    line_items: [{ price: priceId, quantity: 1 }],
    mode: "subscription"
  });
  return { id: session.id, url: session.url ?? "" };
}
