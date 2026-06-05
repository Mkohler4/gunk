import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { storageConfig } from "../config/storage";
import type { UploadResult } from "../types/upload";

const client = new S3Client({ region: storageConfig.region });

export async function uploadImage(file: Blob): Promise<UploadResult> {
  const key = `images/${crypto.randomUUID()}.png`;
  await client.send(new PutObjectCommand({ Bucket: storageConfig.bucket, Key: key, Body: file }));
  return { key, bucket: storageConfig.bucket };
}
