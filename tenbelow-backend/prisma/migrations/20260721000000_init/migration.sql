-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "MembershipSource" AS ENUM ('app_store', 'stripe');

-- CreateEnum
CREATE TYPE "MembershipStatus" AS ENUM ('complimentary', 'active', 'expired');

-- CreateEnum
CREATE TYPE "ProductApprovalStatus" AS ENUM ('submitted', 'approved', 'rejected', 'archived');

-- CreateEnum
CREATE TYPE "ProductMediaKind" AS ENUM ('image', 'demo_video', 'production_preview');

-- CreateEnum
CREATE TYPE "CartStatus" AS ENUM ('active', 'checked_out', 'abandoned');

-- CreateEnum
CREATE TYPE "OrderStatus" AS ENUM ('placed', 'processing', 'partiallyShipped', 'shipped', 'delivered', 'cancelled');

-- CreateEnum
CREATE TYPE "SellerOrderStatus" AS ENUM ('preparing', 'shipped', 'delivered', 'cancelled');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('pending', 'succeeded', 'failed', 'cancelled');

-- CreateEnum
CREATE TYPE "RefundStatus" AS ENUM ('pending', 'succeeded', 'failed');

-- CreateEnum
CREATE TYPE "ExchangeReasonCode" AS ENUM ('damaged', 'defective', 'wrong_item', 'poor_quality', 'missing_part', 'other');

-- CreateEnum
CREATE TYPE "ExchangeResolution" AS ENUM ('same_item_exchange');

-- CreateEnum
CREATE TYPE "ExchangeStatus" AS ENUM ('draft', 'submitted', 'awaiting_buyer_proof', 'under_review', 'awaiting_seller_response', 'approved', 'denied', 'replacement_preparing', 'replacement_shipped', 'replacement_delivered', 'closed', 'cancelled');

-- CreateEnum
CREATE TYPE "ExchangeActorType" AS ENUM ('buyer', 'seller', 'admin', 'system');

-- CreateEnum
CREATE TYPE "MediaAssetType" AS ENUM ('image', 'video');

-- CreateEnum
CREATE TYPE "SupportRequestType" AS ENUM ('cancel', 'refund');

-- CreateEnum
CREATE TYPE "SupportRequestStatus" AS ENUM ('pending', 'approved', 'denied', 'withdrawn');

-- CreateEnum
CREATE TYPE "SupportRequestActor" AS ENUM ('buyer', 'seller');

-- CreateEnum
CREATE TYPE "CustomOrderRequestStatus" AS ENUM ('pending', 'accepted', 'declined');

-- CreateEnum
CREATE TYPE "PushUserType" AS ENUM ('buyer', 'seller', 'guest');

-- CreateEnum
CREATE TYPE "PushPlatform" AS ENUM ('ios', 'android', 'web');

-- CreateEnum
CREATE TYPE "AppEnvironment" AS ENUM ('production', 'sandbox', 'development');

-- CreateEnum
CREATE TYPE "NotificationChannel" AS ENUM ('push', 'email');

-- CreateEnum
CREATE TYPE "NotificationStatus" AS ENUM ('queued', 'sent', 'failed');

-- CreateEnum
CREATE TYPE "ModerationTargetType" AS ENUM ('product', 'seller', 'exchange', 'order');

-- CreateTable
CREATE TABLE "buyers" (
    "email" VARCHAR(320) NOT NULL,
    "full_name" TEXT NOT NULL DEFAULT '',
    "password_hash" TEXT NOT NULL DEFAULT '',
    "email_verified" BOOLEAN NOT NULL DEFAULT false,
    "email_verified_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "buyers_pkey" PRIMARY KEY ("email")
);

-- CreateTable
CREATE TABLE "sellers" (
    "id" VARCHAR(24) NOT NULL,
    "email" VARCHAR(320) NOT NULL DEFAULT '',
    "password_hash" TEXT NOT NULL DEFAULT '',
    "stripe_account_id" VARCHAR(255) NOT NULL DEFAULT '',
    "business_name" TEXT NOT NULL DEFAULT '',
    "legal_name" TEXT NOT NULL DEFAULT '',
    "shipping_origin_country" VARCHAR(2) NOT NULL DEFAULT '',
    "shipping_origin_state" VARCHAR(64) NOT NULL DEFAULT '',
    "seller_policies_acknowledged" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "sellers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "seller_agreements" (
    "seller_id" VARCHAR(24) NOT NULL,
    "accepted" BOOLEAN NOT NULL DEFAULT false,
    "accepted_at" TIMESTAMPTZ(6),
    "version" VARCHAR(64) NOT NULL DEFAULT 'seller-agreement-2026-04-24',

    CONSTRAINT "seller_agreements_pkey" PRIMARY KEY ("seller_id")
);

-- CreateTable
CREATE TABLE "seller_memberships" (
    "seller_id" VARCHAR(24) NOT NULL,
    "product_id" TEXT NOT NULL DEFAULT 'com.innovativecodeworks.com.TenBelow.seller.monthly',
    "has_active_subscription" BOOLEAN NOT NULL DEFAULT false,
    "expires_at" TIMESTAMPTZ(6),
    "last_synced_at" TIMESTAMPTZ(6),
    "source" "MembershipSource" NOT NULL DEFAULT 'app_store',
    "original_transaction_id" VARCHAR(255),
    "transaction_id" VARCHAR(255),
    "stripe_subscription_id" VARCHAR(255),
    "stripe_customer_id" VARCHAR(255),
    "membership_status" "MembershipStatus" NOT NULL DEFAULT 'expired',

    CONSTRAINT "seller_memberships_pkey" PRIMARY KEY ("seller_id")
);

-- CreateTable
CREATE TABLE "founding_creator_access" (
    "seller_id" VARCHAR(24) NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT false,
    "starts_at" TIMESTAMPTZ(6),
    "ends_at" TIMESTAMPTZ(6),
    "creator_badge" VARCHAR(128) NOT NULL DEFAULT 'Founding Creator',

    CONSTRAINT "founding_creator_access_pkey" PRIMARY KEY ("seller_id")
);

-- CreateTable
CREATE TABLE "seller_profiles" (
    "seller_id" VARCHAR(24) NOT NULL,
    "display_name" TEXT NOT NULL DEFAULT '',
    "handle" VARCHAR(64) NOT NULL DEFAULT '',
    "bio" TEXT NOT NULL DEFAULT '',
    "avatar_url" TEXT,
    "banner_url" TEXT,
    "website_url" TEXT,
    "custom_order_info_url" TEXT,
    "location" TEXT NOT NULL DEFAULT 'TenBelow',
    "materials" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "processing_time" TEXT NOT NULL DEFAULT 'Printed fresh to order',
    "design_license" TEXT NOT NULL DEFAULT 'Original Designs',
    "product_count" INTEGER NOT NULL DEFAULT 0,
    "order_count" INTEGER NOT NULL DEFAULT 0,
    "total_review_count" INTEGER NOT NULL DEFAULT 0,
    "positive_review_count" INTEGER NOT NULL DEFAULT 0,
    "rating" DECIMAL(4,2) NOT NULL DEFAULT 0,
    "like_count" INTEGER NOT NULL DEFAULT 0,
    "page_view_count" INTEGER NOT NULL DEFAULT 0,
    "is_verified" BOOLEAN NOT NULL DEFAULT false,
    "joined_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ships_in_min_days" INTEGER NOT NULL DEFAULT 2,
    "ships_in_max_days" INTEGER NOT NULL DEFAULT 5,
    "accepts_custom_orders" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "seller_profiles_pkey" PRIMARY KEY ("seller_id")
);

-- CreateTable
CREATE TABLE "products" (
    "id" VARCHAR(64) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "name" TEXT NOT NULL,
    "category" VARCHAR(64) NOT NULL DEFAULT 'desk',
    "price_cents" INTEGER NOT NULL DEFAULT 0,
    "previous_price_cents" INTEGER,
    "material" TEXT NOT NULL DEFAULT 'PLA+',
    "durability_note" TEXT NOT NULL DEFAULT 'Built for everyday use.',
    "care_warnings" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "ships_in_min_days" INTEGER NOT NULL DEFAULT 2,
    "ships_in_max_days" INTEGER NOT NULL DEFAULT 4,
    "is_drop" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT false,
    "is_approved" BOOLEAN NOT NULL DEFAULT false,
    "approval_status" "ProductApprovalStatus" NOT NULL DEFAULT 'submitted',
    "submitted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "reviewed_at" TIMESTAMPTZ(6),
    "archived_at" TIMESTAMPTZ(6),
    "review_notes" TEXT NOT NULL DEFAULT '',
    "drop_headline" TEXT NOT NULL DEFAULT '',
    "drop_story" TEXT NOT NULL DEFAULT '',
    "drop_best_use_case" TEXT NOT NULL DEFAULT '',
    "requires_manual_review" BOOLEAN NOT NULL DEFAULT false,
    "review_reason" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "products_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_media" (
    "id" UUID NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "kind" "ProductMediaKind" NOT NULL,
    "url" TEXT NOT NULL,
    "sort_order" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "product_media_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_rights" (
    "product_id" VARCHAR(64) NOT NULL,
    "ownership_type" VARCHAR(64),
    "reference_flags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "certification_accepted" BOOLEAN NOT NULL DEFAULT false,
    "certification_accepted_at" TIMESTAMPTZ(6),

    CONSTRAINT "product_rights_pkey" PRIMARY KEY ("product_id")
);

-- CreateTable
CREATE TABLE "product_variants" (
    "id" VARCHAR(80) NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "sku" VARCHAR(80) NOT NULL,
    "name" TEXT NOT NULL DEFAULT 'Default',
    "price_cents" INTEGER NOT NULL,
    "is_default" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory_items" (
    "variant_id" VARCHAR(80) NOT NULL,
    "track_inventory" BOOLEAN NOT NULL DEFAULT false,
    "quantity_on_hand" INTEGER,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "inventory_items_pkey" PRIMARY KEY ("variant_id")
);

-- CreateTable
CREATE TABLE "carts" (
    "id" UUID NOT NULL,
    "buyer_email" VARCHAR(320) NOT NULL,
    "status" "CartStatus" NOT NULL DEFAULT 'active',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "carts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cart_items" (
    "id" UUID NOT NULL,
    "cart_id" UUID NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "variant_id" VARCHAR(80) NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "cart_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "orders" (
    "id" VARCHAR(64) NOT NULL,
    "buyer_email" VARCHAR(320) NOT NULL,
    "status" "OrderStatus" NOT NULL DEFAULT 'placed',
    "currency" VARCHAR(3) NOT NULL DEFAULT 'USD',
    "total_cents" INTEGER NOT NULL DEFAULT 0,
    "ship_to_city" VARCHAR(128),
    "ship_to_state" VARCHAR(64),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "seller_orders" (
    "id" VARCHAR(64) NOT NULL,
    "order_id" VARCHAR(64) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "seller_name" TEXT NOT NULL DEFAULT '',
    "seller_handle" VARCHAR(64),
    "status" "SellerOrderStatus" NOT NULL DEFAULT 'preparing',
    "subtotal_cents" INTEGER NOT NULL DEFAULT 0,
    "shipping_cents" INTEGER NOT NULL DEFAULT 0,
    "ship_by_date" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "seller_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "shipments" (
    "id" VARCHAR(64) NOT NULL,
    "seller_order_id" VARCHAR(64) NOT NULL,
    "carrier" VARCHAR(64),
    "tracking_number" VARCHAR(128),
    "shipped_at" TIMESTAMPTZ(6),
    "delivered_at" TIMESTAMPTZ(6),

    CONSTRAINT "shipments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "order_items" (
    "id" VARCHAR(64) NOT NULL,
    "seller_order_id" VARCHAR(64) NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "variant_id" VARCHAR(80),
    "product_name" TEXT NOT NULL,
    "unit_price_cents" INTEGER NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "thumbnail_url" TEXT,
    "production_preview_url" TEXT,

    CONSTRAINT "order_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" UUID NOT NULL,
    "order_id" VARCHAR(64) NOT NULL,
    "stripe_payment_intent_id" VARCHAR(255) NOT NULL,
    "status" "PaymentStatus" NOT NULL DEFAULT 'pending',
    "amount_cents" INTEGER NOT NULL,
    "subtotal_cents" INTEGER NOT NULL DEFAULT 0,
    "shipping_cents" INTEGER NOT NULL DEFAULT 0,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'USD',
    "buyer_email" VARCHAR(320) NOT NULL,
    "stripe_payload" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_transfers" (
    "id" UUID NOT NULL,
    "payment_id" UUID NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "stripe_transfer_id" VARCHAR(255),
    "amount_cents" INTEGER NOT NULL,
    "platform_fee_cents" INTEGER NOT NULL DEFAULT 0,
    "shipping_cents" INTEGER NOT NULL DEFAULT 0,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'USD',
    "idempotency_key" VARCHAR(255),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payment_transfers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refunds" (
    "id" UUID NOT NULL,
    "order_id" VARCHAR(64) NOT NULL,
    "seller_order_id" VARCHAR(64),
    "payment_id" UUID,
    "support_request_id" VARCHAR(64),
    "stripe_refund_id" VARCHAR(255),
    "amount_cents" INTEGER NOT NULL DEFAULT 0,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'USD',
    "status" "RefundStatus" NOT NULL DEFAULT 'pending',
    "reason" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "refunds_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_reviews" (
    "id" VARCHAR(64) NOT NULL,
    "order_id" VARCHAR(64) NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "buyer_email" VARCHAR(320) NOT NULL,
    "rating" INTEGER NOT NULL,
    "review_text" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "product_reviews_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "exchange_requests" (
    "id" VARCHAR(64) NOT NULL,
    "order_id" VARCHAR(64) NOT NULL,
    "order_item_id" VARCHAR(64) NOT NULL,
    "buyer_email" VARCHAR(320) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "product_title" TEXT NOT NULL DEFAULT '',
    "product_image_url" TEXT,
    "reason_code" "ExchangeReasonCode" NOT NULL DEFAULT 'other',
    "buyer_explanation" TEXT NOT NULL DEFAULT '',
    "requested_resolution" "ExchangeResolution" NOT NULL DEFAULT 'same_item_exchange',
    "status" "ExchangeStatus" NOT NULL DEFAULT 'draft',
    "denial_reason" TEXT,
    "admin_notes" TEXT,
    "seller_notes" TEXT,
    "buyer_submitted_at" TIMESTAMPTZ(6),
    "reviewed_at" TIMESTAMPTZ(6),
    "approved_at" TIMESTAMPTZ(6),
    "denied_at" TIMESTAMPTZ(6),
    "replacement_shipped_at" TIMESTAMPTZ(6),
    "replacement_delivered_at" TIMESTAMPTZ(6),
    "closed_at" TIMESTAMPTZ(6),
    "eligibility_checked_at" TIMESTAMPTZ(6),
    "eligible_at_submission" BOOLEAN NOT NULL DEFAULT false,
    "eligibility_failure_reason" TEXT,
    "exchange_number_for_order" INTEGER NOT NULL DEFAULT 1,
    "is_admin_override" BOOLEAN NOT NULL DEFAULT false,
    "tracking_number" VARCHAR(128),
    "shipping_carrier" VARCHAR(64),
    "replacement_order_id" VARCHAR(64),
    "original_variant_snapshot" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "exchange_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "exchange_proof_assets" (
    "id" VARCHAR(64) NOT NULL,
    "exchange_request_id" VARCHAR(64) NOT NULL,
    "asset_type" "MediaAssetType" NOT NULL,
    "url" TEXT NOT NULL,
    "storage_path" TEXT,
    "thumbnail_url" TEXT,
    "uploaded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "uploaded_by_user_id" VARCHAR(320) NOT NULL,

    CONSTRAINT "exchange_proof_assets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "exchange_timeline_events" (
    "id" VARCHAR(64) NOT NULL,
    "exchange_request_id" VARCHAR(64) NOT NULL,
    "event_type" VARCHAR(64) NOT NULL,
    "message" TEXT NOT NULL,
    "actor_type" "ExchangeActorType" NOT NULL,
    "actor_id" VARCHAR(320) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "exchange_timeline_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "weekly_drops" (
    "week_id" VARCHAR(16) NOT NULL,
    "starts_at" TIMESTAMPTZ(6),
    "ends_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "weekly_drops_pkey" PRIMARY KEY ("week_id")
);

-- CreateTable
CREATE TABLE "drop_entries" (
    "id" UUID NOT NULL,
    "week_id" VARCHAR(16) NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "submitted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "drop_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "support_requests" (
    "id" VARCHAR(64) NOT NULL,
    "order_id" VARCHAR(64) NOT NULL,
    "seller_order_id" VARCHAR(64),
    "type" "SupportRequestType" NOT NULL,
    "status" "SupportRequestStatus" NOT NULL DEFAULT 'pending',
    "seller_id" VARCHAR(24) NOT NULL,
    "requested_by" "SupportRequestActor" NOT NULL,
    "reason" TEXT NOT NULL,
    "resolution_note" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "support_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "support_evidence_assets" (
    "id" VARCHAR(64) NOT NULL,
    "support_request_id" VARCHAR(64) NOT NULL,
    "asset_type" "MediaAssetType" NOT NULL,
    "url" TEXT NOT NULL,
    "uploaded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "support_evidence_assets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "order_messages" (
    "id" VARCHAR(64) NOT NULL,
    "order_id" VARCHAR(64) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "sender_role" "SupportRequestActor" NOT NULL,
    "sender_email" VARCHAR(320),
    "sender_name" TEXT,
    "text" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "order_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "custom_order_requests" (
    "id" VARCHAR(64) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "buyer_email" VARCHAR(320) NOT NULL,
    "buyer_name" TEXT NOT NULL DEFAULT '',
    "description" TEXT NOT NULL,
    "reference_image_urls" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "status" "CustomOrderRequestStatus" NOT NULL DEFAULT 'pending',
    "status_updated_at" TIMESTAMPTZ(6),
    "client_ip" VARCHAR(64),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "custom_order_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "seller_inquiry_threads" (
    "id" VARCHAR(512) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "buyer_email" VARCHAR(320) NOT NULL,
    "buyer_name" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "seller_inquiry_threads_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inquiry_messages" (
    "id" VARCHAR(64) NOT NULL,
    "thread_id" VARCHAR(512) NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "sender_role" "SupportRequestActor" NOT NULL,
    "sender_email" VARCHAR(320),
    "sender_name" TEXT,
    "text" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "inquiry_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "push_devices" (
    "id" UUID NOT NULL,
    "user_type" "PushUserType" NOT NULL,
    "user_reference" VARCHAR(320) NOT NULL,
    "user_key" VARCHAR(360) NOT NULL,
    "device_token" VARCHAR(64) NOT NULL,
    "platform" "PushPlatform" NOT NULL DEFAULT 'ios',
    "app_environment" "AppEnvironment" NOT NULL DEFAULT 'production',
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "last_seen_at" TIMESTAMPTZ(6),
    "revoked_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "push_devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_deliveries" (
    "id" UUID NOT NULL,
    "push_device_id" UUID,
    "user_key" VARCHAR(360) NOT NULL,
    "channel" "NotificationChannel" NOT NULL DEFAULT 'push',
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "status" "NotificationStatus" NOT NULL DEFAULT 'queued',
    "error_message" TEXT,
    "metadata" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sent_at" TIMESTAMPTZ(6),

    CONSTRAINT "notification_deliveries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "moderation_records" (
    "id" UUID NOT NULL,
    "target_type" "ModerationTargetType" NOT NULL,
    "target_id" VARCHAR(64) NOT NULL,
    "product_id" VARCHAR(64),
    "seller_id" VARCHAR(24),
    "actor_type" "ExchangeActorType" NOT NULL,
    "actor_id" VARCHAR(320) NOT NULL,
    "action" VARCHAR(64) NOT NULL,
    "decision" VARCHAR(64),
    "notes" TEXT,
    "request_id" VARCHAR(64),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "moderation_records_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_log_entries" (
    "id" BIGSERIAL NOT NULL,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actor_type" "ExchangeActorType",
    "actor_id" VARCHAR(320),
    "action" VARCHAR(128) NOT NULL,
    "target_type" VARCHAR(64),
    "target_id" VARCHAR(320),
    "before_metadata" JSONB,
    "after_metadata" JSONB,
    "request_id" VARCHAR(64),
    "correlation_id" VARCHAR(64),
    "ip_address" VARCHAR(64),
    "http_method" VARCHAR(16),
    "http_path" TEXT,
    "metadata" JSONB,

    CONSTRAINT "audit_log_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "processed_webhook_events" (
    "stripe_event_id" VARCHAR(255) NOT NULL,
    "event_type" VARCHAR(128),
    "processed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "processed_webhook_events_pkey" PRIMARY KEY ("stripe_event_id")
);

-- CreateTable
CREATE TABLE "seller_media_assets" (
    "id" UUID NOT NULL,
    "seller_id" VARCHAR(24) NOT NULL,
    "product_id" VARCHAR(64),
    "media_kind" VARCHAR(64) NOT NULL,
    "url" TEXT NOT NULL,
    "storage_provider" VARCHAR(32) NOT NULL,
    "source" VARCHAR(64) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "seller_media_assets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_config" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "version" INTEGER NOT NULL DEFAULT 2,
    "minimum_order_cents" INTEGER NOT NULL DEFAULT 1500,
    "free_shipping_enabled" BOOLEAN NOT NULL DEFAULT false,
    "drop_enabled" BOOLEAN NOT NULL DEFAULT false,
    "drop_type" VARCHAR(64),
    "drop_title" TEXT,
    "exchange_window_days" INTEGER NOT NULL DEFAULT 7,
    "exchange_config" JSONB NOT NULL DEFAULT '{}',
    "extra" JSONB NOT NULL DEFAULT '{}',
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "app_config_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "sellers_email_idx" ON "sellers"("email");

-- CreateIndex
CREATE INDEX "products_seller_id_idx" ON "products"("seller_id");

-- CreateIndex
CREATE INDEX "products_approval_status_is_active_is_approved_idx" ON "products"("approval_status", "is_active", "is_approved");

-- CreateIndex
CREATE INDEX "product_media_product_id_kind_idx" ON "product_media"("product_id", "kind");

-- CreateIndex
CREATE INDEX "product_variants_product_id_idx" ON "product_variants"("product_id");

-- CreateIndex
CREATE UNIQUE INDEX "product_variants_product_id_sku_key" ON "product_variants"("product_id", "sku");

-- CreateIndex
CREATE INDEX "carts_buyer_email_status_idx" ON "carts"("buyer_email", "status");

-- CreateIndex
CREATE UNIQUE INDEX "cart_items_cart_id_variant_id_key" ON "cart_items"("cart_id", "variant_id");

-- CreateIndex
CREATE INDEX "orders_buyer_email_idx" ON "orders"("buyer_email");

-- CreateIndex
CREATE INDEX "orders_status_idx" ON "orders"("status");

-- CreateIndex
CREATE INDEX "seller_orders_order_id_idx" ON "seller_orders"("order_id");

-- CreateIndex
CREATE INDEX "seller_orders_seller_id_idx" ON "seller_orders"("seller_id");

-- CreateIndex
CREATE UNIQUE INDEX "shipments_seller_order_id_key" ON "shipments"("seller_order_id");

-- CreateIndex
CREATE INDEX "order_items_seller_order_id_idx" ON "order_items"("seller_order_id");

-- CreateIndex
CREATE INDEX "order_items_product_id_idx" ON "order_items"("product_id");

-- CreateIndex
CREATE UNIQUE INDEX "payments_order_id_key" ON "payments"("order_id");

-- CreateIndex
CREATE UNIQUE INDEX "payments_stripe_payment_intent_id_key" ON "payments"("stripe_payment_intent_id");

-- CreateIndex
CREATE INDEX "payments_buyer_email_idx" ON "payments"("buyer_email");

-- CreateIndex
CREATE UNIQUE INDEX "payment_transfers_stripe_transfer_id_key" ON "payment_transfers"("stripe_transfer_id");

-- CreateIndex
CREATE INDEX "payment_transfers_payment_id_idx" ON "payment_transfers"("payment_id");

-- CreateIndex
CREATE INDEX "payment_transfers_seller_id_idx" ON "payment_transfers"("seller_id");

-- CreateIndex
CREATE UNIQUE INDEX "refunds_stripe_refund_id_key" ON "refunds"("stripe_refund_id");

-- CreateIndex
CREATE INDEX "refunds_order_id_idx" ON "refunds"("order_id");

-- CreateIndex
CREATE INDEX "product_reviews_product_id_idx" ON "product_reviews"("product_id");

-- CreateIndex
CREATE INDEX "product_reviews_buyer_email_idx" ON "product_reviews"("buyer_email");

-- CreateIndex
CREATE INDEX "exchange_requests_order_id_idx" ON "exchange_requests"("order_id");

-- CreateIndex
CREATE INDEX "exchange_requests_buyer_email_idx" ON "exchange_requests"("buyer_email");

-- CreateIndex
CREATE INDEX "exchange_requests_seller_id_idx" ON "exchange_requests"("seller_id");

-- CreateIndex
CREATE INDEX "exchange_proof_assets_exchange_request_id_idx" ON "exchange_proof_assets"("exchange_request_id");

-- CreateIndex
CREATE INDEX "exchange_timeline_events_exchange_request_id_idx" ON "exchange_timeline_events"("exchange_request_id");

-- CreateIndex
CREATE INDEX "drop_entries_seller_id_idx" ON "drop_entries"("seller_id");

-- CreateIndex
CREATE UNIQUE INDEX "drop_entries_week_id_product_id_key" ON "drop_entries"("week_id", "product_id");

-- CreateIndex
CREATE INDEX "support_requests_order_id_idx" ON "support_requests"("order_id");

-- CreateIndex
CREATE INDEX "order_messages_order_id_seller_id_idx" ON "order_messages"("order_id", "seller_id");

-- CreateIndex
CREATE INDEX "custom_order_requests_seller_id_idx" ON "custom_order_requests"("seller_id");

-- CreateIndex
CREATE INDEX "custom_order_requests_buyer_email_idx" ON "custom_order_requests"("buyer_email");

-- CreateIndex
CREATE UNIQUE INDEX "seller_inquiry_threads_seller_id_buyer_email_key" ON "seller_inquiry_threads"("seller_id", "buyer_email");

-- CreateIndex
CREATE INDEX "inquiry_messages_thread_id_idx" ON "inquiry_messages"("thread_id");

-- CreateIndex
CREATE UNIQUE INDEX "push_devices_device_token_key" ON "push_devices"("device_token");

-- CreateIndex
CREATE INDEX "push_devices_user_key_enabled_idx" ON "push_devices"("user_key", "enabled");

-- CreateIndex
CREATE INDEX "push_devices_user_type_user_reference_idx" ON "push_devices"("user_type", "user_reference");

-- CreateIndex
CREATE INDEX "notification_deliveries_user_key_created_at_idx" ON "notification_deliveries"("user_key", "created_at");

-- CreateIndex
CREATE INDEX "moderation_records_target_type_target_id_idx" ON "moderation_records"("target_type", "target_id");

-- CreateIndex
CREATE INDEX "moderation_records_product_id_idx" ON "moderation_records"("product_id");

-- CreateIndex
CREATE INDEX "audit_log_entries_occurred_at_idx" ON "audit_log_entries"("occurred_at");

-- CreateIndex
CREATE INDEX "audit_log_entries_action_idx" ON "audit_log_entries"("action");

-- CreateIndex
CREATE INDEX "audit_log_entries_actor_type_actor_id_idx" ON "audit_log_entries"("actor_type", "actor_id");

-- CreateIndex
CREATE INDEX "audit_log_entries_target_type_target_id_idx" ON "audit_log_entries"("target_type", "target_id");

-- CreateIndex
CREATE INDEX "seller_media_assets_seller_id_product_id_idx" ON "seller_media_assets"("seller_id", "product_id");

-- AddForeignKey
ALTER TABLE "seller_agreements" ADD CONSTRAINT "seller_agreements_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_memberships" ADD CONSTRAINT "seller_memberships_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "founding_creator_access" ADD CONSTRAINT "founding_creator_access_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_profiles" ADD CONSTRAINT "seller_profiles_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_media" ADD CONSTRAINT "product_media_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_rights" ADD CONSTRAINT "product_rights_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_variants" ADD CONSTRAINT "product_variants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory_items" ADD CONSTRAINT "inventory_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "carts" ADD CONSTRAINT "carts_buyer_email_fkey" FOREIGN KEY ("buyer_email") REFERENCES "buyers"("email") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cart_items" ADD CONSTRAINT "cart_items_cart_id_fkey" FOREIGN KEY ("cart_id") REFERENCES "carts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cart_items" ADD CONSTRAINT "cart_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cart_items" ADD CONSTRAINT "cart_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_buyer_email_fkey" FOREIGN KEY ("buyer_email") REFERENCES "buyers"("email") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_orders" ADD CONSTRAINT "seller_orders_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_orders" ADD CONSTRAINT "seller_orders_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "shipments" ADD CONSTRAINT "shipments_seller_order_id_fkey" FOREIGN KEY ("seller_order_id") REFERENCES "seller_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_items" ADD CONSTRAINT "order_items_seller_order_id_fkey" FOREIGN KEY ("seller_order_id") REFERENCES "seller_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_items" ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_items" ADD CONSTRAINT "order_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "product_variants"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_transfers" ADD CONSTRAINT "payment_transfers_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "payments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_transfers" ADD CONSTRAINT "payment_transfers_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refunds" ADD CONSTRAINT "refunds_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refunds" ADD CONSTRAINT "refunds_seller_order_id_fkey" FOREIGN KEY ("seller_order_id") REFERENCES "seller_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refunds" ADD CONSTRAINT "refunds_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "payments"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refunds" ADD CONSTRAINT "refunds_support_request_id_fkey" FOREIGN KEY ("support_request_id") REFERENCES "support_requests"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_reviews" ADD CONSTRAINT "product_reviews_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_reviews" ADD CONSTRAINT "product_reviews_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_reviews" ADD CONSTRAINT "product_reviews_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_reviews" ADD CONSTRAINT "product_reviews_buyer_email_fkey" FOREIGN KEY ("buyer_email") REFERENCES "buyers"("email") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exchange_requests" ADD CONSTRAINT "exchange_requests_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exchange_requests" ADD CONSTRAINT "exchange_requests_order_item_id_fkey" FOREIGN KEY ("order_item_id") REFERENCES "order_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exchange_requests" ADD CONSTRAINT "exchange_requests_buyer_email_fkey" FOREIGN KEY ("buyer_email") REFERENCES "buyers"("email") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exchange_requests" ADD CONSTRAINT "exchange_requests_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exchange_requests" ADD CONSTRAINT "exchange_requests_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exchange_proof_assets" ADD CONSTRAINT "exchange_proof_assets_exchange_request_id_fkey" FOREIGN KEY ("exchange_request_id") REFERENCES "exchange_requests"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exchange_timeline_events" ADD CONSTRAINT "exchange_timeline_events_exchange_request_id_fkey" FOREIGN KEY ("exchange_request_id") REFERENCES "exchange_requests"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "drop_entries" ADD CONSTRAINT "drop_entries_week_id_fkey" FOREIGN KEY ("week_id") REFERENCES "weekly_drops"("week_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "drop_entries" ADD CONSTRAINT "drop_entries_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "support_requests" ADD CONSTRAINT "support_requests_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "support_requests" ADD CONSTRAINT "support_requests_seller_order_id_fkey" FOREIGN KEY ("seller_order_id") REFERENCES "seller_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "support_evidence_assets" ADD CONSTRAINT "support_evidence_assets_support_request_id_fkey" FOREIGN KEY ("support_request_id") REFERENCES "support_requests"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_messages" ADD CONSTRAINT "order_messages_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "custom_order_requests" ADD CONSTRAINT "custom_order_requests_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "custom_order_requests" ADD CONSTRAINT "custom_order_requests_buyer_email_fkey" FOREIGN KEY ("buyer_email") REFERENCES "buyers"("email") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_inquiry_threads" ADD CONSTRAINT "seller_inquiry_threads_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_inquiry_threads" ADD CONSTRAINT "seller_inquiry_threads_buyer_email_fkey" FOREIGN KEY ("buyer_email") REFERENCES "buyers"("email") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inquiry_messages" ADD CONSTRAINT "inquiry_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "seller_inquiry_threads"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_push_device_id_fkey" FOREIGN KEY ("push_device_id") REFERENCES "push_devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_records" ADD CONSTRAINT "moderation_records_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_records" ADD CONSTRAINT "moderation_records_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_media_assets" ADD CONSTRAINT "seller_media_assets_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seller_media_assets" ADD CONSTRAINT "seller_media_assets_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE SET NULL ON UPDATE CASCADE;

