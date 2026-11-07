// AI gateway for MamaBot (task "assistant").
//
// Contract with the app (lib/data/ai_client.dart):
//   request  { task: "assistant", lang: "sw" | "en", input: string, context: { stage: "pregnant" | "postpartum" | "baby" } }
//   response { text, label, urgent }  or  { unavailable: true }
//
// Safety: the app never lets this change a warning level, and it routes urgent words to Emergency
// before calling. This function checks again: an urgent topic gets a fixed safety message and the
// AI is not called. The question is never logged or stored; ai_usage keeps only who and when,
// for the daily limit. The model never sees her name, phone or records.
//
// Provider: Groq (OpenAI-compatible chat completions API).
// Secrets (set with `supabase secrets set`, never in git or chat):
//   GROQ_API_KEY  required; without it the app falls back to its scripted answers
//   GROQ_MODEL    optional; defaults to DEFAULT_MODEL below. Check the model list in the Groq
//                 console and test Kiswahili answers before changing it.
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically; the service key
// stays inside this function.
import { createClient } from "npm:@supabase/supabase-js@2";

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const DEFAULT_MODEL = "llama-3.3-70b-versatile";
const TIMEOUT_MS = 12000; // the app gives up after 15 s and shows the scripted answer

const DAILY_LIMIT = 30;
const MAX_INPUT = 600;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Words that mean "go now". Mirrors the app's urgent intents (assistant.g.dart); keep both in step.
const URGENT_WORDS = [
  "bleeding", "heavy bleeding", "fits", "convulsion", "convulsions", "seizure", "unconscious", "fainted", "fainting",
  "not breathing", "can't breathe", "cannot breathe", "blurred vision", "severe headache", "water broke", "waters broke",
  "baby not moving", "stopped moving", "kill myself", "suicide", "harm my baby", "hurt myself",
  "kutokwa damu", "anatoka damu", "degedege", "kifafa", "amezimia", "kuzimia", "hapumui", "hawezi kupumua",
  "kichwa kinauma sana", "maji yamevunjika", "hachezi", "kujiua", "kumdhuru mtoto",
];
// whole words only: "blood pressure" or "benefit" must not trigger the safety message
// (the words are plain letters, spaces and apostrophes, so they need no regex escaping)
const URGENT = URGENT_WORDS.map((w) => new RegExp(`(^|[^a-z'])${w}($|[^a-z])`, "i"));

const SAFETY = {
  en: "This may be a danger sign. Go to the nearest health facility now, and ask someone to go with you. Open Emergency help in the app for who to call.",
  sw: "Hii inaweza kuwa dalili ya hatari. Nenda kituo cha afya kilicho karibu sasa, na muombe mtu akusindikize. Fungua Msaada wa dharura kwenye programu kuona wa kumpigia.",
};
const LABEL = {
  ai: { en: "AI answer · not medical advice", sw: "Jibu la AI · si ushauri wa kitabibu" },
  safety: { en: "Safety message · not AI", sw: "Ujumbe wa usalama · si AI" },
};

const SYSTEM = `You answer questions from mothers in Tanzania and East Africa through the Safari ya Mama app, during pregnancy, after birth, and while caring for a baby up to 9 months old.

How to answer:
- Reply in the language you are told to use (Kiswahili or English), in short, plain sentences a person with little schooling can follow. At most about 120 words. No headings, no tables, no markdown.
- Give practical, everyday guidance that matches WHO advice and East African life (local foods, the clinic card, community health workers).
- Never diagnose, never name a likely illness, never prescribe or change a medicine or dose, and never say that she or the baby is fine or that something is nothing to worry about.
- If anything in the question could be a danger sign (bleeding, fits, severe headache, blurred vision, swelling of face or hands, fever, water leaking, baby moving less, trouble breathing, a baby not feeding, thoughts of self-harm), tell her to go to a health facility now or contact a health worker today, before anything else.
- When unsure, tell her to ask her health worker. You support health workers; you do not replace them.
- Do not ask for or repeat her name, phone number or location.
Reply with the answer only.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // 1. who is asking (the app sends the signed-in session)
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: who } = await admin.auth.getUser(token);
  if (!who?.user) return json({ error: "sign in first" }, 401);

  // 2. what is asked
  let body: { task?: string; lang?: string; input?: string; context?: { stage?: string } };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const lang = body.lang === "sw" ? "sw" : "en";
  const input = (body.input ?? "").toString().trim().slice(0, MAX_INPUT);
  const stage = ["pregnant", "postpartum", "baby"].includes(body.context?.stage ?? "") ? body.context!.stage! : "pregnant";
  if (body.task !== "assistant" || !input) return json({ error: "bad request" }, 400);

  // 3. urgent words never reach the AI
  const lower = input.toLowerCase();
  if (URGENT.some((re) => re.test(lower))) {
    return json({ text: SAFETY[lang], label: LABEL.safety[lang], urgent: true, action: "emergency" });
  }

  // 4. daily limit
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await admin.from("ai_usage").select("id", { count: "exact", head: true }).eq("profile_id", who.user.id).gte("at", since);
  if ((count ?? 0) >= DAILY_LIMIT) return json({ error: "daily limit" }, 429);

  // 5. no key configured: the app uses its scripted answers
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) return json({ unavailable: true });

  await admin.from("ai_usage").insert({ profile_id: who.user.id });

  const stageWords = { pregnant: "She is pregnant.", postpartum: "She gave birth in the last 6 weeks.", baby: "She is caring for a baby under 9 months." }[stage];
  try {
    const res = await fetch(GROQ_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(TIMEOUT_MS),
      body: JSON.stringify({
        model: Deno.env.get("GROQ_MODEL") || DEFAULT_MODEL,
        temperature: 0.3,
        max_tokens: 400,
        messages: [
          { role: "system", content: SYSTEM },
          { role: "user", content: `Answer in ${lang === "sw" ? "Kiswahili" : "English"}. ${stageWords}\n\nHer question:\n${input}` },
        ],
      }),
    });
    if (!res.ok) return json({ unavailable: true, reason: `groq ${res.status}` }); // 429 busy, 401 bad key, 5xx down
    const data = await res.json();
    const choice = data?.choices?.[0];
    const text = (choice?.message?.content ?? "").toString().trim();
    // an empty or cut-off answer is not shown: the app uses its scripted answer instead
    if (!text || choice?.finish_reason === "length" || choice?.finish_reason === "content_filter") return json({ unavailable: true });
    return json({ text: `${text}\n\n${LABEL.ai[lang]}`, label: LABEL.ai[lang], urgent: false });
  } catch {
    return json({ unavailable: true }); // timeout or no connection
  }
});
