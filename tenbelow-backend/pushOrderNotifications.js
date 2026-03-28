import { loadPushDevices } from "./pushDevicesStore.js";
import { sendApnsAlert, isApnsConfigured } from "./apnsSend.js";

/**
 * @param {{ orderId: string; buyerEmail?: string; sellerTotals: Record<string, number> }} params
 */
export async function notifyPaymentSucceeded({ orderId, buyerEmail, sellerTotals }) {
  if (!isApnsConfigured()) {
    return { skipped: true };
  }

  const map = loadPushDevices();

  /** @type {Promise<{ status: number } | { skipped: boolean }>[]} */
  const jobs = [];

  if (buyerEmail) {
    const key = `buyer:${String(buyerEmail).toLowerCase().trim()}`;
    const tokens = map[key] || [];
    for (const t of tokens) {
      jobs.push(
        sendApnsAlert(t, {
          title: "Order confirmed",
          body: `TenBelow order ${orderId} is paid.`,
        })
      );
    }
  }

  for (const sellerId of Object.keys(sellerTotals || {})) {
    const key = `seller:${sellerId}`;
    const tokens = map[key] || [];
    for (const t of tokens) {
      jobs.push(
        sendApnsAlert(t, {
          title: "New order",
          body: `You have a new TenBelow order ${orderId}.`,
        })
      );
    }
  }

  await Promise.allSettled(jobs);
  return { sent: jobs.length };
}
