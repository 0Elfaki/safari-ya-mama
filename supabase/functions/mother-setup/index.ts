// Staff-assisted sign-in for mothers (sign-in is required in the app).
//
//   POST { action: "create", phone, name?, facility_id? }   caller: signed-in staff
//     → creates (or finds) the mother's account by phone and returns a one-time 8-digit
//       setup code, valid 24 hours: { code, expires_at }. Only a hash of the code is stored.
//   POST { action: "redeem", code }                          caller: the app, not signed in
//     → { token_hash, type: "magiclink" } that the app exchanges for her session with
//       supabase.auth.verifyOTP(type: magiclink, tokenHash). Single use.
//
// Deployed with verify_jwt off because "redeem" runs before sign-in; "create" checks the
// caller's session and role itself. Every create and redeem is written to audit_log.
// Secrets: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
import { createClient } from "npm:@supabase/supabase-js@2";

const STAFF = ["health_worker", "facility_admin", "programme_admin", "super_admin"];
const MAX_FAILS_PER_HOUR = 10;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function sha256(text: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

function newCode(): string {
  // 8 digits from a cryptographic random source (rejection sampling avoids bias)
  const buf = new Uint32Array(1);
  let n: number;
  do {
    crypto.getRandomValues(buf);
    n = buf[0];
  } while (n >= 4_200_000_000);
  return (n % 100_000_000).toString().padStart(8, "0");
}

// Tanzanian numbers: 07xx / 06xx → +2557xx / +2556xx; anything else must already be +E.164.
function e164(raw: string): string | null {
  let p = (raw ?? "").replace(/[^0-9+]/g, "");
  if (p.startsWith("0")) p = "+255" + p.slice(1);
  if (!p.startsWith("+")) p = "+" + p;
  return /^\+[1-9][0-9]{7,14}$/.test(p) ? p : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  let body: { action?: string; phone?: string; name?: string; facility_id?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }

  // ───────────── staff: set up a mother's account and get her a setup code
  if (body.action === "create") {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who } = await db.auth.getUser(token);
    if (!who?.user) return json({ error: "sign in first" }, 401);
    const { data: staff } = await db.from("profiles").select("role").eq("id", who.user.id).maybeSingle();
    if (!staff || !STAFF.includes(staff.role)) return json({ error: "only clinic staff can set up a mother's account" }, 403);
    if (["programme_admin", "super_admin"].includes(staff.role)) {
      // admins must have finished their two-step sign-in (aal2), as everywhere else
      let aal = "";
      try { aal = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).aal ?? ""; } catch { /* not a JWT */ }
      if (aal !== "aal2") return json({ error: "confirm your sign-in with your authenticator code first" }, 403);
    }

    const phone = e164(body.phone ?? "");
    if (!phone) return json({ error: "enter a valid phone number" }, 400);
    const facility = body.facility_id ?? null;
    if (facility && ["health_worker", "facility_admin"].includes(staff.role)) {
      const { data: a } = await db.from("staff_assignments").select("facility_id").eq("staff_id", who.user.id).eq("facility_id", facility).eq("active", true).maybeSingle();
      if (!a) return json({ error: "you are not assigned to that facility" }, 403);
    }

    // find or create her account; a hidden email lets us issue a one-time sign-in link
    let motherId: string | null = (await db.rpc("find_user_id_by_phone", { p_phone: phone })).data ?? null;
    if (!motherId) {
      const { data, error } = await db.auth.admin.createUser({ phone, phone_confirm: true, email: `m-${crypto.randomUUID()}@mothers.safariyamama.invalid`, email_confirm: true });
      if (error || !data.user) return json({ error: "could not create the account" }, 500);
      motherId = data.user.id;
    } else {
      const { data: u } = await db.auth.admin.getUserById(motherId);
      if (!u?.user?.email) {
        await db.auth.admin.updateUserById(motherId, { email: `m-${crypto.randomUUID()}@mothers.safariyamama.invalid`, email_confirm: true });
      }
    }
    const { data: prof } = await db.from("profiles").select("role").eq("id", motherId).maybeSingle();
    if (prof && prof.role !== "mother") return json({ error: "this phone number belongs to a staff or helper account" }, 409);
    const patch: Record<string, unknown> = {};
    if (body.name?.trim()) patch.display_name = body.name.trim().slice(0, 60);
    if (facility) patch.home_facility = facility;
    if (Object.keys(patch).length) await db.from("profiles").update(patch).eq("id", motherId);

    const code = newCode();
    const expires = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
    // a new code replaces any unused older one for this mother
    await db.from("mother_setup_codes").update({ used_at: new Date().toISOString() }).eq("mother_id", motherId).is("used_at", null);
    const { error: insErr } = await db.from("mother_setup_codes").insert({ code_hash: await sha256(code), mother_id: motherId, facility_id: facility, created_by: who.user.id, expires_at: expires });
    if (insErr) return json({ error: "could not make a code, try again" }, 500);
    await db.from("audit_log").insert({ actor_id: who.user.id, action: "mother_setup_code", mother_id: motherId, details: { facility_id: facility } });
    return json({ code, expires_at: expires });
  }

  // ───────────── app: redeem a setup code (before sign-in)
  if (body.action === "redeem") {
    const client = (req.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();
    const since = new Date(Date.now() - 3600 * 1000).toISOString();
    const { count } = await db.from("setup_code_attempts").select("id", { count: "exact", head: true }).eq("client", client).gte("at", since);
    if ((count ?? 0) >= MAX_FAILS_PER_HOUR) return json({ error: "too many tries, wait an hour" }, 429);

    const code = (body.code ?? "").replace(/\D/g, "");
    const fail = async () => {
      await db.from("setup_code_attempts").insert({ client });
      return json({ error: "this code is wrong, used or expired" }, 400);
    };
    if (code.length !== 8) return await fail();
    const { data: row } = await db.from("mother_setup_codes").select("code_hash, mother_id, expires_at, used_at").eq("code_hash", await sha256(code)).maybeSingle();
    if (!row || row.used_at || new Date(row.expires_at) <= new Date()) return await fail();

    // single use: claim it before issuing the link
    const { data: claimed } = await db.from("mother_setup_codes").update({ used_at: new Date().toISOString() }).eq("code_hash", row.code_hash).is("used_at", null).select("code_hash");
    if (!claimed?.length) return await fail();

    const { data: u } = await db.auth.admin.getUserById(row.mother_id);
    if (!u?.user?.email) return json({ error: "account not ready, ask the clinic for a new code" }, 409);
    const { data: link, error } = await db.auth.admin.generateLink({ type: "magiclink", email: u.user.email });
    if (error || !link?.properties?.hashed_token) return json({ error: "could not sign in, ask for a new code" }, 500);
    await db.from("audit_log").insert({ actor_id: row.mother_id, action: "mother_setup_redeemed", mother_id: row.mother_id, details: {} });
    return json({ token_hash: link.properties.hashed_token, type: "magiclink" });
  }

  return json({ error: "unknown action" }, 400);
});
