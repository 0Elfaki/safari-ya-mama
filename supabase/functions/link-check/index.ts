// link-check: checks the links in a blog post before it is published (Website team only).
//   POST { urls: string[] }  → { results: [{ url, ok, status, note }] }
// Only http(s) addresses are fetched (HEAD, then GET when HEAD is refused), 6 s each, at most 30.
// Site pages ("/about") are checked against the website. Addresses that point at private networks
// are refused, so the function cannot be used to reach internal services.
import { createClient } from "npm:@supabase/supabase-js@2";

const SITE = (Deno.env.get("SITE_URL") || "https://safariyamama.com").replace(/\/$/, "");
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const PRIVATE = /^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|0\.|\[?::1\]?|\[?f[cd])/i;

async function check(raw: string) {
  const u = raw.startsWith("/") ? SITE + raw : raw;
  let parsed: URL;
  try { parsed = new URL(u); } catch { return { url: raw, ok: false, status: 0, note: "not a valid address" }; }
  if (!/^https?:$/.test(parsed.protocol)) return { url: raw, ok: false, status: 0, note: "only http and https links" };
  if (PRIVATE.test(parsed.hostname)) return { url: raw, ok: false, status: 0, note: "private address" };
  for (const method of ["HEAD", "GET"]) {
    try {
      const r = await fetch(parsed, { method, redirect: "follow", signal: AbortSignal.timeout(6000), headers: { "User-Agent": "SafariYaMama-LinkCheck/1.0" } });
      if (method === "HEAD" && (r.status === 405 || r.status === 403)) continue;
      return { url: raw, ok: r.status < 400, status: r.status, note: r.status < 400 ? "works" : `answers ${r.status}` };
    } catch (e) {
      if (method === "GET") return { url: raw, ok: false, status: 0, note: (e as Error).name === "TimeoutError" ? "no answer in 6 s" : "could not be reached" };
    }
  }
  return { url: raw, ok: false, status: 0, note: "could not be reached" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const caller = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } }, auth: { persistSession: false },
  });
  const { data: allowed } = await caller.rpc("web_can", { p: "write" });
  if (allowed !== true) return json({ error: "Website team only." }, 403);
  let urls: string[] = [];
  try { urls = ((await req.json()).urls ?? []).map(String).slice(0, 30); } catch { return json({ error: "bad request" }, 400); }
  const results = await Promise.all([...new Set(urls)].map(check));
  return json({ results });
});
