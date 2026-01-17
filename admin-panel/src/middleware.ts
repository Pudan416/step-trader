import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

const COOKIE_NAME = "admin_session_v1";

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  if (pathname.startsWith("/login")) return NextResponse.next();
  if (pathname.startsWith("/_next")) return NextResponse.next();
  if (pathname.startsWith("/favicon")) return NextResponse.next();

  const authed = req.cookies.get(COOKIE_NAME)?.value === "1";
  if (!authed) {
    const url = req.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api/health).*)"],
};

