-- TenBelow optional Postgres document store (see db/pgDocuments.mjs).
-- Applied automatically by the server when DATABASE_URL is set; this file documents the shape for operators.

CREATE TABLE IF NOT EXISTS tb_documents (
  key TEXT PRIMARY KEY,
  body JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS tb_documents_updated_at_idx ON tb_documents (updated_at DESC);
