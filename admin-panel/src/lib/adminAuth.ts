import { cookies } from "next/headers";
import { getAdminPassword } from "./env";
import { supabaseAdmin } from "./supabaseAdmin";

const COOKIE_NAME = "admin_session_v1";
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 7; // 7 days

async function hmacSign(payload: string, secret: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(payload));
  return btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function hmacVerify(
  payload: string,
  signature: string,
  secret: string
): Promise<boolean> {
  const expected = await hmacSign(payload, secret);
  if (expected.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return mismatch === 0;
}

async function createSessionToken(secret: string): Promise<string> {
  const exp = Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS;
  const payload = JSON.stringify({ exp });
  const payloadB64 = btoa(payload)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  const sig = await hmacSign(payload, secret);
  return `${payloadB64}.${sig}`;
}

export async function verifySessionToken(token: string): Promise<boolean> {
  const dotIdx = token.indexOf(".");
  if (dotIdx < 1) return false;
  const payloadB64 = token.slice(0, dotIdx);
  const sig = token.slice(dotIdx + 1);

  try {
    const secret = getAdminPassword();
    const payload = atob(
      payloadB64.replace(/-/g, "+").replace(/_/g, "/")
    );
    if (!(await hmacVerify(payload, sig, secret))) return false;

    const { exp } = JSON.parse(payload);
    if (typeof exp !== "number" || exp < Math.floor(Date.now() / 1000)) {
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

export { COOKIE_NAME };

// Persistent rate limiting via Supabase RPC (survives cold starts / per-invocation isolation)
async function checkRateLimit(ip: string): Promise<boolean> {
  try {
    const sb = supabaseAdmin();
    const { data, error } = await sb.rpc("check_admin_rate_limit", {
      p_ip: ip,
      p_max_attempts: 5,
      p_window_seconds: 900, // 15 minutes
    });
    if (error) {
      console.error("Rate limit RPC error:", error.message);
      return true; // fail open if DB is unreachable — don't lock admins out
    }
    return data === true;
  } catch (e) {
    console.error("Rate limit check failed:", e);
    return true; // fail open
  }
}

export async function loginWithPassword(password: string, clientIp?: string) {
  const ip = clientIp ?? "unknown";
  if (!(await checkRateLimit(ip))) {
    return { ok: false as const, rateLimited: true };
  }

  const expected = getAdminPassword();
  if (password.length !== expected.length) return { ok: false as const };
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= password.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  if (mismatch !== 0) return { ok: false as const };

  const token = await createSessionToken(expected);
  const c = await cookies();
  const isProd = process.env.NODE_ENV === "production";
  c.set(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: isProd,
    path: "/",
    maxAge: TOKEN_TTL_SECONDS,
  });
  return { ok: true as const };
}

export async function logout() {
  const c = await cookies();
  const isProd = process.env.NODE_ENV === "production";
  c.set(COOKIE_NAME, "", {
    httpOnly: true,
    sameSite: "lax",
    secure: isProd,
    path: "/",
    maxAge: 0,
  });
}
