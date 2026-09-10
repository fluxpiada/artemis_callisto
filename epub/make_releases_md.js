#!/usr/bin/env node
//
// Writes a short release history into the manuscript, so the EPUB carries a
// list of the editions that came before it.
//
//   node epub/make_releases_md.js <owner> <repo> <output-path>
//
// This talks to the network, and the network fails. A book build must never
// depend on GitHub being reachable, so every failure here — no releases, a
// 404, a rate limit, no connection at all — writes a valid file containing
// just the current edition, and exits 0. The only thing that changes is how
// much history the reader sees.

const fs = require("fs");
const path = require("path");
const https = require("https");

const [owner, repo, outPath] = process.argv.slice(2);

if (!owner || !repo || !outPath) {
  console.error("usage: make_releases_md.js <owner> <repo> <output-path>");
  process.exit(2);
}

const today = new Date().toISOString().substring(0, 10);
const centred = (text) => `<div style="text-align:center;"><em>${text}</em></div>\n`;

function write(releases) {
  let md = "";
  for (const r of releases) {
    const name = r && (r.name || r.tag_name);
    if (!name) continue;
    const date = (r.published_at || "").substring(0, 10) || "unknown";
    md += centred(`${name} — ${date}`) + "\n";
  }
  md += centred(`Current edition — ${today}`);

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, md);
}

function giveUp(why) {
  console.error(`⚠️  Release history unavailable (${why}) — continuing without it.`);
  write([]);
  process.exit(0);
}

const options = {
  headers: {
    "User-Agent": "book_bake",
    Accept: "application/vnd.github+json",
  },
  timeout: 10000,
};

// CI has a token sitting in the environment; using it lifts the 60-request
// hourly limit that unauthenticated calls share across the whole runner.
const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
if (token) options.headers.Authorization = `Bearer ${token}`;

const req = https.get(
  `https://api.github.com/repos/${owner}/${repo}/releases?per_page=100`,
  options,
  (res) => {
    if (res.statusCode !== 200) {
      res.resume();
      return giveUp(`HTTP ${res.statusCode}`);
    }

    let data = "";
    res.setEncoding("utf8");
    res.on("data", (chunk) => (data += chunk));
    res.on("end", () => {
      let parsed;
      try {
        parsed = JSON.parse(data);
      } catch {
        return giveUp("unreadable response");
      }
      // An error response is an object, not an array. Without this check the
      // loop below throws and takes the whole book build down with it.
      if (!Array.isArray(parsed)) return giveUp("unexpected response shape");

      write(parsed.filter((r) => r && !r.draft && !r.prerelease));
    });
  }
);

req.on("timeout", () => {
  req.destroy();
  giveUp("timed out");
});
req.on("error", (e) => giveUp(e.message));
