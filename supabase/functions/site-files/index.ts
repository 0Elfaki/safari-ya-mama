// site-files: the website's sitemap.xml and robots.txt, built from what is published.
// Public (verify_jwt off). The website's host forwards /sitemap.xml and /robots.txt here.
//   GET ?file=sitemap.xml   every page of the site plus every published blog post (noindex pages left out)
//   GET ?file=robots.txt    the text saved under Website › SEO & settings, or a safe default
// Secrets: SITE_URL (optional, default https://safariyamama.com).
import { createClient } from "npm:@supabase/supabase-js@2";

const SITE = (Deno.env.get("SITE_URL") || "https://safariyamama.com").replace(/\/$/, "");
const PAGES = ["/", "/innovation", "/how-it-works", "/impact", "/learning", "/blog", "/about", "/contact"];
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const file = url.searchParams.get("file") ?? (url.pathname.endsWith("robots.txt") ? "robots.txt" : "sitemap.xml");
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
  const { data } = await db.rpc("site_sitemap");
  const info = (data ?? { posts: [], noindex: [], robots: null }) as { posts: { slug: string; updated: string }[]; noindex: string[]; robots: string | null };

  if (file === "robots.txt") {
    const text = info.robots?.trim() || "User-agent: *\nAllow: /\nDisallow: /blog/preview/";
    const body = /sitemap:/i.test(text) ? text : `${text}\n\nSitemap: ${SITE}/sitemap.xml`;
    return new Response(body + "\n", { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=3600" } });
  }

  const skip = new Set(info.noindex ?? []);
  const rows = [
    ...PAGES.filter((p) => !skip.has(p)).map((p) => `  <url><loc>${esc(SITE + p)}</loc></url>`),
    ...(info.posts ?? []).filter((p) => !skip.has(`/blog/${p.slug}`))
      .map((p) => `  <url><loc>${esc(`${SITE}/blog/${p.slug}`)}</loc><lastmod>${p.updated.slice(0, 10)}</lastmod></url>`),
  ];
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${rows.join("\n")}\n</urlset>\n`;
  return new Response(xml, { headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, max-age=3600" } });
});
