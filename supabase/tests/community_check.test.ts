// Runs the shared Mothers' circle cases against the server rules engine.
//   node supabase/tests/community_check.test.ts      (Node 22.6+ strips the types)
import { readFileSync } from "node:fs";
import { checkText, redact, type Rules } from "../functions/community/check.ts";

const root = new URL("../../", import.meta.url);
const rules = JSON.parse(readFileSync(new URL("supabase/functions/community/rules.json", root), "utf8")) as Rules;
const cases = JSON.parse(readFileSync(new URL("test/fixtures/community_cases.json", root), "utf8")) as {
  text: string;
  verdict: string;
  reasons: string[];
  urgent?: boolean;
  medical?: boolean;
}[];

let failed = 0;
for (const c of cases) {
  const r = checkText(c.text, rules);
  const same = r.verdict === c.verdict && [...r.reasons].sort().join() === [...c.reasons].sort().join() &&
    (c.urgent === undefined || r.urgent === c.urgent) && (c.medical === undefined || r.medical === c.medical);
  if (!same) {
    failed++;
    console.log(`FAIL ${JSON.stringify(c.text)}\n  want ${c.verdict} ${c.reasons}\n  got  ${r.verdict} ${r.reasons}`);
  }
}
const red = redact("call 0712 345 678 or a@b.co, week 28");
if (red !== "call [number removed] or [email removed], week 28") {
  failed++;
  console.log(`FAIL redact: ${red}`);
}
console.log(failed ? `${failed} failed` : `all ${cases.length + 1} passed`);
if (failed) process.exit(1);

// community names: same cases as test/community_test.dart
import { checkHandle, handleKey } from "../functions/community/check.ts";
const handles = JSON.parse(readFileSync(new URL("test/fixtures/handle_cases.json", root), "utf8")) as { handle: string; problem: string | null }[];
let hFailed = 0;
for (const c of handles) {
  const got = checkHandle(c.handle, rules.handle);
  if (got !== c.problem) {
    hFailed++;
    console.log(`FAIL handle ${JSON.stringify(c.handle)}: want ${c.problem} got ${got}`);
  }
}
for (const [a, b] of [["Mama_Amina", "mama.amina"], ["mamaam1na", "MamaAmina"], ["zawad1", "zawadi"]]) {
  if (handleKey(a) !== handleKey(b)) {
    hFailed++;
    console.log(`FAIL same name: ${a} vs ${b}`);
  }
}
console.log(hFailed ? `${hFailed} handle checks failed` : `all ${handles.length + 3} handle checks passed`);
if (hFailed) process.exit(1);
