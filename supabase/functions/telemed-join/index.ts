// Video appointments: hands out the call link, only to the mother who booked and the staff of
// that facility, from 15 minutes before the start until 30 minutes after the planned end.
// Deploy with verify_jwt on.
//
//   request  { booking_id }
//   response { url, provider: "daily"|"jitsi", opens_at, ends_at }
//            { error: "too_early", opens_at } (425) · { error: "ended" } (410) · 403 / 404
//
// Provider (secrets, set with `supabase secrets set`, never in git or chat):
//   DAILY_API_KEY + DAILY_DOMAIN   recommended: private Daily.co rooms that expire, one meeting token
//                                  per person (staff join as owner). Works in the phone's browser.
//   neither                        Jitsi Meet at JITSI_BASE (default https://meet.jit.si) with a
//                                  random 64-character room name nobody can guess. Fine for testing;
//                                  for real consultations use Daily or your own Jitsi server.
// Nothing about the consultation is stored by this function.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const EARLY_MS = 15 * 60_000;
const LATE_MS = 30 * 60_000;

async function daily(room: string, expSec: number, name: string, owner: boolean): Promise<string | null> {
  const key = Deno.env.get("DAILY_API_KEY"), domain = Deno.env.get("DAILY_DOMAIN");
  if (!key || !domain) return null;
  const h = { Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  const roomName = `sym-${room.slice(0, 40)}`;
  const made = await fetch("https://api.daily.co/v1/rooms", {
    method: "POST",
    headers: h,
    body: JSON.stringify({
      name: roomName,
      privacy: "private",
      properties: { exp: expSec, eject_at_room_exp: true, max_participants: 4, enable_prejoin_ui: true, enable_chat: true },
    }),
  });
  if (!made.ok && made.status !== 400) return null; // 400: the room already exists
  const t = await fetch("https://api.daily.co/v1/meeting-tokens", {
    method: "POST",
    headers: h,
    body: JSON.stringify({ properties: { room_name: roomName, exp: expSec, is_owner: owner, user_name: name } }),
  });
  if (!t.ok) return null;
  const { token } = await t.json();
  return `https://${domain}.daily.co/${roomName}?t=${token}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer /i, "");
  const { data: who } = await db.auth.getUser(token);
  const uid = who?.user?.id;
  if (!uid) return json({ error: "sign in first" }, 401);

  let bookingId = "";
  try {
    bookingId = String((await req.json()).booking_id ?? "");
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const { data: b } = await db.from("bookings")
    .select("id, mother_id, facility_id, starts_at, minutes, mode, status, room").eq("id", bookingId).maybeSingle();
  if (!b || b.mode !== "video") return json({ error: "not found" }, 404);

  const { data: me } = await db.from("profiles").select("role, display_name").eq("id", uid).maybeSingle();
  let staff = false;
  if (b.mother_id !== uid) {
    const { data: a } = await db.from("staff_assignments").select("staff_id")
      .eq("staff_id", uid).eq("facility_id", b.facility_id).eq("active", true).maybeSingle();
    // super admins and Admins can work at any facility, after their two-step code (aal2 in the token)
    let aal = "";
    try { aal = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).aal ?? ""; } catch { /* not a JWT */ }
    staff = (!!a && ["health_worker", "facility_admin"].includes(me?.role ?? ""))
      || (["super_admin", "programme_admin"].includes(me?.role ?? "") && aal === "aal2");
    if (!staff) return json({ error: "not your appointment" }, 403);
  }
  if (b.status !== "booked") return json({ error: "ended" }, 410);

  const start = new Date(b.starts_at).getTime();
  const opens = start - EARLY_MS, ends = start + b.minutes * 60_000 + LATE_MS, now = Date.now();
  if (now < opens) return json({ error: "too_early", opens_at: new Date(opens).toISOString() }, 425);
  if (now > ends) return json({ error: "ended" }, 410);

  const name = staff ? (me?.display_name || "Health worker") : "Mama";
  const dailyUrl = await daily(b.room, Math.floor(ends / 1000), name, staff);
  const base = (Deno.env.get("JITSI_BASE") || "https://meet.jit.si").replace(/\/$/, "");
  const url = dailyUrl ?? `${base}/SafariYaMama-${b.room}#userInfo.displayName=%22${encodeURIComponent(name)}%22`;
  // first join of each side, for the "both joined" KPI (times only, nothing about the call)
  const joined = staff ? "staff_joined_at" : "mother_joined_at";
  await db.from("bookings").update({ [joined]: new Date().toISOString() }).eq("id", b.id).is(joined, null);
  return json({
    url,
    provider: dailyUrl ? "daily" : "jitsi",
    opens_at: new Date(opens).toISOString(),
    ends_at: new Date(ends).toISOString(),
  });
});
