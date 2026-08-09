#!/usr/bin/env node
import { createWriteStream, existsSync, readFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";
import PDFDocument from "pdfkit";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(__dirname, "..");
const documentId = process.argv[2] || "seller-agreement-2026-04-24";
const documentDir = path.join(backendRoot, "legal", "documents", documentId);
const contentPath = path.join(documentDir, "content.txt");
const outputPath = path.join(documentDir, `${documentId}.pdf`);

const UNICODE_FONT_CANDIDATES = [
  "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
  "/Library/Fonts/Arial Unicode.ttf",
  "/System/Library/Fonts/Supplemental/Arial.ttf",
  "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
];

function resolveBodyFont() {
  for (const candidate of UNICODE_FONT_CANDIDATES) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

/** PDF built-in Helvetica cannot encode smart quotes; normalize for Preview-safe output. */
function normalizeAgreementText(text) {
  return String(text || "")
    .replace(/\r\n/g, "\n")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
    .replace(/\u2014/g, "--")
    .replace(/\u2013/g, "-")
    .replace(/\u2026/g, "...")
    .trim();
}

function writePdf(outputFile, content, bodyFontPath) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "LETTER",
      margins: { top: 54, bottom: 54, left: 54, right: 54 },
      autoFirstPage: true,
      info: {
        Title: "TenBelow Seller Agreement",
        Author: "Innovative Codeworks LLC",
        Subject: "TenBelow Seller Agreement",
        Creator: "TenBelow backend",
      },
    });

    const stream = createWriteStream(outputFile);
    doc.pipe(stream);

    if (bodyFontPath) {
      doc.registerFont("AgreementBody", bodyFontPath);
      doc.registerFont("AgreementBold", bodyFontPath);
    }

    const titleFont = bodyFontPath ? "AgreementBold" : "Helvetica-Bold";
    const bodyFont = bodyFontPath ? "AgreementBody" : "Helvetica";

    doc.font(titleFont).fontSize(16).fillColor("#0b4f8a").text("TenBelow Seller Agreement", {
      align: "center",
    });
    doc.moveDown(0.4);
    doc.font(bodyFont).fontSize(10).fillColor("#456").text(documentId, { align: "center" });
    doc.moveDown(1.2);

    doc.font(bodyFont).fontSize(10.5).fillColor("#123").text(content, {
      align: "left",
      lineGap: 3,
    });

    doc.end();

    stream.on("finish", resolve);
    stream.on("error", reject);
    doc.on("error", reject);
  });
}

async function main() {
  if (!existsSync(contentPath)) {
    console.error(`Missing agreement text: ${contentPath}`);
    process.exit(1);
  }

  const content = normalizeAgreementText(readFileSync(contentPath, "utf8"));
  const bodyFontPath = resolveBodyFont();

  await writePdf(outputPath, content, bodyFontPath);

  const header = readFileSync(outputPath).subarray(0, 5).toString("ascii");
  if (header !== "%PDF-") {
    console.error("Generated file is not a valid PDF header:", header);
    process.exit(1);
  }

  console.log(`Wrote ${outputPath}`);
  console.log(`Font: ${bodyFontPath || "Helvetica (ASCII-normalized)"}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
