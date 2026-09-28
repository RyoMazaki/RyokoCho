import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import ts from "typescript";
import { NextRequest, NextResponse } from "next/server.js";

// Exercise adapters without contacting Auth or creating users in the real DB.
function loadModule(path, imports = {}, env = {}) {
  const source = readFileSync(new URL(path, import.meta.url), "utf8");
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  });
  const compiledModule = { exports: {} };
  runInNewContext(outputText, {
    exports: compiledModule.exports,
    module: compiledModule,
    process: { env },
    require(name) {
      if (name === "server-only") return {};
      if (!(name in imports)) throw new Error(`Unexpected import: ${name}`);
      return imports[name];
    },
  });
  return compiledModule.exports;
}

test("environment rejects missing and privileged keys without printing values", () => {
  const path = "../src/lib/supabase/env.ts";
  assert.throws(() => loadModule(path).getSupabaseEnv(), /Set NEXT_PUBLIC/);
  for (const key of ["sb_secret_sensitive", "eyJ.service-role.jwt"]) {
    const env = {
      NEXT_PUBLIC_SUPABASE_URL: "https://example.supabase.co",
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: key,
    };
    assert.throws(() => loadModule(path, {}, env).getSupabaseEnv(), (error) => {
      assert.match(error.message, /must be a Supabase publishable key/);
      assert.equal(error.message.includes(key), false);
      return true;
    });
  }
});

const envImport = {
  getSupabaseEnv: () => ({
    url: "https://example.supabase.co",
    publishableKey: "sb_publishable_test",
  }),
};

test("proxy forwards refreshed cookies to server and browser, preserving cache headers", async () => {
  const request = new NextRequest("https://example.test/");
  const { updateSession } = loadModule("../src/lib/supabase/proxy.ts", {
    "./env": envImport,
    "next/server": { NextResponse },
    "@supabase/ssr": {
      createServerClient(_url, _key, { cookies }) {
        return {
          auth: {
            async getClaims() {
              cookies.setAll(
                [{ name: "session", value: "refreshed", options: { path: "/", sameSite: "lax", secure: true } }],
                { "Cache-Control": "private, no-store", Pragma: "no-cache", Expires: "0" },
              );
              // The SDK may invoke setAll again with no additional headers.
              cookies.setAll([{ name: "old-chunk", value: "", options: { maxAge: 0, path: "/" } }], {});
              return { data: { claims: { sub: "test-user" } }, error: null };
            },
          },
        };
      },
    },
  });
  const response = await updateSession(request);
  assert.equal(request.cookies.get("session")?.value, "refreshed");
  assert.equal(response.cookies.get("session")?.value, "refreshed");
  assert.equal(response.cookies.get("session")?.secure, true);
  assert.equal(response.cookies.get("old-chunk")?.maxAge, 0);
  assert.match(response.headers.get("x-middleware-request-cookie"), /session=refreshed/);
  assert.equal(response.headers.get("Cache-Control"), "private, no-store");
  assert.equal(response.headers.get("Pragma"), "no-cache");
  assert.equal(response.headers.get("Expires"), "0");
});

test("proxy allows unauthenticated requests without granting identity or redirecting", async () => {
  const { updateSession } = loadModule("../src/lib/supabase/proxy.ts", {
    "./env": envImport,
    "next/server": { NextResponse },
    "@supabase/ssr": {
      createServerClient: () => ({
        auth: { getClaims: async () => ({ data: null, error: null }) },
      }),
    },
  });
  const response = await updateSession(new NextRequest("https://example.test/shared"));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("location"), null);
  assert.equal(response.cookies.getAll().length, 0);
});

test("server clients remain isolated per request and support writable and readonly cookies", async () => {
  const adapters = [];
  const stores = [
    { getAll: () => [{ name: "session", value: "alice" }], set: (...args) => writes.push(args) },
    { getAll: () => [{ name: "session", value: "bob" }], set: () => { throw new Error("Readonly Server Component"); } },
  ];
  const writes = [];
  const { createClient } = loadModule("../src/lib/supabase/server.ts", {
    "./env": envImport,
    "next/headers": { cookies: async () => stores.shift() },
    "@supabase/ssr": {
      createServerClient(_url, _key, { cookies }) {
        adapters.push(cookies);
        return { cookies };
      },
    },
  });
  const alice = await createClient();
  const bob = await createClient();
  assert.notEqual(alice, bob);
  assert.equal(adapters[0].getAll()[0].value, "alice");
  assert.equal(adapters[1].getAll()[0].value, "bob");
  adapters[0].setAll([{ name: "session", value: "new-alice", options: { path: "/" } }]);
  assert.equal(writes[0][1], "new-alice");
  assert.doesNotThrow(() => adapters[1].setAll([{ name: "session", value: "new-bob", options: {} }]));
});

test("current user comes from Auth verification and preserves failures", async () => {
  const failure = { data: { user: null }, error: { message: "Auth unavailable" } };
  const { getCurrentUser } = loadModule("../src/lib/supabase/auth.ts", {
    "./server": {
      createClient: async () => ({
        auth: {
          getUser: async () => failure,
          getSession: () => { throw new Error("Must not trust the cookie session"); },
        },
      }),
    },
  });
  assert.equal(await getCurrentUser(), failure);
});