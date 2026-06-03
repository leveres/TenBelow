/**
 * Buyer↔seller shop inquiries (pre-order messaging from storefront).
 * One thread per buyer email + seller id.
 */

import { normalizeOrderMessage } from "./orderSupport.js";

export function normalizeInquiryBuyerEmail(email = "") {
  return String(email || "").trim().toLowerCase();
}

export function inquiryThreadKey(buyerEmail, sellerId) {
  return `${normalizeInquiryBuyerEmail(buyerEmail)}|${String(sellerId || "").trim()}`;
}

export function normalizeInquiryMessage(record = {}, sellerId = "") {
  const message = normalizeOrderMessage({
    ...record,
    sellerId: String(record.sellerId || sellerId || "").trim(),
  });
  return message.id && message.text ? message : null;
}

export function normalizeInquiryThread(record = {}) {
  const sellerId = String(record.sellerId || "").trim();
  const buyerEmail = normalizeInquiryBuyerEmail(record.buyerEmail);
  const messages = Array.isArray(record.messages)
    ? record.messages
        .map((entry) => normalizeInquiryMessage(entry, sellerId))
        .filter(Boolean)
        .sort((lhs, rhs) => new Date(lhs.createdAt).getTime() - new Date(rhs.createdAt).getTime())
    : [];

  return {
    id: String(record.id || "").trim() || inquiryThreadKey(buyerEmail, sellerId),
    sellerId,
    buyerEmail,
    buyerName: String(record.buyerName || "").trim() || null,
    messages,
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: record.updatedAt || record.createdAt || new Date().toISOString(),
  };
}

export function findInquiryThread(threads, buyerEmail, sellerId) {
  const key = inquiryThreadKey(buyerEmail, sellerId);
  return threads.find((thread) => inquiryThreadKey(thread.buyerEmail, thread.sellerId) === key) || null;
}

export function upsertInquiryThread(threads, { sellerId, buyerEmail, buyerName = null }) {
  const normalizedSellerId = String(sellerId || "").trim();
  const normalizedEmail = normalizeInquiryBuyerEmail(buyerEmail);
  if (!normalizedSellerId || !normalizedEmail) {
    return { threads, thread: null };
  }

  const existing = findInquiryThread(threads, normalizedEmail, normalizedSellerId);
  if (existing) {
    return { threads, thread: existing };
  }

  const now = new Date().toISOString();
  const thread = normalizeInquiryThread({
    id: inquiryThreadKey(normalizedEmail, normalizedSellerId),
    sellerId: normalizedSellerId,
    buyerEmail: normalizedEmail,
    buyerName,
    messages: [],
    createdAt: now,
    updatedAt: now,
  });

  return { threads: [...threads, thread], thread };
}

export function appendInquiryMessage(threads, { sellerId, buyerEmail, message, buyerName = null }) {
  const normalizedSellerId = String(sellerId || "").trim();
  const normalizedEmail = normalizeInquiryBuyerEmail(buyerEmail);
  const { threads: withThread, thread: existing } = upsertInquiryThread(threads, {
    sellerId: normalizedSellerId,
    buyerEmail: normalizedEmail,
    buyerName,
  });
  if (!existing) {
    return { threads: withThread, thread: null, message: null };
  }

  const key = inquiryThreadKey(normalizedEmail, normalizedSellerId);
  const now = new Date().toISOString();
  let nextThread = null;
  const nextThreads = withThread.map((thread) => {
    if (inquiryThreadKey(thread.buyerEmail, thread.sellerId) !== key) {
      return thread;
    }
    const merged = normalizeInquiryThread({
      ...thread,
      buyerName: buyerName || thread.buyerName,
      messages: [...thread.messages, message],
      updatedAt: now,
    });
    nextThread = merged;
    return merged;
  });

  return { threads: nextThreads, thread: nextThread, message };
}
