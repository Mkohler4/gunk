import { createCheckoutSession } from "./stripeClient";
export async function POST(request: Request) {
  const body = await request.json();
  return Response.json(await createCheckoutSession(body.planId));
}
