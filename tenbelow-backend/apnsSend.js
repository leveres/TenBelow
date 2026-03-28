import http2 from "node:http2";
import fs from "fs";
import jwt from "jsonwebtoken";

const BUNDLE_ID = process.env.APNS_BUNDLE_ID || "com.innovativecodeworks.com.TenBelow";

export function isApnsConfigured() {
  return Boolean(
    process.env.APNS_KEY_PATH &&
      process.env.APNS_KEY_ID &&
      process.env.APNS_TEAM_ID &&
      fs.existsSync(process.env.APNS_KEY_PATH)
  );
}

let cachedJwt = { token: "", expiresAt: 0 };

function apnsBearerToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt.token && cachedJwt.expiresAt > now + 120) {
    return cachedJwt.token;
  }

  const key = fs.readFileSync(process.env.APNS_KEY_PATH, "utf8");
  const token = jwt.sign(
    { iss: process.env.APNS_TEAM_ID, iat: now },
    key,
    { algorithm: "ES256", header: { kid: process.env.APNS_KEY_ID, typ: "JWT" } }
  );
  cachedJwt = { token, expiresAt: now + 3500 };
  return token;
}

/**
 * @param {string} deviceTokenHex
 * @param {{ title: string; body: string; sound?: string }} alert
 */
export function sendApnsAlert(deviceTokenHex, { title, body, sound = "default" }) {
  return new Promise((resolve, reject) => {
    if (!isApnsConfigured()) {
      resolve({ skipped: true });
      return;
    }

    const tokenHex = String(deviceTokenHex).toLowerCase();
    const host =
      process.env.APNS_USE_PRODUCTION === "1" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
    const client = http2.connect(`https://${host}`);

    client.on("error", (err) => {
      client.close();
      reject(err);
    });

    const path = `/3/device/${tokenHex}`;
    const payload = JSON.stringify({
      aps: {
        alert: { title, body },
        sound,
      },
    });

    const req = client.request({
      ":method": "POST",
      ":path": path,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      authorization: `bearer ${apnsBearerToken()}`,
      "content-type": "application/json",
      "content-length": Buffer.byteLength(payload, "utf8"),
    });

    let status = 0;
    let respBody = "";

    req.on("response", (headers) => {
      status = Number(headers[":status"] || 0);
    });

    req.on("data", (chunk) => {
      respBody += chunk;
    });

    req.on("end", () => {
      client.close();
      if (status >= 400) {
        console.warn(`APNs ${status} for ${tokenHex.slice(0, 8)}…`, respBody);
      }
      resolve({ status, body: respBody });
    });

    req.end(payload);
  });
}
