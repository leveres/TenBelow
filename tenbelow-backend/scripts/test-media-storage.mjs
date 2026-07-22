#!/usr/bin/env node
/**
 * Verifies seller media storage behavior for common Render misconfigurations.
 *
 * Usage:
 *   node scripts/test-media-storage.mjs
 */
import { storeMediaBytes, getMediaStorageMode, getPartialObjectStorageWarning, isObjectStorageEnabled } from "../mediaObjectStorage.js";
import { getMediaStorageChecks, probeMediaDirectoryWritable } from "../mediaStorageHealth.js";
import { mkdirSync } from "fs";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, ...Buffer.from("JFIF"), 0, 0, 1, 1]);

async function runCase(name, envPatch) {
  for (const key of [
    "S3_MEDIA_BUCKET",
    "S3_MEDIA_REGION",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "BACKEND_DATA_DIR",
    "BACKEND_URL",
  ]) {
    delete process.env[key];
  }

  Object.assign(process.env, envPatch);
  process.env.BACKEND_DATA_DIR = envPatch.BACKEND_DATA_DIR || "/tmp/tb-media-storage-test";
  process.env.BACKEND_URL = envPatch.BACKEND_URL || "https://tenbelow.onrender.com";
  mkdirSync(`${process.env.BACKEND_DATA_DIR}/media`, { recursive: true });

  const mode = getMediaStorageMode();
  const warning = getPartialObjectStorageWarning();
  const checks = getMediaStorageChecks();

  try {
    const { url } = await storeMediaBytes({
      relativeKey: `${name}/profile/avatar-0.jpg`,
      buffer: jpeg,
      contentType: "image/jpeg",
    });
    console.log(`OK  ${name}: mode=${mode} objectStorage=${isObjectStorageEnabled()} url=${url}`);
    if (warning) console.log(`    warning: ${warning}`);
    if (!checks.mediaStorageReady) {
      throw new Error("mediaStorageReady=false");
    }
  } catch (err) {
    console.error(`FAIL ${name}: mode=${mode} ${err.message || err}`);
    process.exitCode = 1;
  }
}

await runCase("disk-only", {});
await runCase("partial-s3-no-creds", {
  S3_MEDIA_BUCKET: "tenbelow-media",
  S3_MEDIA_REGION: "auto",
});
await runCase("partial-s3-bucket-only", {
  S3_MEDIA_BUCKET: "tenbelow-media",
});

if (process.exitCode) {
  console.error("\nMedia storage self-test failed.");
} else {
  console.log("\nMedia storage self-test passed.");
  console.log(`Probe writable: ${probeMediaDirectoryWritable()}`);
}
