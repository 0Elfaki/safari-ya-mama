// contact-submit: the website's contact form. Public (verify_jwt off).
//   POST { name, organisation?, email, topic?, message }  → { ok: true } | { error } 400/429
// Stores the message (submit_contact_from: at most 5 an hour from one sender, 300 a day), then
// emails the team a short alert WITHOUT the message itself: who, topic, and a link to the Inbox.
// Secrets (optional; without them the message is stored and shows in the Inbox, no email):
//   RESEND_API_KEY, CONTACT_NOTIFY_TO (comma-separated), CONTACT_NOTIFY_FROM (a verified sender),
//   DASHBOARD_URL (for the Inbox link).
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

async function sha256(t: string) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(t)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return json({ error: "bad request" }, 400); }
  const s = (k: string, max: number) => String(b[k] ?? "").trim().slice(0, max);
  const name = s("name", 120), org = s("organisation", 160), email = s("email", 200).toLowerCase(), topic = s("topic", 80), message = s("message", 2000);
  if (name.length < 2 || !EMAIL.test(email) || message.length < 20) return json({ error: "Please fill in your name, a valid email and a message of at least 20 characters." }, 400);

  const ip = (req.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();
  const sender = await sha256(`${ip}|sym-contact`);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { error } = await db.rpc("submit_contact_from", { p_name: name, p_organisation: org, p_email: email, p_topic: topic, p_message: message, p_sender: sender });
  if (error) return error.code === "53400" ? json({ error: "Too many messages. Please try again later or email us." }, 429) : json({ error: "Your message could not be sent. Please try again." }, 500);

  const key = Deno.env.get("RESEND_API_KEY"), to = Deno.env.get("CONTACT_NOTIFY_TO"), from = Deno.env.get("CONTACT_NOTIFY_FROM");
  if (key && to && from) {
    const inbox = `${(Deno.env.get("DASHBOARD_URL") || "").replace(/\/$/, "")}/website/inbox`;
    const safe = (x: string) => x.replace(/[<>&]/g, "");
    await fetch("https://api.resend.com/emails", {
      method: "POST",
      signal: AbortSignal.timeout(6000),
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from, to: to.split(",").map((x) => x.trim()).filter(Boolean),
        subject: `New website message: ${safe(topic || "general")}`,
        text: `A new message arrived through safariyamama.com from ${safe(name)}${org ? ` (${safe(org)})` : ""}.\n\nRead and answer it in the dashboard Inbox: ${inbox}\n`,
      }),
    }).catch(() => undefined); // the message is stored either way
  }
  return json({ ok: true });
});
