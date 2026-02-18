import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const hasSupabase = Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
    return NextResponse.json({
      ok: hasSupabase,
      status: hasSupabase ? "healthy" : "misconfigured",
    });
  } catch {
    return NextResponse.json({ ok: false, status: "error" }, { status: 500 });
  }
}
