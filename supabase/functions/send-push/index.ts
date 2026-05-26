import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// --- Required env vars ---
// Read once at startup. Missing values throw immediately rather than failing
// silently per request (defends against §6.3: a missing APNS_BUNDLE_ID used to
// silently fall back to the production identifier and could mass-delete tokens
// via §6.4's cleanup heuristic).
function requireEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const APNS_BUNDLE_ID = requireEnv("APNS_BUNDLE_ID");
const IS_PRODUCTION = Deno.env.get("APNS_ENVIRONMENT") !== "sandbox";

// --- Constant-time string compare ---
// Prevents timing oracles when checking the caller's bearer against the service
// role key. Both inputs are ASCII (Supabase keys are JWT-ish base64), so byte
// length difference is informative on its own — we still iterate the longer
// string to keep the timing bound by max(len(a), len(b)).
function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  const len = Math.max(aBytes.length, bBytes.length);
  let mismatch = aBytes.length ^ bBytes.length;
  for (let i = 0; i < len; i++) {
    mismatch |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0);
  }
  return mismatch === 0;
}

function extractBearer(header: string | null): string | null {
  if (!header) return null;
  const m = header.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}

// --- APNs JWT generation (unchanged) ---
async function generateAPNsJWT(): Promise<string> {
  const teamId = requireEnv("APNS_TEAM_ID");
  const keyId = requireEnv("APNS_KEY_ID");
  const privateKeyPem = requireEnv("APNS_PRIVATE_KEY");

  const header = { alg: "ES256", kid: keyId };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: teamId, iat: now };

  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

  const signingInput = `${enc(header)}.${enc(payload)}`;

  // Import the P8 private key
  const pemBody = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );

  // WebCrypto ECDSA already returns raw IEEE P1363 (r||s) format.
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  return `${signingInput}.${sigB64}`;
}

async function sendAPNs(
  token: string,
  title: string,
  body: string,
  jwt: string,
  bundleId: string,
  isProduction: boolean
): Promise<{ token: string; success: boolean; status: number; reason?: string }> {
  const host = isProduction
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const apnsPayload = {
    aps: {
      alert: { title, body },
      sound: "default",
    },
  };

  try {
    const res = await fetch(`https://${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(apnsPayload),
    });

    const status = res.status;
    if (status === 200) {
      return { token, success: true, status };
    }

    const errBody = await res.json().catch(() => ({}));
    return { token, success: false, status, reason: errBody.reason };
  } catch (_e) {
    // Don't surface raw exception strings — they can include URL fragments
    // containing token bytes.
    return { token, success: false, status: 0, reason: "network_error" };
  }
}

// --- Request handler ---
//
// Security contract:
// - Caller MUST present `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`.
//   This endpoint can broadcast to every registered iOS device, so it is
//   restricted to server-side / admin invocations only. No iOS client should
//   ever ship the service-role key. (§6.1)
// - CORS is closed by default. The function is intended to be called from
//   server-to-server contexts (cron, admin tooling), never from a browser.
//   If a browser caller is added later, narrow `Access-Control-Allow-Origin`
//   to a specific allow-list — do not return "*".
serve(async (req) => {
  // No browser callers expected. Reject preflights instead of advertising
  // "*". A future legitimate caller can be added to an allow-list here.
  if (req.method === "OPTIONS") {
    return new Response("CORS disabled for this endpoint", { status: 405 });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Authenticate: require service role bearer, constant-time compare.
  const bearer = extractBearer(req.headers.get("Authorization"));
  if (!bearer || !timingSafeEqual(bearer, SERVICE_ROLE_KEY)) {
    // Same 401 shape for missing / invalid — don't leak which case failed.
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let parsed: { title?: unknown; body?: unknown };
  try {
    parsed = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const title = typeof parsed.title === "string" ? parsed.title : "";
  const pushBody = typeof parsed.body === "string" ? parsed.body : "";
  if (!title || !pushBody) {
    return new Response(
      JSON.stringify({ error: "title and body are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Use service role to read all tokens
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("platform", "ios");

  if (error) {
    return new Response(JSON.stringify({ error: "Database error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!tokens || tokens.length === 0) {
    return new Response(JSON.stringify({ sent: 0, message: "No tokens" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const jwt = await generateAPNsJWT();

  // Send to all tokens in parallel (batches of 50)
  const results: Awaited<ReturnType<typeof sendAPNs>>[] = [];
  const batchSize = 50;
  for (let i = 0; i < tokens.length; i += batchSize) {
    const batch = tokens.slice(i, i + batchSize);
    const batchResults = await Promise.all(
      batch.map((t) =>
        sendAPNs(t.token, title, pushBody, jwt, APNS_BUNDLE_ID, IS_PRODUCTION)
      )
    );
    results.push(...batchResults);
  }

  // Clean up invalid tokens.
  // §6.4: only delete on `BadDeviceToken` (token never valid) or `Unregistered`
  // (app uninstalled). DO NOT delete on `DeviceTokenNotForTopic` — that signals
  // a server config error (wrong APNS_BUNDLE_ID for this token's app) and
  // deleting would wipe live tokens on a misconfigured deploy.
  const invalidTokens = results
    .filter(
      (r) =>
        !r.success &&
        (r.reason === "BadDeviceToken" || r.reason === "Unregistered")
    )
    .map((r) => r.token);

  // Surface DeviceTokenNotForTopic separately so it shows up in function logs
  // as a deploy-config alert rather than silently triggering cleanup.
  const topicMismatches = results.filter(
    (r) => !r.success && r.reason === "DeviceTokenNotForTopic"
  ).length;
  if (topicMismatches > 0) {
    console.warn(
      `[send-push] ${topicMismatches} tokens returned DeviceTokenNotForTopic — ` +
        `check APNS_BUNDLE_ID="${APNS_BUNDLE_ID}" and APNS_ENVIRONMENT.`
    );
  }

  if (invalidTokens.length > 0) {
    await supabase
      .from("device_tokens")
      .delete()
      .in("token", invalidTokens);
  }

  const sent = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;

  return new Response(
    JSON.stringify({
      sent,
      failed,
      cleaned: invalidTokens.length,
      topic_mismatches: topicMismatches,
      total: tokens.length,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
