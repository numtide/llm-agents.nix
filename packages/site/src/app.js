const REPO = "github:numtide/llm-agents.nix";
const SRC = "https://github.com/numtide/llm-agents.nix/blob/main/packages";
const CATEGORY_ORDER = [
  "AI Coding Agents",
  "AI Assistants",
  "Claude Code Ecosystem",
  "ACP Ecosystem",
  "Usage Analytics",
  "Workflow & Project Management",
  "Code Review",
  "Voice & Transcription",
  "Memory & Code Intelligence",
  "Sandboxing & Isolation",
  "Skills & Plugins",
  "Utilities",
  "Uncategorized",
];

const $ = (s) => document.querySelector(s);
const q = $("#q");
const platform = $("#platform");
const source = $("#source");
const results = $("#results");
const tpl = $("#card");

const state = { category: "", pkgs: [] };

function readUrl() {
  const p = new URLSearchParams(location.search);
  q.value = p.get("q") ?? "";
  state.category = p.get("category") ?? "";
  platform.value = p.get("platform") ?? "";
  source.value = p.get("source") ?? "";
}

function writeUrl() {
  const p = new URLSearchParams();
  if (q.value) p.set("q", q.value);
  if (state.category) p.set("category", state.category);
  if (platform.value) p.set("platform", platform.value);
  if (source.value) p.set("source", source.value);
  const s = p.toString();
  history.replaceState(null, "", s ? `?${s}` : location.pathname);
}

// Name matches rank above description matches. All terms must match.
function score(pkg, terms) {
  let total = 0;
  for (const t of terms) {
    const n = pkg.name.toLowerCase();
    if (n === t) total += 100;
    else if (n.startsWith(t)) total += 50;
    else if (n.includes(t)) total += 20;
    else if (pkg._hay.includes(t)) total += 5;
    else return -1;
  }
  return total;
}

function render() {
  const terms = q.value.toLowerCase().split(/\s+/).filter(Boolean);
  const rows = state.pkgs
    .filter((p) => !state.category || p.category === state.category)
    .filter((p) => !platform.value || p.platforms.includes(platform.value))
    .filter((p) => !source.value || p.source === source.value)
    .map((p) => [score(p, terms), p])
    .filter(([s]) => s >= 0)
    .sort((a, b) => b[0] - a[0] || a[1].name.localeCompare(b[1].name));

  results.replaceChildren(...rows.map(([, p]) => card(p)));
  $("#count").textContent = `${rows.length} of ${state.pkgs.length} packages`;
  $("#empty").hidden = rows.length > 0;
  for (const b of document.querySelectorAll(".chip")) {
    b.setAttribute("aria-pressed", b.dataset.value === state.category);
  }
  writeUrl();
}

const BADGE_TITLES = {
  source: "Built from source",
  binary: "Prebuilt upstream binary",
  bytecode: "Prebuilt bytecode",
  unfree: "Unfree license",
};

function badge(text, cls) {
  const s = document.createElement("span");
  s.className = `badge ${cls}`;
  s.textContent = text;
  s.title = BADGE_TITLES[text] ?? text;
  return s;
}

function link(href, text, label) {
  const a = document.createElement("a");
  a.href = href;
  a.textContent = text;
  if (label) a.setAttribute("aria-label", label);
  return a;
}

// aria-label is not allowed on plain spans.
function described(prefix, text) {
  const s = document.createElement("span");
  const sr = document.createElement("span");
  sr.className = "sr-only";
  sr.textContent = `${prefix} `;
  s.append(sr, text);
  return s;
}

function announce(msg) {
  $("#announce").textContent = msg;
}

function card(p) {
  const li = tpl.content.firstElementChild.cloneNode(true);
  li.querySelector(".name").textContent = p.name;
  li.querySelector(".version").replaceChildren(described("version", p.version));
  li.querySelector(".desc").textContent = p.description;
  const badges = li.querySelector(".badges");
  badges.append(badge(p.source, p.source));
  // flake.lib sets `free = true` on unfree licenses, so match by name.
  if (/unfree/i.test(p.license)) badges.append(badge("unfree", "unfree"));
  const cmd = `nix run ${REPO}#${p.name}`;
  const code = li.querySelector(".cmd code");
  code.textContent = cmd;
  // Scrollable on narrow screens, so it must be focusable.
  code.tabIndex = 0;
  const copy = li.querySelector(".copy");
  copy.setAttribute("aria-label", `Copy nix run command for ${p.name}`);
  copy.addEventListener("click", async () => {
    await navigator.clipboard.writeText(cmd);
    copy.textContent = "Copied";
    announce(`Copied: ${cmd}`);
    setTimeout(() => (copy.textContent = "Copy"), 1500);
  });
  const links = li.querySelector(".links");
  const item = (...nodes) => {
    const el = document.createElement("li");
    el.append(...nodes);
    links.append(el);
  };
  if (p.homepage) item(link(p.homepage, "Homepage", `${p.name} homepage`));
  item(link(`${SRC}/${p.name}/package.nix`, "package.nix", `Nix source for ${p.name}`));
  if (p.hasReadme) item(link(`${SRC}/${p.name}/README.md`, "README", `README for ${p.name}`));
  item(described("license", p.license));
  item(described("platforms", p.platforms.join(", ")));
  return li;
}

function buildChips() {
  const present = new Set(state.pkgs.map((p) => p.category));
  const cats = [
    ...CATEGORY_ORDER.filter((c) => present.has(c)),
    ...[...present].filter((c) => !CATEGORY_ORDER.includes(c)).sort(),
  ];
  const counts = Object.groupBy(state.pkgs, (p) => p.category);
  const mk = (value, label, n) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "chip";
    b.dataset.value = value;
    b.setAttribute("aria-label", `${label}, ${n} packages`);
    b.innerHTML = `${label} <span class="n" aria-hidden="true">${n}</span>`;
    b.addEventListener("click", () => {
      state.category = state.category === value ? "" : value;
      render();
    });
    return b;
  };
  $("#categories").replaceChildren(
    mk("", "All", state.pkgs.length),
    ...cats.map((c) => mk(c, c, counts[c].length)),
  );
}

const res = await fetch("packages.json");
state.pkgs = (await res.json()).map((p) => ({
  ...p,
  _hay: `${p.name} ${p.description} ${p.category} ${p.mainProgram}`.toLowerCase(),
}));
readUrl();
buildChips();
render();
for (const el of [q, platform, source]) el.addEventListener("input", render);
addEventListener("keydown", (e) => {
  if (e.key === "/" && document.activeElement !== q) {
    e.preventDefault();
    q.focus();
  }
});
