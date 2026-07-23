import { mkdirSync, writeFileSync } from "fs";
import { fileURLToPath } from "url";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { MEDIA_DIRECTORY_URL } from "./storagePaths.js";
import {
  isBlockedMediaMime,
  isServableMediaExtension,
  normalizeMediaExtension,
  safeContentTypeForExtension,
} from "./mediaUploadPolicy.js";

function backendBase() {
  return String(process.env.BACKEND_URL || "http://localhost:3000").replace(/\/$/, "");
}

function readObjectStorageEnv() {
  return {
    bucket: String(process.env.S3_MEDIA_BUCKET || "").trim(),
    region: String(process.env.S3_MEDIA_REGION || "").trim(),
    accessKeyId: String(process.env.AWS_ACCESS_KEY_ID || "").trim(),
    secretAccessKey: String(process.env.AWS_SECRET_ACCESS_KEY || "").trim(),
  };
}

/**
 * When object storage is not configured, uploads behave as today (local disk + `/media/...` URL).
 * When S3_MEDIA_BUCKET, S3_MEDIA_REGION, and AWS credentials are all set, objects are written to S3.
 *
 * Env:
 * - S3_MEDIA_BUCKET, S3_MEDIA_REGION (use "auto" for R2 if needed)
 * - AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
 * - S3_ENDPOINT (e.g. Cloudflare R2)
 * - S3_FORCE_PATH_STYLE=true (often needed for R2/MinIO)
 * - PUBLIC_MEDIA_BASE_URL=https://cdn.example.com (no trailing slash) — optional CDN / public bucket URL
 */
export function isObjectStorageEnabled() {
  const { bucket, region, accessKeyId, secretAccessKey } = readObjectStorageEnv();
  return Boolean(bucket && region && accessKeyId && secretAccessKey);
}

export function getPartialObjectStorageWarning() {
  const { bucket, region, accessKeyId, secretAccessKey } = readObjectStorageEnv();
  const hasAny = Boolean(bucket || region || accessKeyId || secretAccessKey);
  const complete = Boolean(bucket && region && accessKeyId && secretAccessKey);
  if (hasAny && !complete) {
    return "S3 media env vars are partially set; using disk storage until bucket, region, and AWS credentials are all configured.";
  }
  return null;
}

export function getMediaStorageMode() {
  if (isObjectStorageEnabled()) return "object_storage";
  if (getPartialObjectStorageWarning()) return "disk_fallback";
  return "disk";
}

function s3Client() {
  const { region, accessKeyId, secretAccessKey } = readObjectStorageEnv();
  return new S3Client({
    region,
    endpoint: String(process.env.S3_ENDPOINT || "").trim() || undefined,
    credentials: { accessKeyId, secretAccessKey },
    forcePathStyle: String(process.env.S3_FORCE_PATH_STYLE || "").toLowerCase() === "true",
  });
}

async function storeMediaBytesOnDisk({ normalizedKey, buffer, mediaPath }) {
  const target = new URL(normalizedKey, MEDIA_DIRECTORY_URL);
  mkdirSync(new URL("./", target), { recursive: true });
  writeFileSync(fileURLToPath(target), buffer);
  // Disk uploads are always served from this backend's /media route. Do not point clients at
  // PUBLIC_MEDIA_BASE_URL when the bytes were not written to object storage.
  return { url: `${backendBase()}${mediaPath}` };
}

/**
 * Extract `sellerId/productId/file.ext` from stored references (/media/, CDN, or absolute backend URLs).
 */
export function mediaRelativeKeyFromReference(reference) {
  const trimmed = String(reference || "").trim();
  if (!trimmed) return null;

  if (trimmed.startsWith("/media/")) {
    return trimmed.replace(/^\/media\//, "").split("?")[0];
  }

  const publicBase = String(process.env.PUBLIC_MEDIA_BASE_URL || "").trim().replace(/\/$/, "");
  if (publicBase && trimmed.startsWith(publicBase)) {
    return trimmed.slice(publicBase.length).replace(/^\//, "").split("?")[0] || null;
  }

  try {
    const parsed = new URL(trimmed);
    if (parsed.pathname.startsWith("/media/")) {
      return parsed.pathname.replace(/^\/media\//, "").split("?")[0];
    }
    const pathKey = parsed.pathname.replace(/^\//, "").split("?")[0];
    if (pathKey.includes("/")) {
      return pathKey;
    }
  } catch {
    // Non-URL strings are returned unchanged by resolveClientMediaURL.
  }

  return null;
}

/** Return a URL the iOS app can load in the current storage configuration. */
export function resolveClientMediaURL(reference) {
  const trimmed = String(reference || "").trim();
  if (!trimmed) return null;

  const relativeKey = mediaRelativeKeyFromReference(trimmed);
  if (!isObjectStorageEnabled() && relativeKey) {
    return `${backendBase()}/media/${relativeKey}`;
  }

  if (trimmed.startsWith("/media/")) {
    return `${backendBase()}${trimmed.split("?")[0]}`;
  }

  return trimmed;
}

/** Prefer portable `/media/...` paths when files live on the Render disk. */
export function canonicalStoredMediaReference(reference) {
  const trimmed = String(reference || "").trim();
  if (!trimmed) return null;

  const relativeKey = mediaRelativeKeyFromReference(trimmed);
  if (!isObjectStorageEnabled() && relativeKey) {
    return `/media/${relativeKey}`;
  }

  return trimmed;
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

  const extension = normalizeMediaExtension(normalizedKey.split(".").pop() || "");
  if (!isServableMediaExtension(extension)) {
    throw new Error("Unsupported media file type");
  }
  const safeContentType = safeContentTypeForExtension(extension);
  const requestedType = String(contentType || "").trim().toLowerCase();
  const resolvedContentType =
    requestedType && !isBlockedMediaMime(requestedType) && requestedType === safeContentType
      ? requestedType
      : safeContentType;
  if (!resolvedContentType) {
    throw new Error("Unsupported media content type");
  }

  const mediaPath = `/media/${normalizedKey}`;
  const publicBase = String(process.env.PUBLIC_MEDIA_BASE_URL || "").trim().replace(/\/$/, "");

  if (!isObjectStorageEnabled()) {
    return storeMediaBytesOnDisk({ normalizedKey, buffer, mediaPath });
  }

  const { bucket } = readObjectStorageEnv();
  await s3Client().send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: normalizedKey,
      Body: buffer,
      ContentType: resolvedContentType,
    })
  );

  const url = publicBase ? `${publicBase}/${normalizedKey}` : `${backendBase()}${mediaPath}`;
  return { url };
}
