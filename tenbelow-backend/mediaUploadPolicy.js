/**
 * Central media upload + serving policy.
 * Optional future hook: wire MEDIA_SCAN_WEBHOOK_URL for async malware scanning after storeMediaBytes.
 */

const BLOCKED_EXTENSIONS = new Set([
  "html",
  "htm",
  "xhtml",
  "svg",
  "xml",
  "xsl",
  "xslt",
  "js",
  "mjs",
  "cjs",
  "jsx",
  "ts",
  "tsx",
  "php",
  "phtml",
  "asp",
  "aspx",
  "jsp",
  "sh",
  "bash",
  "zsh",
  "exe",
  "dll",
  "bat",
  "cmd",
  "com",
  "msi",
  "jar",
  "wasm",
  "swf",
  "hta",
  "json",
  "pdf",
  "zip",
  "rar",
  "7z",
  "gz",
  "bz2",
  "tar",
  "dmg",
  "apk",
  "ipa",
  "crt",
  "cer",
  "pem",
  "key",
]);

const BLOCKED_MIME_PREFIXES = ["text/", "application/javascript", "application/x-javascript"];
const BLOCKED_MIME_EXACT = new Set([
  "image/svg+xml",
  "application/pdf",
  "application/json",
  "application/xml",
  "text/xml",
  "application/octet-stream",
  "application/x-msdownload",
  "application/x-sh",
  "application/x-httpd-php",
  "multipart/form-data",
]);

const IMAGE_EXTENSIONS = new Set(["jpg", "jpeg", "png", "heic", "heif", "webp"]);
const VIDEO_EXTENSIONS = new Set(["mp4", "mov", "m4v", "qt"]);

const IMAGE_MIME_BY_EXTENSION = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  heic: "image/heic",
  heif: "image/heif",
  webp: "image/webp",
};

const VIDEO_MIME_BY_EXTENSION = {
  mp4: "video/mp4",
  mov: "video/quicktime",
  m4v: "video/mp4",
  qt: "video/quicktime",
};

const SELLER_IMAGE_MEDIA_KINDS = new Set(["image", "avatar", "banner"]);
const SELLER_VIDEO_MEDIA_KINDS = new Set(["demo-video", "production-preview"]);

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value || "").trim(), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export const MEDIA_SIZE_LIMITS = {
  sellerImageBytes: parsePositiveInt(process.env.MEDIA_SELLER_IMAGE_MAX_BYTES, 12 * 1024 * 1024),
  sellerVideoBytes: parsePositiveInt(process.env.MEDIA_SELLER_VIDEO_MAX_BYTES, 50 * 1024 * 1024),
  exchangeImageBytes: parsePositiveInt(process.env.MEDIA_EXCHANGE_IMAGE_MAX_BYTES, 12 * 1024 * 1024),
  exchangeVideoBytes: parsePositiveInt(process.env.MEDIA_EXCHANGE_VIDEO_MAX_BYTES, 50 * 1024 * 1024),
  customOrderRefBytes: parsePositiveInt(process.env.MEDIA_CUSTOM_ORDER_REF_MAX_BYTES, 11 * 1024 * 1024),
};

export function normalizeMediaExtension(value, fallback = "") {
  const normalized = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/^\./, "")
    .replace(/[^a-z0-9]/g, "");
  return normalized || fallback;
}

export function isBlockedMediaExtension(extension = "") {
  const ext = normalizeMediaExtension(extension);
  return !ext || BLOCKED_EXTENSIONS.has(ext);
}

export function isBlockedMediaMime(contentType = "") {
  const normalized = String(contentType || "").trim().toLowerCase();
  if (!normalized) return false;
  if (BLOCKED_MIME_EXACT.has(normalized)) return true;
  return BLOCKED_MIME_PREFIXES.some((prefix) => normalized.startsWith(prefix));
}

function sniffMediaKind(buffer) {
  if (!buffer || buffer.length < 12) return null;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return "jpeg";
  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return "png";
  }
  if (
    buffer.length >= 12 &&
    buffer.toString("ascii", 0, 4) === "RIFF" &&
    buffer.toString("ascii", 8, 12) === "WEBP"
  ) {
    return "webp";
  }
  const brand = buffer.length >= 12 ? buffer.toString("ascii", 4, 8) : "";
  if (brand === "ftyp") {
    const compatible = buffer.toString("ascii", 8, 16).toLowerCase();
    if (compatible.includes("heic") || compatible.includes("heif") || compatible.includes("mif1")) {
      return "heic";
    }
    if (
      compatible.includes("mp4") ||
      compatible.includes("qt") ||
      compatible.includes("mov") ||
      compatible.includes("m4v")
    ) {
      return "mp4";
    }
  }
  return null;
}

function extensionMatchesSniff(extension, sniffed) {
  if (!sniffed) return true;
  if (sniffed === "jpeg") return ["jpg", "jpeg"].includes(extension);
  if (sniffed === "png") return extension === "png";
  if (sniffed === "webp") return extension === "webp";
  if (sniffed === "heic") return ["heic", "heif"].includes(extension);
  if (sniffed === "mp4") return ["mp4", "mov", "m4v", "qt"].includes(extension);
  return false;
}

function resolveAllowedMime(extension, allowedMimeByExtension) {
  return allowedMimeByExtension[extension] || null;
}

function validateAgainstPolicy({
  buffer,
  contentType,
  fileExtension,
  allowedExtensions,
  allowedMimeByExtension,
  maxBytes,
  requireSniffMatch = true,
}) {
  const extension = normalizeMediaExtension(fileExtension);
  if (isBlockedMediaExtension(extension)) {
    return { ok: false, error: "File type is not allowed" };
  }
  if (!allowedExtensions.has(extension)) {
    return { ok: false, error: "Unsupported file extension" };
  }

  const normalizedMime = String(contentType || "").trim().toLowerCase();
  if (isBlockedMediaMime(normalizedMime)) {
    return { ok: false, error: "Unsupported content type" };
  }

  const allowedMime = resolveAllowedMime(extension, allowedMimeByExtension);
  if (normalizedMime && allowedMime && normalizedMime !== allowedMime) {
    return { ok: false, error: "Content type does not match file extension" };
  }

  if (!buffer || !Buffer.isBuffer(buffer) || buffer.length === 0) {
    return { ok: false, error: "Media file is required" };
  }
  if (buffer.length > maxBytes) {
    return { ok: false, error: `File is too large (max ${Math.floor(maxBytes / (1024 * 1024))} MB)` };
  }

  if (requireSniffMatch) {
    const sniffed = sniffMediaKind(buffer);
    if (sniffed && !extensionMatchesSniff(extension, sniffed)) {
      return { ok: false, error: "File contents do not match the declared type" };
    }
  }

  return {
    ok: true,
    extension,
    contentType: allowedMime || normalizedMime || "application/octet-stream",
  };
}

export function validateSellerMediaUpload({ buffer, contentType, fileExtension, mediaKind }) {
  const kind = String(mediaKind || "").trim().toLowerCase();
  if (SELLER_IMAGE_MEDIA_KINDS.has(kind)) {
    return validateAgainstPolicy({
      buffer,
      contentType,
      fileExtension,
      allowedExtensions: IMAGE_EXTENSIONS,
      allowedMimeByExtension: IMAGE_MIME_BY_EXTENSION,
      maxBytes: MEDIA_SIZE_LIMITS.sellerImageBytes,
    });
  }
  if (SELLER_VIDEO_MEDIA_KINDS.has(kind)) {
    return validateAgainstPolicy({
      buffer,
      contentType,
      fileExtension,
      allowedExtensions: VIDEO_EXTENSIONS,
      allowedMimeByExtension: VIDEO_MIME_BY_EXTENSION,
      maxBytes: MEDIA_SIZE_LIMITS.sellerVideoBytes,
    });
  }
  return { ok: false, error: "Unsupported media kind" };
}

export function validateExchangeProofUpload({ buffer, contentType, fileExtension, proofType }) {
  const type = String(proofType || "").trim().toLowerCase();
  if (type === "image") {
    return validateAgainstPolicy({
      buffer,
      contentType,
      fileExtension,
      allowedExtensions: new Set(["jpg", "jpeg", "png", "heic", "heif"]),
      allowedMimeByExtension: {
        jpg: "image/jpeg",
        jpeg: "image/jpeg",
        png: "image/png",
        heic: "image/heic",
        heif: "image/heif",
      },
      maxBytes: MEDIA_SIZE_LIMITS.exchangeImageBytes,
    });
  }
  if (type === "video") {
    return validateAgainstPolicy({
      buffer,
      contentType,
      fileExtension,
      allowedExtensions: VIDEO_EXTENSIONS,
      allowedMimeByExtension: {
        ...VIDEO_MIME_BY_EXTENSION,
        mov: "video/quicktime",
      },
      maxBytes: MEDIA_SIZE_LIMITS.exchangeVideoBytes,
    });
  }
  return { ok: false, error: "x-proof-type must be image or video" };
}

export function validateCustomOrderReferenceUpload({ buffer, contentType, fileExtension }) {
  return validateAgainstPolicy({
    buffer,
    contentType,
    fileExtension,
    allowedExtensions: new Set(["jpg", "jpeg", "png", "heic", "heif"]),
    allowedMimeByExtension: {
      jpg: "image/jpeg",
      jpeg: "image/jpeg",
      png: "image/png",
      heic: "image/heic",
      heif: "image/heif",
    },
    maxBytes: MEDIA_SIZE_LIMITS.customOrderRefBytes,
  });
}

const SERVABLE_EXTENSIONS = new Set([...IMAGE_EXTENSIONS, ...VIDEO_EXTENSIONS]);

export function isServableMediaExtension(extension = "") {
  const ext = normalizeMediaExtension(extension);
  return SERVABLE_EXTENSIONS.has(ext) && !isBlockedMediaExtension(ext);
}

export function safeContentTypeForExtension(extension = "") {
  const ext = normalizeMediaExtension(extension);
  return IMAGE_MIME_BY_EXTENSION[ext] || VIDEO_MIME_BY_EXTENSION[ext] || null;
}

/**
 * Express middleware: block dangerous uploads from being served from /media.
 */
export function safeMediaServingMiddleware() {
  return (req, res, next) => {
    const extension = normalizeMediaExtension(req.path.split(".").pop() || "");
    if (!extension || !isServableMediaExtension(extension)) {
      return res.status(404).end();
    }
    const contentType = safeContentTypeForExtension(extension);
    if (contentType) {
      res.setHeader("Content-Type", contentType);
    }
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Content-Disposition", "inline");
    res.setHeader("Cache-Control", "private, max-age=3600");
    return next();
  };
}
