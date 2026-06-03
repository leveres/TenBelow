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
          title: "New order received",
          body: `You have a new order (${orderId}) ready to fulfill.`,
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

/**
 * Buyer alerts for shipment lifecycle (shipped / delivered / production).
 */
export async function notifyShipmentStatusToBuyer({
  buyerEmail,
  action,
  itemName = "your item",
  carrier = "",
  trackingNumber = "",
}) {
  const trimmedAction = String(action || "").trim();
  let title = "";
  let body = "";

  if (trimmedAction === "markShipped") {
    title = "Order shipped";
    const trackingBits = [String(carrier || "").trim(), String(trackingNumber || "").trim()].filter(Boolean);
    const trackingSuffix = trackingBits.length ? ` Tracking: ${trackingBits.join(" ")}.` : "";
    body = `${itemName} is on the way.${trackingSuffix}`;
  } else if (trimmedAction === "markDelivered") {
    title = "Order delivered";
    body = `${itemName} has been delivered.`;
  } else if (trimmedAction === "startProcessing") {
    title = "Order in production";
    body = `${itemName} is being prepared by the seller.`;
  } else {
    return { skipped: true };
  }

  return notifyOrderStatusChanged({ buyerEmail, title, body });
}

/**
 * Order support: cancel/refund requests, resolutions, and thread messages.
 */
export async function notifyOrderSupportEvent({
  buyerEmail,
  sellerId,
  notifyBuyer = false,
  notifySeller = false,
  title,
  body,
}) {
  return notifyOrderStatusChanged({
    buyerEmail: notifyBuyer ? buyerEmail : undefined,
    sellerId: notifySeller ? sellerId : undefined,
    title,
    body,
  });
}
