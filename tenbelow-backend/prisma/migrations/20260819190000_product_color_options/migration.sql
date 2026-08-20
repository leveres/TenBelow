ALTER TABLE "products"
ADD COLUMN "available_colors" JSONB NOT NULL DEFAULT '[]'::JSONB;

ALTER TABLE "order_items"
ADD COLUMN "selected_color_id" VARCHAR(48),
ADD COLUMN "selected_color_name" TEXT,
ADD COLUMN "selected_color_hex" VARCHAR(7);
