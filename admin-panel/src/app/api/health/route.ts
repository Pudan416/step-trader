import { NextResponse } from "next/server";
import { countAuthUsers, countShields, sumEnergyDelta } from "@/lib/queries";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const env = {
      SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
      SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
      ADMIN_PASSWORD: Boolean(process.env.ADMIN_PASSWORD),
      NODE_ENV: process.env.NODE_ENV ?? "unknown",
    };

    const [users, shields, energy] = await Promise.all([
      countAuthUsers(),
      countShields(),
      sumEnergyDelta(),
    ]);

    return NextResponse.json({
      ok: true,
      env,
      stats: { users, shields, energy },
    });
  } catch (e: any) {
    return NextResponse.json(
      {
        ok: false,
        error: String(e?.message ?? e),
        name: e?.name,
        details: e,
        env: {
          SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
          SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
          ADMIN_PASSWORD: Boolean(process.env.ADMIN_PASSWORD),
          NODE_ENV: process.env.NODE_ENV ?? "unknown",
        },
      },
      { status: 500 }
    );
  }
}

