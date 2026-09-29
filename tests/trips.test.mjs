import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import ts from "typescript";

const source = readFileSync(new URL("../src/lib/trips/queries.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
});
const id = "30000000-0000-0000-0000-000000000001";
const nextId = "30000000-0000-0000-0000-000000000002";
const summary = { id, name: "Kyoto", start_date: "2026-10-01", end_date: "2026-10-02", thumbnail_path: null };

function setup({ user = { id: "user" }, authError = null, authThrows = false,
  rows = [summary], count = rows.length, detail = { ...summary, visibility: "private" },
  dbError = null, dbThrows = false, clientThrows = false } = {}) {
  const calls = [];
  let currentRows = rows;
  let currentDetail = detail;
  const query = {
    order(column, options) { calls.push(["order", column, options]); return query; },
    limit(value) { calls.push(["limit", value]); return query; },
    gt(column, value) { calls.push(["gt", column, value]); return query; },
    eq(column, value) { calls.push(["eq", column, value]); return query; },
    async maybeSingle() {
      if (dbThrows) throw new Error("private infrastructure details");
      return { data: currentDetail, error: dbError };
    },
    then(resolve, reject) {
      return (dbThrows
        ? Promise.reject(new Error("private infrastructure details"))
        : Promise.resolve({ data: currentRows, count, error: dbError })).then(resolve, reject);
    },
  };
  const imports = {
    "server-only": {},
    "@supabase/supabase-js": { isAuthSessionMissingError: (error) => error?.name === "AuthSessionMissingError" },
    "@/lib/supabase/auth": { getCurrentUser: async () => {
      calls.push(["authenticate"]);
      if (authThrows) throw new Error("private auth details");
      return { data: { user }, error: authError };
    } },
    "@/lib/supabase/server": { createClient: async () => {
      calls.push(["client"]);
      if (clientThrows) throw new Error("private client details");
      return { rpc(name, args, options) {
        calls.push(["rpc", name, args, options]);
        return { select(columns) { calls.push(["rpcSelect", columns]); return query; } };
      }, from(table) {
        calls.push(["from", table]);
        return { select(columns, options) {
          calls.push(["select", columns, options]);
          return query;
        } };
      } };
    } },
  };
  const compiledModule = { exports: {} };
  runInNewContext(outputText, {
    module: compiledModule, exports: compiledModule.exports,
    require(name) {
      if (!(name in imports)) throw new Error("Unexpected import: " + name);
      return imports[name];
    },
  });
  return { ...compiledModule.exports, calls, removeMembership() { currentRows = []; currentDetail = null; } };
}

test("unauthenticated callers never reach a database query", async () => {
  for (const authError of [null, { name: "AuthSessionMissingError" }, { status: 401 }, { status: 403 }]) {
    const service = setup({ user: null, authError });
    for (const read of [() => service.listMyTrips(), () => service.getMyTrip(id), () => service.listMyTripMembers(id)]) {
      await assert.rejects(read(), { code: "UNAUTHENTICATED" });
    }
    assert.equal(service.calls.some(([operation]) => operation === "client"), false);
  }
});

test("auth outages are not reported as signed-out or empty results", async () => {
  for (const options of [{ authError: { status: 503 } }, { authThrows: true }]) {
    const service = setup(options);
    await assert.rejects(service.listMyTrips(), { code: "AUTH_UNAVAILABLE" });
    await assert.rejects(service.getMyTrip(id), { code: "AUTH_UNAVAILABLE" });
  }
});

test("list and detail explicitly project their agreed fields using the user client", async () => {
  const service = setup();
  const page = await service.listMyTrips();
  const trip = await service.getMyTrip(id);
  assert.deepEqual(Object.keys(page.trips[0]), ["id", "name", "start_date", "end_date", "thumbnail_path"]);
  assert.equal(page.nextCursor, null);
  assert.equal(trip.visibility, "private");
  const selects = service.calls.filter(([op]) => op === "select");
  assert.equal(selects[0][1], "id,name,start_date,end_date,thumbnail_path");
  assert.equal(selects[0][2].count, "exact");
  assert.equal(selects[1][1], "id,name,start_date,end_date,thumbnail_path,visibility");
  assert.equal(service.calls.some(([op, column]) => op === "eq" && column === "created_by"), false);
  assert.equal(service.calls.filter(([op]) => op === "authenticate").length, 2);
});

test("empty membership list succeeds; denied and missing details share NOT_FOUND", async () => {
  // These are PostgREST's RLS-filtered responses. Actual policy is tested in SQL.
  const service = setup({ rows: [], detail: null });
  assert.equal((await service.listMyTrips()).trips.length, 0);
  await assert.rejects(service.getMyTrip(id), { code: "NOT_FOUND" });
  await assert.rejects(service.getMyTrip(nextId), { code: "NOT_FOUND" });
});

test("every call rechecks auth and reads RLS results after membership removal", async () => {
  const service = setup({ count: 0 });
  assert.equal((await service.getMyTrip(id)).id, id);
  service.removeMembership();
  await assert.rejects(service.getMyTrip(id), { code: "NOT_FOUND" });
  assert.equal((await service.listMyTrips()).trips.length, 0);
  assert.equal(service.calls.filter(([op]) => op === "authenticate").length, 3);
});

test("cursor pagination continues even when the API cap is smaller than pageSize", async () => {
  const service = setup({ count: 5 });
  const cursor = "30000000-0000-0000-0000-000000000000";
  const result = await service.listMyTrips({ pageSize: 100, cursor });
  assert.equal(result.nextCursor, id);
  assert.equal(service.calls.find(([op]) => op === "limit")[1], 100);
  assert.equal(service.calls.find(([op]) => op === "gt")[2], cursor);
  assert.equal(service.calls.find(([op]) => op === "order")[1], "id");
});

test("invalid IDs, cursor and sizes fail before SELECT", async () => {
  const service = setup();
  for (const value of ["", "../private", "not-a-uuid", id + "'"]) {
    await assert.rejects(service.getMyTrip(value), { code: "INVALID_INPUT" });
    await assert.rejects(service.listMyTrips({ cursor: value }), { code: "INVALID_INPUT" });
  }
  for (const pageSize of [0, -1, 101, 1.5, NaN, Infinity]) {
    await assert.rejects(service.listMyTrips({ pageSize }), { code: "INVALID_INPUT" });
  }
  assert.equal(service.calls.some(([op]) => op === "from"), false);
});

test("query failures preserve a safe error contract instead of returning empty data", async () => {
  for (const options of [{ dbError: { message: "private SQL details" } }, { dbThrows: true }]) {
    const service = setup(options);
    for (const operation of [() => service.listMyTrips(), () => service.getMyTrip(id), () => service.listMyTripMembers(id)]) {
      await assert.rejects(operation(), (error) => {
        assert.equal(error.code, "READ_FAILED");
        assert.equal(error.message.includes("private"), false);
        return true;
      });
    }
  }
  await assert.rejects(setup({ count: null }).listMyTrips(), { code: "READ_FAILED" });
});
test("members use the authorized RPC and expose only names and nullable paths", async () => {
  const rows = [
    { display_name: "Same", avatar_path: null, user_id: "never expose" },
    { display_name: "Same", avatar_path: "user/avatar.jpg" },
  ];
  const s = setup({ rows });
  const members = await s.listMyTripMembers(id);
  assert.equal(members.length, 2);
  assert.equal(members[0].avatar_path, null);
  assert.equal(members[1].avatar_path, "user/avatar.jpg");
  assert.deepEqual(Object.keys(members[0]), ["display_name", "avatar_path"]);
  assert.deepEqual(Array.from(members, m => m.display_name), ["Same", "Same"]);
  const rpc = s.calls.find(([op]) => op === "rpc");
  assert.equal(rpc[1], "get_trip_members");
  assert.equal(rpc[2].p_trip_id, id);
  assert.equal(rpc[3].count, "exact");
  assert.equal(s.calls.find(([op]) => op === "rpcSelect")[1], "display_name,avatar_path");
  assert.equal(s.calls.some(([op]) => op === "from"), false);
});
test("members reject invalid input and auth outages without invoking the RPC", async () => {
  const s = setup();
  for (const value of ["", "invalid", id + ",x"]) {
    await assert.rejects(s.listMyTripMembers(value), { code: "INVALID_INPUT" });
  }
  assert.equal(s.calls.some(([op]) => op === "rpc"), false);
  for (const options of [{ authError: { status: 503 } }, { authThrows: true }]) {
    await assert.rejects(setup(options).listMyTripMembers(id), { code: "AUTH_UNAVAILABLE" });
  }
});
test("RPC membership denial is NOT_FOUND and infrastructure failures stay READ_FAILED", async () => {
  await assert.rejects(setup({ dbError: { code: "42501", message: "private details" } }).listMyTripMembers(id), { code: "NOT_FOUND" });
  for (const options of [{ dbThrows: true }, { clientThrows: true }, { dbError: { code: "XX000" } },
    { rows: null, count: 0 }, { rows: [], count: null }, { rows: [], count: 1 }]) {
    await assert.rejects(setup(options).listMyTripMembers(id), { code: "READ_FAILED" });
  }
});
test("member list preserves authorized empty results but rejects API truncation", async () => {
  assert.equal((await setup({ rows: [] }).listMyTripMembers(id)).length, 0);
  await assert.rejects(setup({ rows: [{ display_name: "A", avatar_path: null }], count: 2 }).listMyTripMembers(id), { code: "READ_FAILED" });
});
test("member reads are authenticated and queried again on every invocation", async () => {
  const s = setup({ rows: [], count: 0 });
  await s.listMyTripMembers(id);
  await s.listMyTripMembers(id);
  assert.equal(s.calls.filter(([op]) => op === "authenticate").length, 2);
  assert.equal(s.calls.filter(([op]) => op === "rpc").length, 2);
});
