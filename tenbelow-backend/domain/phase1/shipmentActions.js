/**
 * Authoritative shipment fulfillment transitions for POST /orders/shipment-action.
 * Keeps the server aligned with the intended preparing -> shipped -> delivered flow.
 */

function normalizeStatus(status) {
  return String(status || "").trim().toLowerCase();
}

export function resolveShipmentAction({
  action,
  shipment = {},
  carrier = "",
  trackingNumber = "",
  timestamp = new Date().toISOString(),
} = {}) {
  const status = normalizeStatus(shipment.status);
  const trimmedAction = String(action || "").trim();
  const trimmedCarrier = String(carrier || "").trim();
  const trimmedTrackingNumber = String(trackingNumber || "").trim();

  switch (trimmedAction) {
    case "startProcessing": {
      if (status === "cancelled" || status === "delivered" || status === "shipped") {
        return {
          ok: false,
          statusCode: 400,
          error: `Cannot start processing a ${status || "unknown"} shipment`,
        };
      }
      return {
        ok: true,
        mutated: false,
        orderStatusOverride: "processing",
        nextShipment: shipment,
        sendShippedEmail: false,
        sendDeliveredEmail: false,
        sendPush: true,
        pushAction: "startProcessing",
      };
    }

    case "markShipped": {
      if (status === "cancelled") {
        return { ok: false, statusCode: 400, error: "Cannot mark a cancelled shipment as shipped" };
      }
      if (status === "delivered") {
        return { ok: false, statusCode: 400, error: "Cannot mark a delivered shipment as shipped" };
      }
      if (status === "shipped") {
        // Already shipped: do not rewrite shippedAt/tracking; allow shipped-email retry only.
        return {
          ok: true,
          mutated: false,
          nextShipment: shipment,
          sendShippedEmail: true,
          sendDeliveredEmail: false,
          sendPush: false,
          pushAction: null,
        };
      }
      if (!trimmedCarrier || !trimmedTrackingNumber) {
        return {
          ok: false,
          statusCode: 400,
          error: "carrier and trackingNumber are required to mark a shipment as shipped",
        };
      }
      if (status !== "preparing") {
        return {
          ok: false,
          statusCode: 400,
          error: `Cannot mark a ${status || "unknown"} shipment as shipped`,
        };
      }
      return {
        ok: true,
        mutated: true,
        nextShipment: {
          ...shipment,
          status: "shipped",
          shippedAt: timestamp,
          carrier: trimmedCarrier,
          trackingNumber: trimmedTrackingNumber,
        },
        sendShippedEmail: true,
        sendDeliveredEmail: false,
        sendPush: true,
        pushAction: "markShipped",
      };
    }

    case "markDelivered": {
      if (status === "cancelled") {
        return { ok: false, statusCode: 400, error: "Cannot mark a cancelled shipment as delivered" };
      }
      if (status === "preparing") {
        return {
          ok: false,
          statusCode: 400,
          error: "Shipment must be marked shipped before it can be marked delivered",
        };
      }
      if (status === "delivered") {
        // Already delivered: preserve deliveredAt; allow delivery-email retry only.
        return {
          ok: true,
          mutated: false,
          nextShipment: shipment,
          sendShippedEmail: false,
          sendDeliveredEmail: true,
          sendPush: false,
          pushAction: null,
        };
      }
      if (status !== "shipped") {
        return {
          ok: false,
          statusCode: 400,
          error: `Cannot mark a ${status || "unknown"} shipment as delivered`,
        };
      }
      return {
        ok: true,
        mutated: true,
        nextShipment: {
          ...shipment,
          status: "delivered",
          deliveredAt: timestamp,
        },
        sendShippedEmail: false,
        sendDeliveredEmail: true,
        sendPush: true,
        pushAction: "markDelivered",
      };
    }

    case "updateTracking": {
      if (!trimmedCarrier || !trimmedTrackingNumber) {
        return {
          ok: false,
          statusCode: 400,
          error: "carrier and trackingNumber are required to update tracking",
        };
      }
      if (!["shipped", "delivered"].includes(status)) {
        return {
          ok: false,
          statusCode: 400,
          error: "Tracking can only be updated after a shipment is marked shipped",
        };
      }
      return {
        ok: true,
        mutated: true,
        nextShipment: {
          ...shipment,
          carrier: trimmedCarrier,
          trackingNumber: trimmedTrackingNumber,
        },
        sendShippedEmail: false,
        sendDeliveredEmail: false,
        sendPush: false,
        pushAction: null,
      };
    }

    default:
      return { ok: false, statusCode: 400, error: "Unknown shipment action" };
  }
}
