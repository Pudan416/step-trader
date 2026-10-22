import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { once } from "node:events";
import { after, before, test } from "node:test";

let server;
let baseURL;
let output = "";

before(async () => {
  const socket = createServer();
  socket.listen(0, "127.0.0.1");
  await once(socket, "listening");
  const port = socket.address().port;
  await new Promise((resolve) => socket.close(resolve));
  baseURL = `http://127.0.0.1:${port}`;
  server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "start", "--hostname", "127.0.0.1", "--port", String(port)], {
    env: {
      ...process.env,
      ADMIN_PASSWORD: "local-smoke-test-only",
      // Never use a developer's live backend, even if present in the shell.
      SUPABASE_URL: "http://127.0.0.1:1",
      SUPABASE_SERVICE_ROLE_KEY: "local-smoke-test-only",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stdout.on("data", (data) => { output += data; });
  server.stderr.on("data", (data) => { output += data; });
  for (let attempt = 0; attempt < 100; attempt++) {
    assert.equal(server.exitCode, null, output);
    try {
      if ((await fetch(`${baseURL}/api/health`)).ok) return;
    } catch { /* Wait for the local listener. */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.fail(`Production server did not become ready: ${output}`);
}, { timeout: 15000 });

after(async () => {
  if (server && server.exitCode === null) {
    const exited = once(server, "exit");
    server.kill("SIGTERM");
    await exited;
  }
});

test("production login and health routes remain reachable", async () => {
  assert.equal((await fetch(`${baseURL}/login`)).status, 200);
  assert.equal((await fetch(`${baseURL}/api/health`)).status, 200);
});

for (const method of ["GET", "POST"]) {
  for (const path of ["/dashboard", "/users", "/users/smoke-user"]) {
    test(`${method} ${path} requires a valid admin session`, async () => {
      for (const cookie of ["", "admin_session_v1=invalid.signature"]) {
        const response = await fetch(`${baseURL}${path}`, {
          method, redirect: "manual", headers: { cookie },
        });
        assert.equal(response.status, 307);
        const location = new URL(response.headers.get("location"), baseURL);
        assert.equal(location.pathname, "/login");
        assert.equal(location.searchParams.get("next"), path);
      }
    });
  }
}
