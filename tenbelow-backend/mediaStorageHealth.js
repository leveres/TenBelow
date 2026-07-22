import { unlinkSync, writeFileSync } from "fs";
import path from "path";
import { MEDIA_DIRECTORY_PATH } from "./storagePaths.js";
import {
  getMediaStorageMode,
  getPartialObjectStorageWarning,
  isObjectStorageEnabled,
} from "./mediaObjectStorage.js";

export function probeMediaDirectoryWritable() {
  try {
    const probe = path.join(MEDIA_DIRECTORY_PATH, `.write_probe_${Date.now()}`);
    writeFileSync(probe, "ok");
    unlinkSync(probe);
    return true;
  } catch {
    return false;
  }
}

export function getMediaStorageChecks() {
  const mode = getMediaStorageMode();
  const partialWarning = getPartialObjectStorageWarning();
  const mediaDirectoryWritable = probeMediaDirectoryWritable();
  const backendUrlConfigured = Boolean(String(process.env.BACKEND_URL || "").trim());

  const checks = {
    mediaStorageMode: mode,
    mediaDirectoryWritable,
    objectStorageEnabled: isObjectStorageEnabled(),
    backendUrlConfigured,
  };

  if (partialWarning) {
    checks.mediaStoragePartialConfig = true;
    checks.mediaStorageWarning = partialWarning;
  }

  if (mode === "object_storage") {
    checks.mediaStorageReady = true;
  } else {
    checks.mediaStorageReady = mediaDirectoryWritable;
  }

  return checks;
}
