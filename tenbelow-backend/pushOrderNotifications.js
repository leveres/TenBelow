import { loadPushDevices } from "./pushDevicesStore.js";
import { sendApnsAlert, isApnsConfigured } from "./apnsSend.js";

/**
 * @param {{ orderId: string; buyerEmail?: string; sellerTotals: Record<string, number>; orderItems?: Array<{ name?: string; productionPreviewURL?: string | null }> }} params
 */
export async function notifyPaymentSucceeded({ orderId, buyerEmail, sellerTotals, orderItems = [] }) {
  if (!isApnsConfigured()) {
    return { skipped: true };
  }

  const map = loadPushDevices();

  /** @type {Promise<{ status: number } | { skipped: boolean }>[]} */
  const jobs = [];

  const firstItemName = String(orderItems[0]?.name || "").trim() || "your order";
  const hasMakerVideo = orderItems.some((item) => Boolean(item?.productionPreviewURL));

  if (buyerEmail) {
    const key = `buyer:${String(buyerEmail).toLowerCase().trim()}`;
    const tokens = map[key] || [];
    const buyerBody = hasMakerVideo
      ? `Order confirmed — see how ${firstItemName} is being made in Order details when production starts.`
      : `TenBelow order ${orderId} is paid. Thanks for your order.`;
    for (const t of tokens) {
      jobs.push(
        sendApnsAlert(t, {
          title: "Order confirmed",
          body: buyerBody,
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

/**
 * @param {{
 *   buyerEmail?: string;
 *   sellerId?: string;
 *   title: string;
 *   body: string;
 * }} params
 */
export async function notifyOrderStatusChanged({ buyerEmail, sellerId, title, body }) {
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
      jobs.push(sendApnsAlert(t, { title, body }));
    }
  }

  if (sellerId) {
    const key = `seller:${String(sellerId).trim()}`;
    const tokens = map[key] || [];
    for (const t of tokens) {
      jobs.push(sendApnsAlert(t, { title, body }));
    }
  }

  await Promise.allSettled(jobs);
  return { sent: jobs.length };
}
