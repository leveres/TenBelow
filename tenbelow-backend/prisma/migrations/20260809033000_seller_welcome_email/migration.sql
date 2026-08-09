-- Seller welcome email + immutable agreement acceptance history

CREATE TYPE "WelcomeEmailStatus" AS ENUM ('pending', 'sent', 'failed');

CREATE TABLE "legal_agreement_documents" (
    "id" VARCHAR(128) NOT NULL,
    "agreement_type" VARCHAR(64) NOT NULL DEFAULT 'seller_agreement',
    "version_label" VARCHAR(32) NOT NULL DEFAULT '1.0',
    "effective_date" DATE NOT NULL,
    "document_hash" VARCHAR(128) NOT NULL,
    "storage_path" TEXT NOT NULL DEFAULT '',
    "public_path" TEXT NOT NULL DEFAULT '',
    "is_active_for_new_sellers" BOOLEAN NOT NULL DEFAULT false,
    "published_at" TIMESTAMPTZ(6) NOT NULL,
    "superseded_at" TIMESTAMPTZ(6),

    CONSTRAINT "legal_agreement_documents_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "legal_agreement_documents_agreement_type_is_active_for_new_sellers_idx"
    ON "legal_agreement_documents"("agreement_type", "is_active_for_new_sellers");

CREATE TABLE "seller_agreement_acceptances" (
    "id" UUID NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "agreement_type" VARCHAR(64) NOT NULL DEFAULT 'seller_agreement',
    "document_id" VARCHAR(128) NOT NULL,
    "version" VARCHAR(64) NOT NULL,
    "document_hash" VARCHAR(128) NOT NULL,
    "accepted_at" TIMESTAMPTZ(6) NOT NULL,
    "seller_email" VARCHAR(320) NOT NULL DEFAULT '',
    "seller_legal_name" VARCHAR(255) NOT NULL DEFAULT '',
    "source" VARCHAR(64) NOT NULL DEFAULT 'seller_registration',
    "welcome_email_status" "WelcomeEmailStatus" NOT NULL DEFAULT 'pending',
    "welcome_email_sent_at" TIMESTAMPTZ(6),
    "welcome_email_message_id" VARCHAR(255),
    "welcome_email_last_error" TEXT,
    "welcome_email_attempt_count" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "seller_agreement_acceptances_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "seller_agreement_acceptances_seller_id_document_id_key"
    ON "seller_agreement_acceptances"("seller_id", "document_id");
CREATE INDEX "seller_agreement_acceptances_seller_id_idx"
    ON "seller_agreement_acceptances"("seller_id");
CREATE INDEX "seller_agreement_acceptances_welcome_email_status_idx"
    ON "seller_agreement_acceptances"("welcome_email_status");

ALTER TABLE "seller_agreement_acceptances"
    ADD CONSTRAINT "seller_agreement_acceptances_seller_id_fkey"
    FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "seller_agreement_acceptances"
    ADD CONSTRAINT "seller_agreement_acceptances_document_id_fkey"
    FOREIGN KEY ("document_id") REFERENCES "legal_agreement_documents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
