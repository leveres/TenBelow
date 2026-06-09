import { getPool, isPgEnabled } from "./pgDocuments.mjs";

function asText(value, fallback = "") {
  if (value == null) return fallback;
  return String(value).trim();
}

function asBool(value, fallback = false) {
  if (value == null) return fallback;
  return value === true;
}

function asInt(value, fallback = 0) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function asIso(value) {
  const raw = asText(value, "");
  if (!raw) return null;
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function currentIso() {
  return new Date().toISOString();
}

function foundingAccessStatus(seller = {}, now = new Date()) {
  const isFoundingCreator = seller?.isFoundingCreator === true;
  const startsAt = asIso(seller?.foundingCreatorAccessStartsAt);
  const endsAt = asIso(seller?.foundingCreatorAccessEndsAt);
  const startDate = startsAt ? new Date(startsAt) : null;
  const endDate = endsAt ? new Date(endsAt) : null;
  const hasStarted = !startDate || now >= startDate;
  const hasNotEnded = !!endDate && now <= endDate;
  const hasComplimentaryAccess = isFoundingCreator && hasStarted && hasNotEnded;
  return {
    isFoundingCreator,
    startsAt,
    endsAt,
    hasComplimentaryAccess,
    creatorBadge: asText(seller?.creatorBadge, "Founding Creator"),
  };
}

function membershipStatusForSeller(seller = {}) {
  const founding = foundingAccessStatus(seller);
  const paidActive = seller?.membership?.hasActiveSubscription === true;
  if (founding.hasComplimentaryAccess) return "complimentary";
  if (paidActive) return "active";
  return "expired";
}

export async function ensureRelationalSchema() {
  const pool = getPool();
  if (!pool) return;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sellers (
      id TEXT PRIMARY KEY,
      email TEXT,
      business_name TEXT,
      has_active_subscription BOOLEAN NOT NULL DEFAULT FALSE,
      is_founding_creator BOOLEAN NOT NULL DEFAULT FALSE,
      founding_access_starts_at TIMESTAMPTZ NULL,
      founding_access_ends_at TIMESTAMPTZ NULL,
      membership_status TEXT NOT NULL DEFAULT 'expired',
      creator_badge TEXT NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS buyers (
      id TEXT PRIMARY KEY,
      full_name TEXT NULL,
      email_verified BOOLEAN NOT NULL DEFAULT FALSE,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS products (
      id TEXT PRIMARY KEY,
      seller_id TEXT NULL,
      approval_status TEXT NULL,
      is_active BOOLEAN NOT NULL DEFAULT FALSE,
      is_approved BOOLEAN NOT NULL DEFAULT FALSE,
      price_cents INTEGER NOT NULL DEFAULT 0,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY,
      buyer_email TEXT NULL,
      status TEXT NULL,
      created_at TIMESTAMPTZ NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS weekly_drops (
      week_id TEXT PRIMARY KEY,
      starts_at TIMESTAMPTZ NULL,
      ends_at TIMESTAMPTZ NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS exchanges (
      id TEXT PRIMARY KEY,
      order_id TEXT NULL,
      status TEXT NULL,
      buyer_user_id TEXT NULL,
      seller_id TEXT NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS reviews (
      id TEXT PRIMARY KEY,
      order_id TEXT NULL,
      product_id TEXT NULL,
      buyer_email TEXT NULL,
      rating INTEGER NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS support_messages (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      thread_id TEXT NULL,
      order_id TEXT NULL,
      seller_id TEXT NULL,
      buyer_email TEXT NULL,
      message_type TEXT NULL,
      created_at TIMESTAMPTZ NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS seller_media (
      id TEXT PRIMARY KEY,
      seller_id TEXT NULL,
      product_id TEXT NULL,
      media_kind TEXT NOT NULL,
      url TEXT NOT NULL,
      storage_provider TEXT NOT NULL,
      source TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS creator_programs (
      seller_id TEXT PRIMARY KEY,
      is_founding_creator BOOLEAN NOT NULL DEFAULT FALSE,
      access_starts_at TIMESTAMPTZ NULL,
      access_ends_at TIMESTAMPTZ NULL,
      membership_status TEXT NOT NULL DEFAULT 'expired',
      creator_badge TEXT NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_products_seller_id ON products(seller_id);
    CREATE INDEX IF NOT EXISTS idx_orders_buyer_email ON orders(buyer_email);
    CREATE INDEX IF NOT EXISTS idx_exchanges_order_id ON exchanges(order_id);
    CREATE INDEX IF NOT EXISTS idx_seller_media_seller_product ON seller_media(seller_id, product_id);
    CREATE INDEX IF NOT EXISTS idx_support_messages_order_id ON support_messages(order_id);
  `);
}

async function upsertSeller(pool, sellerId, seller) {
  const founding = foundingAccessStatus(seller);
  const membershipStatus = membershipStatusForSeller(seller);
  await pool.query(
    `INSERT INTO sellers (
      id, email, business_name, has_active_subscription, is_founding_creator,
      founding_access_starts_at, founding_access_ends_at, membership_status, creator_badge, payload, updated_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,NOW())
    ON CONFLICT (id) DO UPDATE SET
      email = EXCLUDED.email,
      business_name = EXCLUDED.business_name,
      has_active_subscription = EXCLUDED.has_active_subscription,
      is_founding_creator = EXCLUDED.is_founding_creator,
      founding_access_starts_at = EXCLUDED.founding_access_starts_at,
      founding_access_ends_at = EXCLUDED.founding_access_ends_at,
      membership_status = EXCLUDED.membership_status,
      creator_badge = EXCLUDED.creator_badge,
      payload = EXCLUDED.payload,
      updated_at = NOW()`,
    [
      sellerId,
      asText(seller?.email, null),
      asText(seller?.businessName, null),
      seller?.membership?.hasActiveSubscription === true,
      founding.isFoundingCreator,
      founding.startsAt,
      founding.endsAt,
      membershipStatus,
      founding.creatorBadge,
      JSON.stringify(seller ?? {}),
    ]
  );

  await pool.query(
    `INSERT INTO creator_programs (
      seller_id, is_founding_creator, access_starts_at, access_ends_at, membership_status, creator_badge, payload, updated_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,NOW())
    ON CONFLICT (seller_id) DO UPDATE SET
      is_founding_creator = EXCLUDED.is_founding_creator,
      access_starts_at = EXCLUDED.access_starts_at,
      access_ends_at = EXCLUDED.access_ends_at,
      membership_status = EXCLUDED.membership_status,
      creator_badge = EXCLUDED.creator_badge,
      payload = EXCLUDED.payload,
      updated_at = NOW()`,
    [
      sellerId,
      founding.isFoundingCreator,
      founding.startsAt,
      founding.endsAt,
      membershipStatus,
      founding.creatorBadge,
      JSON.stringify({
        sellerId,
        isFoundingCreator: founding.isFoundingCreator,
        foundingCreatorAccessStartsAt: founding.startsAt,
        foundingCreatorAccessEndsAt: founding.endsAt,
        membershipStatus,
        creatorBadge: founding.creatorBadge,
      }),
    ]
  );
}

async function replaceSupportMessagesForSource(pool, source, rows) {
  await pool.query(`DELETE FROM support_messages WHERE source = $1`, [source]);
  for (const row of rows) {
    await pool.query(
      `INSERT INTO support_messages (
        id, source, thread_id, order_id, seller_id, buyer_email, message_type, created_at, payload, updated_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,NOW())
      ON CONFLICT (id) DO UPDATE SET
        source = EXCLUDED.source,
        thread_id = EXCLUDED.thread_id,
        order_id = EXCLUDED.order_id,
        seller_id = EXCLUDED.seller_id,
        buyer_email = EXCLUDED.buyer_email,
        message_type = EXCLUDED.message_type,
        created_at = EXCLUDED.created_at,
        payload = EXCLUDED.payload,
        updated_at = NOW()`,
      [
        row.id,
        source,
        row.threadId ?? null,
        row.orderId ?? null,
        row.sellerId ?? null,
        row.buyerEmail ?? null,
        row.messageType ?? null,
        row.createdAt ?? null,
        JSON.stringify(row.payload ?? {}),
      ]
    );
  }
}

async function replaceSellerMediaForSource(pool, source, rows) {
  await pool.query(`DELETE FROM seller_media WHERE source = $1`, [source]);
  for (const row of rows) {
    await pool.query(
      `INSERT INTO seller_media (
        id, seller_id, product_id, media_kind, url, storage_provider, source, created_at, payload, updated_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,NOW())
      ON CONFLICT (id) DO UPDATE SET
        seller_id = EXCLUDED.seller_id,
        product_id = EXCLUDED.product_id,
        media_kind = EXCLUDED.media_kind,
        url = EXCLUDED.url,
        storage_provider = EXCLUDED.storage_provider,
        source = EXCLUDED.source,
        created_at = EXCLUDED.created_at,
        payload = EXCLUDED.payload,
        updated_at = NOW()`,
      [
        row.id,
        row.sellerId ?? null,
        row.productId ?? null,
        row.mediaKind,
        row.url,
        row.storageProvider || "unknown",
        source,
        row.createdAt || currentIso(),
        JSON.stringify(row.payload ?? {}),
      ]
    );
  }
}

function storageProviderFromURL(url = "") {
  const lower = String(url).toLowerCase();
  if (lower.includes("r2.cloudflarestorage.com") || lower.includes("cloudflare")) return "r2";
  if (lower.includes("amazonaws.com")) return "s3";
  if (lower.includes("/media/")) return "local";
  return "unknown";
}

function sellerMediaRowsFromProducts(payload = {}) {
  const products = Array.isArray(payload?.products) ? payload.products : [];
  const rows = [];
  for (const product of products) {
    const sellerId = asText(product?.sellerId, "");
    const productId = asText(product?.id, "");
    if (!sellerId || !productId) continue;
    const images = Array.isArray(product?.imageURLs) ? product.imageURLs : [];
    images.forEach((url, index) => {
      const normalized = asText(url, "");
      if (!normalized) return;
      rows.push({
        id: `${productId}:image:${index}`,
        sellerId,
        productId,
        mediaKind: "image",
        url: normalized,
        storageProvider: storageProviderFromURL(normalized),
        payload: { sellerId, productId, mediaKind: "image", slot: index, url: normalized },
      });
    });
    const demo = asText(product?.demoVideoURL, "");
    if (demo) {
      rows.push({
        id: `${productId}:demo-video:0`,
        sellerId,
        productId,
        mediaKind: "demo-video",
        url: demo,
        storageProvider: storageProviderFromURL(demo),
        payload: { sellerId, productId, mediaKind: "demo-video", slot: 0, url: demo },
      });
    }
    const preview = asText(product?.productionPreviewURL, "");
    if (preview) {
      rows.push({
        id: `${productId}:production-preview:0`,
        sellerId,
        productId,
        mediaKind: "production-preview",
        url: preview,
        storageProvider: storageProviderFromURL(preview),
        payload: { sellerId, productId, mediaKind: "production-preview", slot: 0, url: preview },
      });
    }
  }
  return rows;
}

function sellerMediaRowsFromSellers(sellers = {}) {
  const rows = [];
  for (const [sellerId, seller] of Object.entries(sellers || {})) {
    const avatar = asText(seller?.profile?.avatarURL, "");
    if (avatar) {
      rows.push({
        id: `${sellerId}:avatar:0`,
        sellerId,
        productId: null,
        mediaKind: "avatar",
        url: avatar,
        storageProvider: storageProviderFromURL(avatar),
        payload: { sellerId, mediaKind: "avatar", slot: 0, url: avatar },
      });
    }
    const banner = asText(seller?.profile?.bannerURL, "");
    if (banner) {
      rows.push({
        id: `${sellerId}:banner:0`,
        sellerId,
        productId: null,
        mediaKind: "banner",
        url: banner,
        storageProvider: storageProviderFromURL(banner),
        payload: { sellerId, mediaKind: "banner", slot: 0, url: banner },
      });
    }
  }
  return rows;
}

export async function upsertRelationalForManagedDocument(key, payload) {
  if (!isPgEnabled()) return;
  const pool = getPool();
  if (!pool) return;
  await ensureRelationalSchema();

  switch (key) {
    case "sellers": {
      const sellers = payload && typeof payload === "object" ? payload : {};
      for (const [sellerId, seller] of Object.entries(sellers)) {
        await upsertSeller(pool, sellerId, seller);
      }
      await replaceSellerMediaForSource(pool, "seller_profile", sellerMediaRowsFromSellers(sellers));
      break;
    }
    case "buyers": {
      const buyers = payload && typeof payload === "object" ? payload : {};
      for (const [buyerId, buyer] of Object.entries(buyers)) {
        await pool.query(
          `INSERT INTO buyers (id, full_name, email_verified, payload, updated_at)
           VALUES ($1,$2,$3,$4::jsonb,NOW())
           ON CONFLICT (id) DO UPDATE SET
             full_name = EXCLUDED.full_name,
             email_verified = EXCLUDED.email_verified,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [
            buyerId,
            asText(buyer?.fullName, null),
            asBool(buyer?.emailVerified, false),
            JSON.stringify(buyer ?? {}),
          ]
        );
      }
      break;
    }
    case "products": {
      const products = Array.isArray(payload?.products) ? payload.products : [];
      for (const product of products) {
        const productId = asText(product?.id, "");
        if (!productId) continue;
        await pool.query(
          `INSERT INTO products (id, seller_id, approval_status, is_active, is_approved, price_cents, payload, updated_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,NOW())
           ON CONFLICT (id) DO UPDATE SET
             seller_id = EXCLUDED.seller_id,
             approval_status = EXCLUDED.approval_status,
             is_active = EXCLUDED.is_active,
             is_approved = EXCLUDED.is_approved,
             price_cents = EXCLUDED.price_cents,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [
            productId,
            asText(product?.sellerId, null),
            asText(product?.approvalStatus, null),
            product?.isActive === true,
            product?.isApproved === true,
            asInt(product?.priceCents, 0),
            JSON.stringify(product ?? {}),
          ]
        );
      }
      await replaceSellerMediaForSource(pool, "products", sellerMediaRowsFromProducts(payload));
      break;
    }
    case "orders": {
      const orders = Array.isArray(payload) ? payload : [];
      const supportRows = [];
      for (const order of orders) {
        const orderId = asText(order?.id, "");
        if (!orderId) continue;
        await pool.query(
          `INSERT INTO orders (id, buyer_email, status, created_at, payload, updated_at)
           VALUES ($1,$2,$3,$4,$5::jsonb,NOW())
           ON CONFLICT (id) DO UPDATE SET
             buyer_email = EXCLUDED.buyer_email,
             status = EXCLUDED.status,
             created_at = EXCLUDED.created_at,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [
            orderId,
            asText(order?.buyerEmail, null),
            asText(order?.status, null),
            asIso(order?.createdAt),
            JSON.stringify(order ?? {}),
          ]
        );

        const orderMessages = Array.isArray(order?.orderMessages) ? order.orderMessages : [];
        orderMessages.forEach((msg, idx) => {
          supportRows.push({
            id: asText(msg?.id, `${orderId}:order_message:${idx}`),
            source: "orders",
            threadId: asText(msg?.threadId, null),
            orderId,
            sellerId: asText(msg?.sellerId, null),
            buyerEmail: asText(msg?.buyerEmail, null),
            messageType: "order_message",
            createdAt: asIso(msg?.createdAt) || asIso(order?.createdAt) || currentIso(),
            payload: msg,
          });
        });

        const supportRequests = Array.isArray(order?.supportRequests) ? order.supportRequests : [];
        supportRequests.forEach((req, idx) => {
          supportRows.push({
            id: asText(req?.id, `${orderId}:support_request:${idx}`),
            source: "orders",
            threadId: asText(req?.threadId, null),
            orderId,
            sellerId: asText(req?.sellerId, null),
            buyerEmail: asText(req?.buyerEmail, null),
            messageType: "support_request",
            createdAt: asIso(req?.createdAt) || asIso(order?.createdAt) || currentIso(),
            payload: req,
          });
        });
      }
      await replaceSupportMessagesForSource(pool, "orders", supportRows);
      break;
    }
    case "drops": {
      const drops = payload && typeof payload === "object" ? payload : {};
      for (const [weekId, weekData] of Object.entries(drops)) {
        await pool.query(
          `INSERT INTO weekly_drops (week_id, starts_at, ends_at, payload, updated_at)
           VALUES ($1,$2,$3,$4::jsonb,NOW())
           ON CONFLICT (week_id) DO UPDATE SET
             starts_at = EXCLUDED.starts_at,
             ends_at = EXCLUDED.ends_at,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [
            weekId,
            asIso(weekData?.startsAt),
            asIso(weekData?.endsAt),
            JSON.stringify(weekData ?? {}),
          ]
        );
      }
      break;
    }
    case "exchangeRequests": {
      const exchanges = Array.isArray(payload) ? payload : [];
      for (const exchange of exchanges) {
        const id = asText(exchange?.id, "");
        if (!id) continue;
        await pool.query(
          `INSERT INTO exchanges (id, order_id, status, buyer_user_id, seller_id, payload, updated_at)
           VALUES ($1,$2,$3,$4,$5,$6::jsonb,NOW())
           ON CONFLICT (id) DO UPDATE SET
             order_id = EXCLUDED.order_id,
             status = EXCLUDED.status,
             buyer_user_id = EXCLUDED.buyer_user_id,
             seller_id = EXCLUDED.seller_id,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [
            id,
            asText(exchange?.orderId, null),
            asText(exchange?.status, null),
            asText(exchange?.buyerUserId, null),
            asText(exchange?.sellerId, null),
            JSON.stringify(exchange ?? {}),
          ]
        );
      }
      break;
    }
    case "productReviews": {
      const reviews = Array.isArray(payload) ? payload : [];
      for (const review of reviews) {
        const id = asText(review?.id, "");
        if (!id) continue;
        await pool.query(
          `INSERT INTO reviews (id, order_id, product_id, buyer_email, rating, payload, updated_at)
           VALUES ($1,$2,$3,$4,$5,$6::jsonb,NOW())
           ON CONFLICT (id) DO UPDATE SET
             order_id = EXCLUDED.order_id,
             product_id = EXCLUDED.product_id,
             buyer_email = EXCLUDED.buyer_email,
             rating = EXCLUDED.rating,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [
            id,
            asText(review?.orderId, null),
            asText(review?.productId, null),
            asText(review?.buyerEmail, null),
            review?.rating == null ? null : asInt(review?.rating, 0),
            JSON.stringify(review ?? {}),
          ]
        );
      }
      break;
    }
    case "customOrderRequests": {
      const rows = Array.isArray(payload) ? payload : [];
      await replaceSupportMessagesForSource(
        pool,
        "custom_order_requests",
        rows.map((entry, index) => ({
          id: asText(entry?.id, `custom_order_request:${index}`),
          source: "custom_order_requests",
          threadId: asText(entry?.threadId, null),
          orderId: asText(entry?.orderId, null),
          sellerId: asText(entry?.sellerId, null),
          buyerEmail: asText(entry?.buyerEmail, null),
          messageType: "custom_order_request",
          createdAt: asIso(entry?.createdAt) || currentIso(),
          payload: entry,
        }))
      );
      break;
    }
    case "sellerInquiries": {
      const rows = Array.isArray(payload) ? payload : [];
      const flattened = [];
      rows.forEach((thread, threadIndex) => {
        const threadId = asText(thread?.id, `seller_inquiry_thread:${threadIndex}`);
        const messages = Array.isArray(thread?.messages) ? thread.messages : [];
        if (messages.length === 0) {
          flattened.push({
            id: threadId,
            source: "seller_inquiries",
            threadId,
            orderId: null,
            sellerId: asText(thread?.sellerId, null),
            buyerEmail: asText(thread?.buyerEmail, null),
            messageType: "seller_inquiry_thread",
            createdAt: asIso(thread?.createdAt) || currentIso(),
            payload: thread,
          });
          return;
        }
        messages.forEach((msg, msgIndex) => {
          flattened.push({
            id: asText(msg?.id, `${threadId}:message:${msgIndex}`),
            source: "seller_inquiries",
            threadId,
            orderId: null,
            sellerId: asText(thread?.sellerId, null),
            buyerEmail: asText(thread?.buyerEmail, null),
            messageType: "seller_inquiry_message",
            createdAt: asIso(msg?.createdAt) || asIso(thread?.createdAt) || currentIso(),
            payload: { ...msg, thread },
          });
        });
      });
      await replaceSupportMessagesForSource(pool, "seller_inquiries", flattened);
      break;
    }
    default:
      break;
  }
}

export async function recordSellerMediaUpload(entry = {}) {
  if (!isPgEnabled()) return;
  const pool = getPool();
  if (!pool) return;
  await ensureRelationalSchema();
  const id = asText(entry.id, "");
  const url = asText(entry.url, "");
  if (!id || !url) return;
  await pool.query(
    `INSERT INTO seller_media (
      id, seller_id, product_id, media_kind, url, storage_provider, source, created_at, payload, updated_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,NOW())
    ON CONFLICT (id) DO UPDATE SET
      seller_id = EXCLUDED.seller_id,
      product_id = EXCLUDED.product_id,
      media_kind = EXCLUDED.media_kind,
      url = EXCLUDED.url,
      storage_provider = EXCLUDED.storage_provider,
      source = EXCLUDED.source,
      created_at = EXCLUDED.created_at,
      payload = EXCLUDED.payload,
      updated_at = NOW()`,
    [
      id,
      entry.sellerId ?? null,
      entry.productId ?? null,
      asText(entry.mediaKind, "unknown"),
      url,
      asText(entry.storageProvider, storageProviderFromURL(url)),
      asText(entry.source, "runtime_upload"),
      asIso(entry.createdAt) || currentIso(),
      JSON.stringify(entry.payload ?? entry),
    ]
  );
}

