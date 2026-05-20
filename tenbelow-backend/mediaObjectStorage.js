import { mkdirSync, writeFileSync } from "fs";
import { fileURLToPath } from "url";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { MEDIA_DIRECTORY_URL } from "./storagePaths.js";

function backendBase() {
  return String(process.env.BACKEND_URL || "http://localhost:3000").replace(/\/$/, "");
}

/**
 * When object storage is not configured, uploads behave as today (local disk + `/media/...` URL).
 * When S3_MEDIA_BUCKET (+ credentials) are set, objects are written to S3 and a public URL is returned.
 *
 * Env:
 * - S3_MEDIA_BUCKET, S3_MEDIA_REGION (use "auto" for R2 if needed)
 * - AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
 * - S3_ENDPOINT (e.g. Cloudflare R2)
 * - S3_FORCE_PATH_STYLE=true (often needed for R2/MinIO)
 * - PUBLIC_MEDIA_BASE_URL=https://cdn.example.com (no trailing slash) — optional CDN / public bucket URL
 */
export function isObjectStorageEnabled() {
  return Boolean(String(process.env.S3_MEDIA_BUCKET || "").trim() && String(process.env.S3_MEDIA_REGION || "").trim());
}

function s3Client() {
  const accessKeyId = String(process.env.AWS_ACCESS_KEY_ID || "").trim();
  const secretAccessKey = String(process.env.AWS_SECRET_ACCESS_KEY || "").trim();
  return new S3Client({
    region: String(process.env.S3_MEDIA_REGION || "auto"),
    endpoint: String(process.env.S3_ENDPOINT || "").trim() || undefined,
    credentials:
      accessKeyId && secretAccessKey
        ? { accessKeyId, secretAccessKey }
        : undefined,
    forcePathStyle: String(process.env.S3_FORCE_PATH_STYLE || "").toLowerCase() === "true",
  });
}

/**
 * @param {object} opts
 * @param {string} opts.relativeKey path under media root, e.g. `sellerId/productId/image-0.jpg` (no leading slash)
 * @param {Buffer} opts.buffer
 * @param {string} [opts.contentType]
 * @returns {Promise<{ url: string }>} `url` is absolute when PUBLIC_MEDIA_BASE_URL is set or when using http(s) backend; suitable for catalog + clients
 */
export async function storeMediaBytes({ relativeKey, buffer, contentType }) {
  const normalizedKey = String(relativeKey || "").replace(/^\/+/, "");
  if (!normalizedKey) {
    throw new Error("storeMediaBytes: relativeKey required");
  }

  const mediaPath = `/media/${normalizedKey}`;
  const publicBase = String(process.env.PUBLIC_MEDIA_BASE_URL || "").trim().replace(/\/$/, "");

  if (!isObjectStorageEnabled()) {
    const target = new URL(normalizedKey, MEDIA_DIRECTORY_URL);
    mkdirSync(new URL("./", target), { recursive: true });
    writeFileSync(fileURLToPath(target), buffer);
    const url = publicBase ? `${publicBase}/${normalizedKey}` : `${backendBase()}${mediaPath}`;
    return { url };
  }

  const bucket = String(process.env.S3_MEDIA_BUCKET || "").trim();
  await s3Client().send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: normalizedKey,
      Body: buffer,
      ContentType: contentType || "application/octet-stream",
    })
  );

  const url = publicBase ? `${publicBase}/${normalizedKey}` : `${backendBase()}${mediaPath}`;
  return { url };
}
