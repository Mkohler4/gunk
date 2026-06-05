import { uploadImage } from "../../../src/services/s3Upload";

export async function POST(request: Request) {
  const file = await request.blob();
  return Response.json(await uploadImage(file));
}
