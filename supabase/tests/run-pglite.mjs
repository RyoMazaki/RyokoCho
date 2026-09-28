import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// The PGlite package lives outside the app dependency tree.
const packagePath = process.argv[2];
if (!packagePath) throw new Error("Usage: node supabase/tests/run-pglite.mjs <absolute path to @electric-sql/pglite/dist/index.js>");
const { PGlite } = await import(pathToFileURL(path.resolve(packagePath)).href);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const db = new PGlite();
try {
  await db.exec(await readFile(path.join(root, "tests", "pglite-bootstrap.sql"), "utf8"));
  for (const file of (await readdir(path.join(root, "migrations"))).filter(f => f.endsWith(".sql")).sort()) {
    await db.exec(await readFile(path.join(root, "migrations", file), "utf8"));
    console.log("Applied:", file);
  }
  const sql = await readFile(path.join(root, "tests", "initial-database.sql"), "utf8");
  const results = await db.exec(sql);
  assert(results.some(r => r.rows?.some(row => row.result === "initial_database_checks_passed")));
  const { rows } = await db.query("SELECT count(*)::int AS count FROM auth.users");
  assert.equal(rows[0].count, 0, "fixtures rolled back");
  console.log("PASS: constraints, role/claim-based RLS, RPCs, Storage metadata policies, fixture cleanup.");
  console.log("LIMIT: not Supabase Auth/Storage HTTP, not concurrent multi-connection PostgreSQL.");
} catch (error) {
  console.error("Database test failed:", error.message);
  console.error("SQLSTATE:", error.code, "Context:", error.where ?? error.detail ?? "");
  process.exitCode = 1;
} finally {
  await db.close();
}
