import crypto from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { DATA_DIRECTORY_PATH } from "../storagePaths.js";

export function buildSellerTestOrders({ sellerId, sellerName, buyerEmail = "seller-test-buyer@example.com" }) {
  const normalizedSellerId = String(sellerId || "").trim();
  if (!normalizedSellerId) {
    throw new Error("sellerId is required");
  }

  const suffix = crypto.randomUUID().slice(0, 8).toUpperCase();
  const displayName = String(sellerName || normalizedSellerId).trim() || normalizedSellerId;
  const now = Date.now();

  const placedOrderId = `TB-SEED-${suffix}-1`;
  const processingOrderId = `TB-SEED-${suffix}-2`;
  const shippedOrderId = `TB-SEED-${suffix}-3`;

  const placedShipmentId = `SHIP-${suffix}-1`;
  const processingShipmentId = `SHIP-${suffix}-2`;
  const shippedShipmentId = `SHIP-${suffix}-3`;

  return [
    {
      id: placedOrderId,
      createdAt: new Date(now - 2 * 60 * 60 * 1000).toISOString(),
      status: "placed",
      buyerEmail,
      shipToCity: "Austin",
      shipToState: "TX",
      currency: "USD",
      totalCents: 1800,
      supportRequests: [],
      orderMessages: [],
      shipments: [
        {
          id: placedShipmentId,
          sellerId: normalizedSellerId,
          sellerName: displayName,
          sellerHandle: null,
          status: "preparing",
          shipByDate: new Date(now + 3 * 24 * 60 * 60 * 1000).toISOString(),
          carrier: null,
          trackingNumber: null,
          shippedAt: null,
          deliveredAt: null,
          items: [
            {
              id: `ITEM-${suffix}-1`,
              productId: `prod-seed-${suffix}-1`,
              productName: "Seed Test Cable Clip",
              unitPriceCents: 900,
              quantity: 2,
              thumbnailURL: null,
              productionPreviewURL: null,
            },
          ],
        },
      ],
    },
    {
      id: processingOrderId,
      createdAt: new Date(now - 24 * 60 * 60 * 1000).toISOString(),
      status: "processing",
      buyerEmail,
      shipToCity: "Austin",
      shipToState: "TX",
      currency: "USD",
      totalCents: 1200,
      supportRequests: [],
      orderMessages: [
        {
          id: crypto.randomUUID(),
          sellerId: normalizedSellerId,
          senderRole: "buyer",
          senderEmail: buyerEmail,
          senderName: "Seed Buyer",
          text: "Can you ship this soon?",
          createdAt: new Date(now - 20 * 60 * 60 * 1000).toISOString(),
        },
      ],
      shipments: [
        {
          id: processingShipmentId,
          sellerId: normalizedSellerId,
          sellerName: displayName,
          sellerHandle: null,
          status: "preparing",
          shipByDate: new Date(now + 2 * 24 * 60 * 60 * 1000).toISOString(),
          carrier: null,
          trackingNumber: null,
          shippedAt: null,
          deliveredAt: null,
          items: [
            {
              id: `ITEM-${suffix}-2`,
              productId: `prod-seed-${suffix}-2`,
              productName: "Seed Test Desk Organizer",
              unitPriceCents: 1200,
              quantity: 1,
              thumbnailURL: null,
              productionPreviewURL: null,
            },
          ],
        },
      ],
    },
    {
      id: shippedOrderId,
      createdAt: new Date(now - 4 * 24 * 60 * 60 * 1000).toISOString(),
      status: "shipped",
      buyerEmail,
      shipToCity: "Austin",
      shipToState: "TX",
      currency: "USD",
      totalCents: 1000,
      supportRequests: [],
      orderMessages: [],
      shipments: [
        {
          id: shippedShipmentId,
          sellerId: normalizedSellerId,
          sellerName: displayName,
          sellerHandle: null,
          status: "shipped",
          shipByDate: new Date(now - 2 * 24 * 60 * 60 * 1000).toISOString(),
          carrier: "USPS",
          trackingNumber: `9400${suffix}`,
          shippedAt: new Date(now - 36 * 60 * 60 * 1000).toISOString(),
          deliveredAt: null,
          items: [
            {
              id: `ITEM-${suffix}-3`,
              productId: `prod-seed-${suffix}-3`,
              productName: "Seed Test Phone Stand",
              unitPriceCents: 1000,
              quantity: 1,
              thumbnailURL: null,
              productionPreviewURL: null,
            },
          ],
        },
      ],
    },
  ];
}

export function ordersFilePath() {
  return path.join(DATA_DIRECTORY_PATH, "orders.json");
}

export function sellersFilePath() {
  return path.join(DATA_DIRECTORY_PATH, "sellers.json");
}

export function loadOrdersFile() {
  const path = ordersFilePath();
  try {
    const parsed = JSON.parse(readFileSync(path, "utf-8"));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function saveOrdersFile(orders) {
  writeFileSync(ordersFilePath(), `${JSON.stringify(orders, null, 2)}\n`, "utf-8");
}

export function seedSellerTestOrders({
  sellerId,
  sellerName,
  buyerEmail,
  replaceExistingForSeller = false,
}) {
  const orders = loadOrdersFile();
  const fixtures = buildSellerTestOrders({ sellerId, sellerName, buyerEmail });
  const normalizedSellerId = String(sellerId || "").trim();

  const retained = replaceExistingForSeller
    ? orders.filter(
        (order) =>
          !(Array.isArray(order?.shipments) ? order.shipments : []).some(
            (shipment) => String(shipment?.sellerId || "").trim() === normalizedSellerId
          )
      )
    : orders;

  const nextOrders = [...fixtures, ...retained];
  saveOrdersFile(nextOrders);

  return {
    inserted: fixtures.length,
    orderIds: fixtures.map((order) => order.id),
    shipmentIds: fixtures.flatMap((order) => order.shipments.map((shipment) => shipment.id)),
    dataDirectory: DATA_DIRECTORY_PATH,
  };
}

export function grantFoundingCreatorMembership({ sellerId, years = 1 }) {
  const sellersPath = sellersFilePath();
  const sellers = JSON.parse(readFileSync(sellersPath, "utf-8"));
  const normalizedSellerId = String(sellerId || "").trim();
  if (!sellers[normalizedSellerId]) {
    throw new Error(`Seller not found in sellers.json: ${normalizedSellerId}`);
  }

  const startsAt = new Date().toISOString();
  const endsAt = new Date(Date.now() + years * 365 * 24 * 60 * 60 * 1000).toISOString();
  sellers[normalizedSellerId] = {
    ...sellers[normalizedSellerId],
    isFoundingCreator: true,
    foundingCreatorAccessStartsAt: startsAt,
    foundingCreatorAccessEndsAt: endsAt,
  };
  writeFileSync(sellersPath, `${JSON.stringify(sellers, null, 2)}\n`, "utf-8");

  return {
    sellerId: normalizedSellerId,
    foundingCreatorAccessStartsAt: startsAt,
    foundingCreatorAccessEndsAt: endsAt,
  };
}
