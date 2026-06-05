import { sendInvite } from "../../../src/services/emailInvite";

export async function POST(request: Request) {
  const body = await request.json();
  return Response.json(await sendInvite(body.email));
}
