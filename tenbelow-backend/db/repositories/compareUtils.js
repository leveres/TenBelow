/**
 * Shared comparison utilities for JSON vs Prisma repository verification.
 */

function stableStringify(value) {
  return JSON.stringify(value, (_key, val) => {
    if (val && typeof val === "object" && !Array.isArray(val)) {
      return Object.keys(val)
        .sort()
        .reduce((acc, key) => {
          acc[key] = val[key];
          return acc;
        }, {});
    }
    return val;
  });
}

export function compareFieldMaps(id, jsonRecord, prismaRecord, fields) {
  const mismatches = [];
  for (const field of fields) {
    const jsonValue = jsonRecord?.[field];
    const prismaValue = prismaRecord?.[field];
    if (stableStringify(jsonValue) !== stableStringify(prismaValue)) {
      mismatches.push({ id, field, json: jsonValue, prisma: prismaValue });
    }
  }
  return mismatches;
}

export function compareRecordSets({
  repository,
  jsonRecordsById,
  prismaRecordsById,
  comparableFields,
  relationshipMismatches = [],
}) {
  const jsonIds = new Set(Object.keys(jsonRecordsById || {}));
  const prismaIds = new Set(Object.keys(prismaRecordsById || {}));

  const missingInPrisma = [...jsonIds].filter((id) => !prismaIds.has(id));
  const missingInJson = [...prismaIds].filter((id) => !jsonIds.has(id));

  const fieldMismatches = [];
  for (const id of jsonIds) {
    if (!prismaIds.has(id)) continue;
    fieldMismatches.push(
      ...compareFieldMaps(id, jsonRecordsById[id], prismaRecordsById[id], comparableFields)
    );
  }

  const ok =
    missingInPrisma.length === 0 &&
    missingInJson.length === 0 &&
    fieldMismatches.length === 0 &&
    relationshipMismatches.length === 0;

  return {
    repository,
    ok,
    counts: {
      json: jsonIds.size,
      prisma: prismaIds.size,
    },
    missingInPrisma,
    missingInJson,
    fieldMismatches,
    relationshipMismatches,
  };
}

export function logComparisonReport(report) {
  const prefix = `[prisma-compare:${report.repository}]`;
  if (report.ok) {
    console.log(`${prefix} OK — ${report.counts.json} records match`);
    return;
  }
  console.warn(`${prefix} MISMATCH — json=${report.counts.json} prisma=${report.counts.prisma}`);
  if (report.missingInPrisma.length) {
    console.warn(`${prefix} missing in Prisma (${report.missingInPrisma.length}):`, report.missingInPrisma.slice(0, 10));
  }
  if (report.missingInJson.length) {
    console.warn(`${prefix} missing in JSON (${report.missingInJson.length}):`, report.missingInJson.slice(0, 10));
  }
  if (report.fieldMismatches.length) {
    console.warn(`${prefix} field mismatches (${report.fieldMismatches.length}):`, report.fieldMismatches.slice(0, 5));
  }
  if (report.relationshipMismatches.length) {
    console.warn(`${prefix} relationship mismatches:`, report.relationshipMismatches.slice(0, 10));
  }
}

export function printReportSummary(reports) {
  console.log("\n=== Phase 1 Prisma Comparison Report ===");
  for (const report of reports) {
    const status = report.ok ? "OK" : "MISMATCH";
    console.log(`\n[${status}] ${report.repository}`);
    console.log(`  counts: json=${report.counts.json} prisma=${report.counts.prisma}`);
    console.log(`  missingInPrisma: ${report.missingInPrisma.length}`);
    console.log(`  missingInJson: ${report.missingInJson.length}`);
    console.log(`  fieldMismatches: ${report.fieldMismatches.length}`);
    console.log(`  relationshipMismatches: ${report.relationshipMismatches.length}`);
    if (report.fieldMismatches.length) {
      for (const mismatch of report.fieldMismatches.slice(0, 5)) {
        console.log(`    - ${mismatch.id}.${mismatch.field}`);
      }
    }
    if (report.relationshipMismatches.length) {
      for (const rel of report.relationshipMismatches.slice(0, 5)) {
        console.log(`    - ${rel}`);
      }
    }
  }
  const allOk = reports.every((report) => report.ok);
  console.log(`\nOverall: ${allOk ? "ALL REPOSITORIES MATCH" : "MISMATCHES FOUND"}`);
  return allOk;
}
