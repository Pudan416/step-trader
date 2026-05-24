import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// APNs JWT generation
async function generateAPNsJWT(): Promise<string> {
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const privateKeyPem = Deno.env.get("APNS_PRIVATE_KEY")!;

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

  // Convert DER signature to raw r||s format is not needed — WebCrypto ECDSA
  // already returns raw IEEE P1363 (r||s) format.
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
  } catch (e) {
    return { token, success: false, status: 0, reason: String(e) };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  // Authenticate caller — must be a valid Supabase user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { title, body: pushBody } = await req.json();
  if (!title || !pushBody) {
    return new Response(
      JSON.stringify({ error: "title and body are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Use service role to read all tokens
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("platform", "ios");

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
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

  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "personal-project.StepsTrader";
  const isProduction = Deno.env.get("APNS_ENVIRONMENT") !== "sandbox";
  const jwt = await generateAPNsJWT();

  // Send to all tokens in parallel (batches of 50)
  const results: Awaited<ReturnType<typeof sendAPNs>>[] = [];
  const batchSize = 50;
  for (let i = 0; i < tokens.length; i += batchSize) {
    const batch = tokens.slice(i, i + batchSize);
    const batchResults = await Promise.all(
      batch.map((t) =>
        sendAPNs(t.token, title, pushBody, jwt, bundleId, isProduction)
      )
    );
    results.push(...batchResults);
  }

  // Clean up invalid tokens
  const invalidTokens = results
    .filter(
      (r) =>
        !r.success &&
        (r.reason === "BadDeviceToken" ||
          r.reason === "Unregistered" ||
          r.reason === "DeviceTokenNotForTopic")
    )
    .map((r) => r.token);

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
      total: tokens.length,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
