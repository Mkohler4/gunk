import { googleOAuthCallback } from "../services/googleOAuth";

export async function authCallback(req, res) {
  const session = await googleOAuthCallback(req.query.code);
  res.json(session);
}
