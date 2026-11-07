// Sends queued push notifications (notification_queue, channel 'push') with Firebase Cloud
// Messaging HTTP v1. Called every 5 minutes by pg_cron (see supabase/README.md), never by the app.
//
// Messages carry no health data: the text is a fixed template and `data` holds only the template
// key. A mother's lock screen says only "You have a reminder" (shared phones).
//
// Secrets:
//   FCM_SERVICE_ACCOUNT  the Firebase service-account JSON (Project settings → Service accounts)
//   CRON_SECRET          a long random string; the cron job sends it as the bearer token
import { createClient } from "npm:@supabase/supabase-js@2";

type Row = { id: number; profile_id: string; template_key: string };

const TEXT: Record<string, { en: [string, string]; sw: [string, string] }> = {
  visit_tomorrow: {
    en: ["Safari ya Mama", "You have a reminder"],
    sw: ["Safari ya Mama", "Una kikumbusho"],
  },
  red_alert_unacked: {
    en: ["Safari ya Mama · Staff", "A red alert at your facility is waiting for action"],
    sw: ["Safari ya Mama · Wahudumu", "Tahadhari nyekundu kituoni kwako inasubiri hatua"],
  },
};

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const enc = new TextEncoder();

async function googleAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(
    enc.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${header}.${claims}`)));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${header}.${claims}.${b64url(sig)}` }),
  });
  if (!res.ok) throw new Error(`google token ${res.status}`);
  return (await res.json()).access_token;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("Authorization") !== `Bearer ${secret}`) return new Response("forbidden", { status: 403 });
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saRaw) return new Response(JSON.stringify({ skipped: "FCM_SERVICE_ACCOUNT not set" }), { status: 503 });
  const sa = JSON.parse(saRaw);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: rows, error } = await db
    .from("notification_queue")
    .select("id, profile_id, template_key")
    .eq("status", "queued")
    .eq("channel", "push")
    .lte("send_after", new Date().toISOString())
    .limit(200);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  if (!rows?.length) return new Response(JSON.stringify({ sent: 0 }));

  const token = await googleAccessToken(sa);
  let sent = 0, failed = 0, noDevice = 0;
  for (const r of rows as Row[]) {
    const t = TEXT[r.template_key];
    const [{ data: devices }, { data: prof }] = await Promise.all([
      db.from("push_subscriptions").select("id, endpoint").eq("profile_id", r.profile_id).eq("kind", "fcm"),
      db.from("profiles").select("lang").eq("id", r.profile_id).maybeSingle(),
    ]);
    if (!t || !devices?.length) {
      noDevice++;
      await db.from("notification_queue").update({ status: t ? "no_device" : "unknown_template", sent_at: new Date().toISOString() }).eq("id", r.id);
      continue;
    }
    const [title, body] = prof?.lang === "sw" ? t.sw : t.en;
    let ok = false;
    for (const d of devices) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message: { token: d.endpoint, notification: { title, body }, data: { template: r.template_key } } }),
      });
      if (res.ok) ok = true;
      else if (res.status === 404 || res.status === 400) await db.from("push_subscriptions").delete().eq("id", d.id); // uninstalled or bad token
    }
    ok ? sent++ : failed++;
    await db.from("notification_queue").update({ status: ok ? "sent" : "failed", sent_at: new Date().toISOString() }).eq("id", r.id);
  }
  return new Response(JSON.stringify({ sent, failed, noDevice }));
});
