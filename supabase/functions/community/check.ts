// Mothers' circle content check, layer 1: rules (no network, explainable, same on phone and server).
// The Dart twin is lib/features/community/domain/community_check.dart; both must pass test/fixtures/community_cases.json
// (Dart: test/community_test.dart; this file: `node supabase/tests/community_check.test.ts`).
//
// Verdicts, strongest first:
//   block    abuse or insults: never shown
//   fix      a phone number or email address: she removes it before posting (the server redacts anyway)
//   review   hidden from others until a health worker checks it: a myth stated as fact, selling,
//            a "miracle cure", or a danger sign (also flagged urgent so staff see it first)
//   publish  shown now. A myth asked as a question ("is it true I should stop iron?") is published
//            with the matching fact attached, because a question is how a mother finds the truth.

export type HandleRules = {
  min: number;
  max: number;
  max_digits: number;
  reserved_contains: string[];
  reserved_prefix: string[];
  offensive: string[];
};

export type Rules = {
  handle: HandleRules;
  urgent: string[];
  abuse: string[];
  selling: string[];
  miracle: string[];
  medical_terms: string[];
  question_starts: string[];
  myths: { id: string; all: string[][]; unless?: string[] }[];
};

export type Check = {
  verdict: "publish" | "review" | "block" | "fix";
  urgent: boolean;
  medical: boolean;
  reasons: string[]; // urgent | privacy | abuse | selling | miracle | myth:<id> | fact:<id>
  facts: string[]; // myth ids whose fact is shown with the post
};

const PHONE = /\+?\d[\d\s\-]{7,}\d/g;
const EMAIL = /[^\s@]+@[^\s@]+\.[a-z]{2,}/gi;
const LINK = /(https?:\/\/|www\.)\S+/gi;

/** Lower case, plain apostrophes, words separated by single spaces, "soooo" -> "soo". */
export function clean(s: string): string {
  return s
    .toLowerCase()
    .replace(/[‘’`]/g, "'")
    .replace(/[^\p{L}\p{N}'%+\- ]/gu, " ")
    .replace(/(\p{L})\1{2,}/gu, "$1$1")
    .replace(/\s+/g, " ")
    .trim();
}

/** Sentences with whether each one is a question. */
function sentences(text: string, rules: Rules): { s: string; q: boolean }[] {
  const out: { s: string; q: boolean }[] = [];
  const re = /([^.!?\n]+)([.!?\n]*)/g;
  for (const m of text.matchAll(re)) {
    const s = ` ${clean(m[1])} `;
    if (s.trim() === "") continue;
    const q = m[2].includes("?") || rules.question_starts.some((w) => s.startsWith(` ${w} `));
    out.push({ s, q });
  }
  return out;
}

/** A term matches at the start of a word: "stop" matches "stopped", not "nonstop". */
const has = (padded: string, term: string) => padded.includes(` ${term}`);
const any = (padded: string, terms: string[]) => terms.some((t) => has(padded, t));

/** Phone numbers with 9 or more digits, and email addresses. */
export function privacyHits(text: string): string[] {
  const hits: string[] = [];
  for (const m of text.match(PHONE) ?? []) if (m.replace(/\D/g, "").length >= 9) hits.push(m.trim());
  for (const m of text.match(EMAIL) ?? []) hits.push(m);
  return hits;
}

/** What the server stores when a post still has contact details in it. */
export function redact(text: string): string {
  return text
    .replace(PHONE, (m) => (m.replace(/\D/g, "").length >= 9 ? "[number removed]" : m))
    .replace(EMAIL, "[email removed]");
}

export function checkText(text: string, rules: Rules): Check {
  const whole = ` ${clean(text)} `;
  const reasons: string[] = [];
  const facts: string[] = [];
  let myth = false;

  const urgent = any(whole, rules.urgent);
  if (urgent) reasons.push("urgent");
  if (privacyHits(text).length) reasons.push("privacy");
  if (any(whole, rules.abuse)) reasons.push("abuse");
  if (any(whole, rules.selling) || LINK.test(text)) reasons.push("selling");
  LINK.lastIndex = 0;
  if (any(whole, rules.miracle)) reasons.push("miracle");

  for (const { s, q } of sentences(text, rules)) {
    for (const r of rules.myths) {
      if (facts.includes(r.id)) continue;
      if (!r.all.every((group) => any(s, group))) continue;
      if (r.unless && any(s, r.unless)) continue;
      facts.push(r.id);
      reasons.push(`${q ? "fact" : "myth"}:${r.id}`);
      if (!q) myth = true;
    }
  }

  const verdict = reasons.includes("abuse")
    ? "block"
    : reasons.includes("privacy")
      ? "fix"
      : urgent || myth || reasons.includes("selling") || reasons.includes("miracle")
        ? "review"
        : "publish";
  return { verdict, urgent, medical: any(whole, rules.medical_terms), reasons, facts };
}

// ───────────── community names (usernames)
// Problems, in the order they are checked:
//   length | chars (only letters, numbers, "_" and ".") | start (must start with a letter;
//   no "__", "..", or ending in "_"/".") | digits (more than 4: looks like a phone number) |
//   reserved (looks like staff or the app) | offensive

const LEET: Record<string, string> = { "0": "o", "1": "i", "l": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b" };

/** Two names are the same name when their keys match ("Mama_Amina" = "mama.amina" = "mamaam1na").
 *  1, i and l count as the same letter, so "Ami1a" cannot copy "Amila". */
export function handleKey(handle: string): string {
  return handle.trim().toLowerCase().replace(/[._]/g, "").replace(/[01l34578]/g, (d) => LEET[d]);
}

export function checkHandle(handle: string, r: HandleRules): string | null {
  const h = handle.trim();
  if (h.length < r.min || h.length > r.max) return "length";
  if (!/^[A-Za-z0-9._]+$/.test(h)) return "chars";
  if (!/^[A-Za-z]/.test(h) || /[._]{2}/.test(h) || /[._]$/.test(h)) return "start";
  if ((h.match(/\d/g) ?? []).length > r.max_digits) return "digits";
  const key = handleKey(h);
  if (r.reserved_contains.some((w) => key.includes(w)) || r.reserved_prefix.some((w) => key.startsWith(w))) return "reserved";
  const bad = (w: string) => (w.length >= 5 ? key.includes(w) : key === w || key.startsWith(w) || key.endsWith(w));
  if (r.offensive.some(bad)) return "offensive";
  return null;
}
