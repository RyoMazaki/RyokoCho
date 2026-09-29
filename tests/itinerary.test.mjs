import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import ts from "typescript";

const source = readFileSync(new URL("../src/lib/itinerary/queries.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
});
const tripId = "30000000-0000-0000-0000-000000000001";
const itemId = "40000000-0000-0000-0000-000000000001";
const date = "2026-10-01";
const columns = "id,trip_id,date,category,title,sort_order,time_type,exact_time,time_period,duration_minutes";
const item = { id: itemId, trip_id: tripId, date, category: "place", title: "Station",
  sort_order: 0, time_type: "none", exact_time: null, time_period: null, duration_minutes: null };

function setup({ user = { id: "user" }, authError = null, authThrows = false,
  rows = [item], count = rows?.length, detail = item, dbError = null,
  dbThrows = false, clientThrows = false } = {}) {
  const calls = [];
  let denied = false;
  const query = {
    eq(column, value) { calls.push(["eq", column, value]); return query; },
    order(column, options) { calls.push(["order", column, options]); return query; },
    limit(value) { calls.push(["limit", value]); return query; },
    or(value) { calls.push(["or", value]); return query; },
    async maybeSingle() {
      if (dbThrows) throw new Error("private SQL details");
      return { data: denied ? null : detail, error: dbError };
    },
    then(resolve, reject) {
      return (dbThrows ? Promise.reject(new Error("private SQL details")) :
        Promise.resolve({ data: denied ? [] : rows, count: denied ? 0 : count, error: dbError }))
        .then(resolve, reject);
    },
  };
  const imports = {
    "server-only": {},
    "@supabase/supabase-js": { isAuthSessionMissingError: e => e?.name === "AuthSessionMissingError" },
    "@/lib/supabase/auth": { getCurrentUser: async () => {
      calls.push(["authenticate"]);
      if (authThrows) throw new Error("private auth details");
      return { data: { user }, error: authError };
    } },
    "@/lib/supabase/server": { createClient: async () => {
      calls.push(["client"]);
      if (clientThrows) throw new Error("private config details");
      return { from(table) {
        calls.push(["from", table]);
        return { select(fields, options) {
          calls.push(["select", fields, options]);
          return query;
        } };
      } };
    } },
  };
  const compiled = { exports: {} };
  runInNewContext(outputText, { module: compiled, exports: compiled.exports,
    require(name) {
      if (!(name in imports)) throw new Error("Unexpected import: " + name);
      return imports[name];
    } });
  return { ...compiled.exports, calls, leave() { denied = true; } };
}
const reads = s => [() => s.listMyItineraryItems(tripId, date), () => s.getMyItineraryItem(tripId, itemId)];

test("unauthenticated callers never create a database client", async () => {
  for (const authError of [null, { name: "AuthSessionMissingError" }, { status: 401 }, { status: 403 }]) {
    const s = setup({ user: null, authError });
    for (const read of reads(s)) await assert.rejects(read(), { code: "UNAUTHENTICATED" });
    assert.equal(s.calls.some(([op]) => op === "client"), false);
  }
});
test("auth outages are distinct from signed-out results", async () => {
  for (const options of [{ authError: { status: 503 } }, { authThrows: true }]) {
    for (const read of reads(setup(options))) await assert.rejects(read(), { code: "AUTH_UNAVAILABLE" });
  }
});
test("day list scopes by trip/date and orders by sort_order then id", async () => {
  const s = setup();
  const page = await s.listMyItineraryItems(tripId, date);
  assert.equal(page.items[0], item);
  assert.equal(page.nextCursor, null);
  assert.deepEqual(s.calls.filter(([op]) => op === "eq"), [["eq", "trip_id", tripId], ["eq", "date", date]]);
  assert.deepEqual(s.calls.filter(([op]) => op === "order").map(c => c[1]), ["sort_order", "id"]);
  assert.ok(s.calls.filter(([op]) => op === "order").every(c => c[2].ascending));
  assert.equal(s.calls.find(([op]) => op === "select")[1], columns);
  assert.equal(s.calls.find(([op]) => op === "select")[2].count, "exact");
  assert.deepEqual(s.calls.filter(([op]) => op === "from"), [["from", "itinerary_items"]]);
});
test("detail filters both IDs and preserves categories, times and null values", async () => {
  const s = setup();
  assert.equal(await s.getMyItineraryItem(tripId, itemId), item);
  assert.deepEqual(s.calls.filter(([op]) => op === "eq"), [["eq", "trip_id", tripId], ["eq", "id", itemId]]);
  assert.equal(s.calls.find(([op]) => op === "select")[1], columns);
  for (const detail of [
    { ...item, category: "transportation", time_type: "exact", exact_time: "18:30:00", duration_minutes: 25 },
    { ...item, time_type: "period", time_period: "朝" },
  ]) assert.equal(await setup({ detail }).getMyItineraryItem(tripId, itemId), detail);
});
test("empty or RLS-hidden list succeeds; missing or hidden detail is NOT_FOUND", async () => {
  const s = setup({ rows: [], detail: null });
  const page = await s.listMyItineraryItems(tripId, date);
  assert.equal(page.items.length, 0);
  assert.equal(page.nextCursor, null);
  await assert.rejects(s.getMyItineraryItem(tripId, itemId), { code: "NOT_FOUND" });
});
test("each call rechecks authentication and reflects loss of membership", async () => {
  const s = setup();
  assert.equal((await s.listMyItineraryItems(tripId, date)).items.length, 1);
  s.leave();
  assert.equal((await s.listMyItineraryItems(tripId, date)).items.length, 0);
  await assert.rejects(s.getMyItineraryItem(tripId, itemId), { code: "NOT_FOUND" });
  assert.equal(s.calls.filter(([op]) => op === "authenticate").length, 3);
});
test("compound cursor continues tied order values even under a smaller API row cap", async () => {
  const s = setup({ count: 3 });
  const page = await s.listMyItineraryItems(tripId, date, { pageSize: 100 });
  assert.equal(page.nextCursor.sortOrder, 0);
  assert.equal(page.nextCursor.id, itemId);
  await s.listMyItineraryItems(tripId, date, { cursor: page.nextCursor });
  assert.equal(s.calls.find(([op]) => op === "or")[1], `sort_order.gt.0,and(sort_order.eq.0,id.gt.${itemId})`);
  assert.equal(s.calls.find(([op]) => op === "limit")[1], 100);
});
test("invalid UUIDs, calendar dates, sizes and filter-injection cursors never SELECT", async () => {
  const s = setup();
  for (const value of ["", "not-a-uuid", itemId + ",id.gt.0"]) {
    await assert.rejects(s.listMyItineraryItems(value, date), { code: "INVALID_INPUT" });
    await assert.rejects(s.getMyItineraryItem(tripId, value), { code: "INVALID_INPUT" });
    await assert.rejects(s.getMyItineraryItem(value, itemId), { code: "INVALID_INPUT" });
    await assert.rejects(s.listMyItineraryItems(tripId, date, { cursor: { sortOrder: 0, id: value } }), { code: "INVALID_INPUT" });
  }
  for (const value of ["2026-02-29", "2026-04-31", "2026-00-01", "2026-13-01", "2026-1-01", "0000-01-01", "2026-10-01T00:00:00Z", ""]) {
    await assert.rejects(s.listMyItineraryItems(tripId, value), { code: "INVALID_INPUT" });
  }
  for (const pageSize of [0, -1, 101, 1.5, NaN, Infinity]) {
    await assert.rejects(s.listMyItineraryItems(tripId, date, { pageSize }), { code: "INVALID_INPUT" });
  }
  for (const sortOrder of [-1, 0.5, NaN, Infinity, 2147483648, "0,id.gt.0"]) {
    await assert.rejects(s.listMyItineraryItems(tripId, date, { cursor: { sortOrder, id: itemId } }), { code: "INVALID_INPUT" });
  }
  await assert.rejects(s.listMyItineraryItems(tripId, date, { cursor: null }), { code: "INVALID_INPUT" });
  assert.equal(s.calls.some(([op]) => op === "from"), false);
});
test("valid leap dates pass without timezone conversion", async () => {
  const s = setup({ rows: [] });
  for (const value of ["2028-02-29", "0001-01-01", "9999-12-31"]) {
    assert.equal((await s.listMyItineraryItems(tripId, value)).items.length, 0);
    assert.ok(s.calls.some(([op, col, val]) => op === "eq" && col === "date" && val === value));
  }
});
test("DB/client failures and malformed responses do not return empty or leak details", async () => {
  for (const options of [{ dbError: { message: "private SQL details" } }, { dbThrows: true }, { clientThrows: true }]) {
    for (const read of reads(setup(options))) await assert.rejects(read(), error => {
      assert.equal(error.code, "READ_FAILED");
      assert.equal(error.message.includes("private"), false);
      return true;
    });
  }
  for (const options of [{ count: null }, { rows: null }, { rows: [], count: 1 }]) {
    await assert.rejects(setup(options).listMyItineraryItems(tripId, date), { code: "READ_FAILED" });
  }
});
