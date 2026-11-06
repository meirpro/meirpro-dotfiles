// Generate product photos with OpenAI GPT Image on a TRANSPARENT background.
// Transparency is an API parameter (background + png/webp), never prompt text.
//
//   node --env-file=<file holding OPENAI_API_KEY> gen.mjs <jobs.json> <outDir>
//
// jobs.json:
// { "model": "gpt-image-2.5-sunburst",   // precise edits; "gpt-image-2.5-flare" = faster
//   "size": "1024x1024", "quality": "high", "n": 2,
//   "base": "Studio product photograph ... (shared prefix, optional)",
//   "jobs": [ { "slug": "paper-a5", "refs": ["/abs/card.png", "/abs/logo.png"],
//               "prompt": "... exactly as image 1 ..." } ] }
// refs present -> POST /v1/images/edits (refs sent as image[] in order: image 1, 2, ...)
// no refs      -> POST /v1/images/generations
// Writes <outDir>/<slug>-<i>.png. Never prints the key.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { basename } from "node:path";

const [jobsPath, outDir] = process.argv.slice(2);
if (!jobsPath || !outDir) {
  console.error("usage: node --env-file=<secrets> gen.mjs <jobs.json> <outDir>");
  process.exit(2);
}
const key = process.env.OPENAI_API_KEY ?? "";
if (key.length < 40) {
  console.error(`OPENAI_API_KEY missing or a stub (length ${key.length}).`);
  process.exit(1);
}
const cfg = JSON.parse(await readFile(jobsPath, "utf8"));
await mkdir(outDir, { recursive: true });

async function run(job) {
  const prompt = [cfg.base, job.prompt].filter(Boolean).join(" ");
  const common = {
    model: cfg.model ?? "gpt-image-2.5-sunburst",
    prompt,
    size: cfg.size ?? "1024x1024",
    quality: cfg.quality ?? "high",
    n: String(cfg.n ?? 2),
    background: "transparent", // the API switch — do NOT also say it in the prompt
    output_format: "png", // transparency needs png or webp
  };
  const t0 = Date.now();
  let res;
  if (job.refs?.length) {
    const fd = new FormData();
    for (const [k, v] of Object.entries(common)) fd.append(k, v);
    for (const r of job.refs) {
      const type = r.endsWith(".jpg") || r.endsWith(".jpeg") ? "image/jpeg" : r.endsWith(".webp") ? "image/webp" : "image/png";
      fd.append("image[]", new Blob([await readFile(r)], { type }), basename(r));
    }
    res = await fetch("https://api.openai.com/v1/images/edits", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}` },
      body: fd,
    });
  } else {
    res = await fetch("https://api.openai.com/v1/images/generations", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ...common, n: Number(common.n) }),
    });
  }
  const j = await res.json();
  if (!res.ok) return `${job.slug}: HTTP ${res.status} ${j?.error?.message ?? ""}`;
  for (const [i, d] of j.data.entries())
    await writeFile(`${outDir}/${job.slug}-${i + 1}.png`, Buffer.from(d.b64_json, "base64"));
  return `${job.slug}: ${j.data.length} image(s) in ${((Date.now() - t0) / 1000).toFixed(0)}s, tokens ${j.usage?.total_tokens ?? "?"}`;
}
for (const line of await Promise.all(cfg.jobs.map(run))) console.log(line);
