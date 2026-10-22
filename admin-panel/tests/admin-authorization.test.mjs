import assert from "node:assert/strict";
import { createHmac, webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";
import ts from "typescript";

const secret = "authorization-test-secret";
function token(expiresAt, signingSecret = secret) {
  const payload = JSON.stringify({ exp: expiresAt });
  return `${Buffer.from(payload).toString("base64url")}.${createHmac("sha256", signingSecret).update(payload).digest("base64url")}`;
}

// Execute actual modules with request cookies and the database substituted.
// Middleware is deliberately absent: every data/action entry must guard itself.
function loadModule(path, dependencies) {
  const exports = {};
  const source = readFileSync(new URL(path, import.meta.url), "utf8");
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  vm.runInNewContext(compiled, {
    exports, crypto: webcrypto, btoa, atob, TextEncoder, process,
    require(name) {
      assert.ok(Object.hasOwn(dependencies, name), `Unexpected dependency: ${name}`);
      return dependencies[name];
    },
  }, { filename: path });
  return exports;
}

function fixture(cookie) {
  let databaseCalls = 0;
  const database = {
    supabaseAdmin() {
      databaseCalls++;
      throw new Error("TEST_DATABASE_REACHED");
    },
  };
  const auth = loadModule("../src/lib/adminAuth.ts", {
    "next/headers": { cookies: async () => ({ get: () => cookie ? { value: cookie } : undefined }) },
    "./env": { getAdminPassword: () => secret },
    "./supabaseAdmin": database,
  });
  const queries = loadModule("../src/lib/queries.ts", {
    "./adminAuth": auth,
    "./supabaseAdmin": database,
  });
  return { queries, databaseCalls: () => databaseCalls };
}

const operations = {
  listPublicUsers: [{}], getPublicUser: ["fixture-user"], getUserPrefs: ["fixture-user"],
  listShields: ["fixture-user"], countShields: [], countAuthUsers: [],
  banUser: ["fixture-user", "fixture reason"], unbanUser: ["fixture-user"],
};

for (const [name, args] of Object.entries(operations)) {
  test(`${name} rejects missing, forged, and expired sessions before database access`, async () => {
    const now = Math.floor(Date.now() / 1000);
    for (const cookie of [undefined, "malformed", token(now + 3600, "wrong-secret"), token(now - 60)]) {
      const f = fixture(cookie);
      await assert.rejects(f.queries[name](...args), /Unauthorized/);
      assert.equal(f.databaseCalls(), 0);
    }
  });
  test(`${name} permits a correctly signed unexpired admin session`, async () => {
    const f = fixture(token(Math.floor(Date.now() / 1000) + 3600));
    await assert.rejects(f.queries[name](...args), /TEST_DATABASE_REACHED/);
    assert.equal(f.databaseCalls(), 1);
  });
}
