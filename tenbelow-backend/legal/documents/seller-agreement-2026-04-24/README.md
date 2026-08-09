# Seller Agreement v1.0 (`seller-agreement-2026-04-24`)

## Files

| File | Purpose |
|------|---------|
| `content.txt` | Canonical agreement text (synced from iOS `LegalDocumentView.swift`) |
| `seller-agreement-2026-04-24.pdf` | **You add this** — PDF copy attached to the seller welcome email |

## Generate the PDF (recommended)

From the backend folder:

```bash
npm install
npm run generate:seller-agreement-pdf
```

This creates a valid PDF from `content.txt` at `seller-agreement-2026-04-24.pdf`.

**Do not** rename `content.txt` to `.pdf` — Preview requires a real PDF file, not plain text with a PDF extension.

### Manual export (optional)

1. Open `content.txt` in Pages, Word, or Google Docs.
2. Export as PDF named exactly: `seller-agreement-2026-04-24.pdf`
3. Place the PDF in this folder.

## Publishing a new agreement version later

1. Add a **new folder** (do not overwrite this one), e.g. `seller-agreement-2026-10-01/`.
2. Append a new entry to `SELLER_AGREEMENT_REGISTRY` in `legal/sellerAgreementDocuments.js`.
3. Set the previous entry’s `isActiveForNewSellers: false` and `supersededAt`.
4. Run the Prisma seed/sync script for legal documents.

Existing seller acceptance records must continue pointing at the document they accepted.
