#!/usr/bin/env node
import assert from "node:assert/strict";
import {
  AvailableColorsValidationError,
  MAX_PRODUCT_COLORS,
  normalizeAvailableColors,
  normalizeCatalogProduct,
} from "../domain/phase1/product.js";

assert.deepEqual(normalizeCatalogProduct({ id: "legacy-product" }).availableColors, []);

assert.deepEqual(
  normalizeAvailableColors(
    [
      { name: "  Ocean Blue  ", hex: "1a2b3c" },
      { id: "Warm / White", name: "Warm White" },
    ],
    { strict: true }
  ),
  [
    { id: "ocean-blue", name: "Ocean Blue", hex: "#1A2B3C" },
    { id: "warm-white", name: "Warm White" },
  ]
);

assert.deepEqual(
  normalizeAvailableColors([{ name: "Ocean Blue" }], {
    strict: true,
    existingColors: [{ id: "blue-original", name: "ocean blue", hex: "#0000FF" }],
  }),
  [{ id: "blue-original", name: "Ocean Blue" }]
);

assert.match(normalizeAvailableColors([{ name: "青" }], { strict: true })[0].id, /^color-[0-9a-f]{12}$/);

assert.throws(
  () => normalizeAvailableColors([{ name: "Red" }, { name: " red " }], { strict: true }),
  AvailableColorsValidationError
);
assert.throws(
  () => normalizeAvailableColors(Array.from({ length: MAX_PRODUCT_COLORS + 1 }, (_, index) => ({ name: `Color ${index}` })), { strict: true }),
  AvailableColorsValidationError
);
assert.throws(
  () => normalizeAvailableColors([{ name: "Red", hex: "#F00" }], { strict: true }),
  AvailableColorsValidationError
);

console.log("Product color normalization verified.");
