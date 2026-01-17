import { cookies } from "next/headers";
import { getAdminPassword } from "./env";

const COOKIE_NAME = "admin_session_v1";

export async function loginWithPassword(password: string) {
  const expected = getAdminPassword();
  if (password !== expected) return { ok: false as const };
  const c = await cookies();
  const isProd = process.env.NODE_ENV === "production";
  c.set(COOKIE_NAME, "1", {
    httpOnly: true,
    sameSite: "lax",
    secure: isProd, // allow localhost over http
    path: "/",
    maxAge: 60 * 60 * 24 * 7, // 7 days
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

