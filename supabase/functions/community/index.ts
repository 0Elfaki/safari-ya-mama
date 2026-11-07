// Mothers' circle: the only way a post or reply gets stored. Deploy with verify_jwt on.
//
// Contract with the app (lib/features/community/data/community_service.dart):
//   { action: "post", body, topic, parent_id?, anonymous: bool, stage?: { kind: "pregnant"|"baby", value: int } }
//     → { id, status: "published"|"review", urgent, facts: [ids], reasons: [codes] }
//     → { status: "blocked", reasons }   nothing stored (insults)
//     → { error: "need_handle" } 409     she chose to post with her name but has none yet
//     → { error: "muted", until } 403    4 strikes: no posting for 30 days
//     → { error } 429 too many posts, 400 bad request, 401 not signed in
//   { action: "handle_check", handle }   → { ok: true } | { ok: false, problem: <rule> | "taken" }
//   { action: "handle", handle }         → { handle } | { error: <rule> | "taken" | "too_soon", can_change_at? } 400/409
// Community names follow the shared rules (check.ts checkHandle; same file as the app). A name
// can be changed once every 30 days. Look-alike names count as taken (handle_key).
//
// The content check, in layers (README "Mothers' circle"):
//   1. rules (check.ts + rules.json, the same file the app checks with before sending)
//   2. new members: the first 2 posts wait for a health worker
//   3. AI second opinion (Groq) for anything the rules would publish; if it calls the post
//      misinformation, harmful, spam or abuse, the post waits for a health worker. The AI can only
//      make a post wait, never publish something the rules held back.
//   4. no AI available: a post about medicines waits for a health worker
//   After publishing: 3 reports hide a post (report_community_post), and health workers can add a
//   note, publish, hide or remove from the dashboard (moderate_community_post).
// Health worker posts are published straight away with a badge (insults are still refused).
// The post text is sent to Groq without her name or any other detail; nothing is logged.
//
// Secrets: GROQ_API_KEY (optional; without it layer 4 applies), GROQ_MODEL (optional).
import { createClient } from "npm:@supabase/supabase-js@2";
import rulesJson from "./rules.json" with { type: "json" };
import { checkHandle, checkText, handleKey, redact, type Rules } from "./check.ts";

const rules = rulesJson as unknown as Rules;
const TOPICS = ["pregnancy", "birth", "feeding", "baby", "feelings", "other"];
const STAFF = ["health_worker", "facility_admin", "programme_admin", "super_admin"];
const HOURLY_LIMIT = 10;
const NEW_MEMBER_POSTS = 2;
const AI_BLOCKING = ["misinformation", "harmful", "spam", "abuse"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const AI_SYSTEM = `You check posts in a support group for pregnant women and new mothers in Tanzania (Kiswahili or English).
Decide if the post could mislead or harm a mother or baby if other mothers believed it.
Judge against WHO and Tanzania Ministry of Health guidance for pregnancy, birth, breastfeeding and baby care.
Labels:
- "ok": personal experience, feelings, questions, encouragement, or advice that matches guidance.
- "misinformation": states something false or unproven about health as if it were true.
- "harmful": encourages something dangerous (stopping medicine, avoiding care, unsafe remedies, harming self or others).
- "spam": selling, advertising, asking for money or contact outside the app.
- "abuse": insults, shaming, hate.
A question is "ok" unless it pushes a harmful practice. When unsure, choose "ok" with low confidence.
Reply with JSON only: {"label": "...", "confidence": 0.0-1.0, "why": "at most 15 words, English"}`;

async function aiCheck(text: string): Promise<{ label: string; confidence: number; why: string } | null> {
  const key = Deno.env.get("GROQ_API_KEY");
  if (!key) return null;
  try {
    const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      signal: AbortSignal.timeout(8000),
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("GROQ_MODEL") || "llama-3.3-70b-versatile",
        temperature: 0,
        max_tokens: 120,
        response_format: { type: "json_object" },
        messages: [{ role: "system", content: AI_SYSTEM }, { role: "user", content: text }],
      }),
    });
    if (!r.ok) return null;
    const out = JSON.parse((await r.json()).choices?.[0]?.message?.content ?? "{}");
    const label = String(out.label ?? "").toLowerCase();
    if (!["ok", ...AI_BLOCKING].includes(label)) return null;
    const confidence = Math.max(0, Math.min(1, Number(out.confidence) || 0));
    return { label, confidence, why: String(out.why ?? "").slice(0, 120) };
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer /i, "");
  const { data: who } = await db.auth.getUser(token);
  const uid = who?.user?.id;
  if (!uid) return json({ error: "sign in first" }, 401);

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }

  // ── community names
  if (input.action === "handle_check" || input.action === "handle") {
    const handle = String(input.handle ?? "").trim();
    const problem = checkHandle(handle, rules.handle);
    if (problem) return input.action === "handle" ? json({ error: problem }, 400) : json({ ok: false, problem });
    const key = handleKey(handle);
    const { data: owner } = await db.from("community_profiles").select("profile_id").eq("handle_key", key).maybeSingle();
    const taken = !!owner && owner.profile_id !== uid;
    if (input.action === "handle_check") return json(taken ? { ok: false, problem: "taken" } : { ok: true });
    if (taken) return json({ error: "taken" }, 409);

    const { data: mine } = await db.from("community_profiles").select("handle, handle_changed_at").eq("profile_id", uid).maybeSingle();
    if (mine?.handle === handle) return json({ handle });
    const canChange = mine?.handle_changed_at ? new Date(new Date(mine.handle_changed_at).getTime() + 30 * 86400_000) : null;
    if (mine?.handle && canChange && canChange.getTime() > Date.now()) {
      return json({ error: "too_soon", can_change_at: canChange.toISOString() }, 409);
    }
    const { error } = await db.from("community_profiles").upsert(
      { profile_id: uid, handle, handle_key: key, handle_changed_at: new Date().toISOString() },
      { onConflict: "profile_id" },
    );
    if (error) return json({ error: error.code === "23505" ? "taken" : "could not save, try again" }, error.code === "23505" ? 409 : 500);
    return json({ handle });
  }

  if (input.action !== "post") return json({ error: "unknown action" }, 400);

  const body = String(input.body ?? "").trim().replace(/\n{3,}/g, "\n\n");
  const topic = TOPICS.includes(String(input.topic)) ? String(input.topic) : "other";
  const parentId = typeof input.parent_id === "string" ? input.parent_id : null;
  if (body.length < 2 || body.length > 1000) return json({ error: "write 2 to 1000 characters" }, 400);

  const { data: me } = await db.from("profiles").select("role, display_name, deleted_at").eq("id", uid).maybeSingle();
  if (!me || me.deleted_at || !(me.role === "mother" || STAFF.includes(me.role))) {
    return json({ error: "only mothers and health workers can post" }, 403);
  }
  const staff = STAFF.includes(me.role);

  // standing: 4 strikes stop posting for 30 days; 2 strikes send every post to review
  const { data: standing } = await db.from("community_profiles")
    .select("handle, review_until, muted_until").eq("profile_id", uid).maybeSingle();
  if (!staff && standing?.muted_until && new Date(standing.muted_until).getTime() > Date.now()) {
    return json({ error: "muted", until: standing.muted_until }, 403);
  }
  const anonymous = staff ? false : input.anonymous !== false;
  if (!anonymous && !staff && !standing?.handle) return json({ error: "need_handle" }, 409);

  const hourAgo = new Date(Date.now() - 3600_000).toISOString();
  const { count: lastHour } = await db.from("community_posts").select("id", { count: "exact", head: true })
    .eq("author_id", uid).gte("created_at", hourAgo);
  if ((lastHour ?? 0) >= HOURLY_LIMIT) return json({ error: "too many posts, try again later" }, 429);

  if (parentId) {
    const { data: parent } = await db.from("community_posts").select("id, parent_id, status").eq("id", parentId).maybeSingle();
    if (!parent || parent.parent_id || parent.status !== "published") return json({ error: "this post is closed" }, 400);
  }

  // layer 1: rules
  const check = checkText(body, rules);
  if (check.verdict === "block") return json({ status: "blocked", reasons: check.reasons });
  const reasons = [...check.reasons];
  let review = check.verdict === "review" || check.verdict === "fix"; // the app asks her to remove contacts first
  let ai: Awaited<ReturnType<typeof aiCheck>> = null;

  if (!staff) {
    // layer 2b: repeat misinformation (2+ strikes): every post waits for 30 days
    if (standing?.review_until && new Date(standing.review_until).getTime() > Date.now()) {
      reasons.push("strikes");
      review = true;
    }
    // layer 2: new members
    const { count: published } = await db.from("community_posts").select("id", { count: "exact", head: true })
      .eq("author_id", uid).eq("status", "published");
    if ((published ?? 0) < NEW_MEMBER_POSTS) {
      reasons.push("new");
      review = true;
    }
    // layer 3: AI second opinion on what the rules would publish
    if (!review) {
      ai = await aiCheck(body);
      if (ai && AI_BLOCKING.includes(ai.label) && ai.confidence >= 0.6) {
        reasons.push(`ai:${ai.label}`);
        review = true;
      } else if (!ai && check.medical) {
        // layer 4: no AI available, a post about medicines waits
        reasons.push("unchecked-medical");
        review = true;
      }
    }
  }

  const stage = input.stage as { kind?: string; value?: number } | undefined;
  const stageKind = stage && ["pregnant", "baby"].includes(String(stage.kind)) ? String(stage.kind) : null;
  const stageValue = stageKind && Number.isInteger(stage!.value) && stage!.value! >= 0 && stage!.value! <= 60 ? stage!.value! : null;

  const { data: row, error } = await db.from("community_posts").insert({
    author_id: uid,
    parent_id: parentId,
    topic,
    body: redact(body),
    anonymous,
    stage_kind: staff ? null : stageKind,
    stage_value: staff ? null : stageValue,
    status: staff || !review ? "published" : "review",
    urgent: check.urgent,
    reasons,
    facts: check.facts,
    ai,
    staff_post: staff,
  }).select("id, status").single();
  if (error || !row) return json({ error: "could not save, try again" }, 500);

  return json({ id: row.id, status: row.status, urgent: check.urgent, facts: check.facts, reasons });
});
