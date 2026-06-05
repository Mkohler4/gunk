import { OAuth2Client } from "google-auth-library";
import { authConfig } from "../config/auth";
import type { AuthSession } from "../types/auth";

const client = new OAuth2Client(authConfig.clientId, authConfig.clientSecret);

export async function googleOAuthCallback(code: string): Promise<AuthSession> {
  const ticket = await client.verifyIdToken({ idToken: code, audience: authConfig.clientId });
  const payload = ticket.getPayload();
  return { provider: "google", email: payload?.email ?? "" };
}
