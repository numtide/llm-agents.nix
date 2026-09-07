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
const results = $("#results");
const tpl = $("#card");

const state = { category: "", open: "", pkgs: [] };

function readUrl() {
  const p = new URLSearchParams(location.search);
  q.value = p.get("q") ?? "";
  state.category = p.get("category") ?? "";
  platform.value = p.get("platform") ?? "";
  state.open = p.get("pkg") ?? "";
}

function writeUrl() {
  const p = new URLSearchParams();
  if (q.value) p.set("q", q.value);
  if (state.category) p.set("category", state.category);
  if (platform.value) p.set("platform", platform.value);
  if (state.open) p.set("pkg", state.open);
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

const moduleSnippet = (attr, name) => `# flake.nix
inputs.llm-agents.url = "${REPO}";

# configuration module
{ inputs, pkgs, ... }:
{
  ${attr} = [
    inputs.llm-agents.packages.\${pkgs.stdenv.hostPlatform.system}.${name}
  ];
}`;

const INSTALL = [
  { id: "run", label: "Run", snippet: (n) => `nix run ${REPO}#${n}` },
  { id: "shell", label: "Shell", snippet: (n) => `nix shell ${REPO}#${n}` },
  { id: "nixos", label: "NixOS", snippet: (n) => moduleSnippet("environment.systemPackages", n) },
  { id: "hm", label: "Home Manager", snippet: (n) => moduleSnippet("home.packages", n) },
];

// Same method across all cards, like search.nixos.org.
let method = INSTALL.some((i) => i.id === localStorage.getItem("install-method"))
  ? localStorage.getItem("install-method")
  : "run";

function installPanel(p) {
  const box = document.createElement("div");
  box.className = "install";
  const tabs = document.createElement("div");
  tabs.setAttribute("role", "tablist");
  tabs.setAttribute("aria-label", `Install ${p.name}`);
  const pre = document.createElement("pre");
  const code = document.createElement("code");
  // Scrollable, so it must be focusable.
  code.tabIndex = 0;
  pre.append(code);
  pre.setAttribute("role", "tabpanel");
  const copy = document.createElement("button");
  copy.type = "button";
  copy.className = "copy";
  copy.textContent = "Copy";

  const select = (id) => {
    method = id;
    localStorage.setItem("install-method", id);
    const m = INSTALL.find((i) => i.id === id);
    code.textContent = m.snippet(p.name);
    copy.setAttribute("aria-label", `Copy ${m.label} instructions for ${p.name}`);
    for (const b of tabs.children) {
      const on = b.dataset.id === id;
      b.setAttribute("aria-selected", on);
      b.tabIndex = on ? 0 : -1;
    }
  };
  for (const m of INSTALL) {
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("role", "tab");
    b.dataset.id = m.id;
    b.textContent = m.label;
    b.addEventListener("click", () => {
      // Switch every open card so the choice sticks visibly.
      document.querySelectorAll(".install").forEach((el) => el._select(m.id));
    });
    b.addEventListener("keydown", (e) => {
      const i = INSTALL.findIndex((x) => x.id === method);
      const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (!d) return;
      e.preventDefault();
      const next = INSTALL[(i + d + INSTALL.length) % INSTALL.length].id;
      document.querySelectorAll(".install").forEach((el) => el._select(next));
      tabs.querySelector(`[data-id="${next}"]`).focus();
    });
    tabs.append(b);
  }
  copy.addEventListener("click", async () => {
    await navigator.clipboard.writeText(code.textContent);
    copy.textContent = "Copied";
    announce(`Copied ${INSTALL.find((i) => i.id === method).label} instructions for ${p.name}`);
    setTimeout(() => (copy.textContent = "Copy"), 1500);
  });
  box._select = select;
  select(method);
  const bar = document.createElement("div");
  bar.className = "bar";
  bar.append(tabs, copy);
  box.append(bar, pre);
  return box;
}

function card(p) {
  const li = tpl.content.firstElementChild.cloneNode(true);
  const toggle = li.querySelector(".name button");
  toggle.textContent = p.name;
  li.querySelector(".version").replaceChildren(described("version", p.version));
  li.querySelector(".desc").textContent = p.description;
  const links = li.querySelector(".links");
  const item = (...nodes) => {
    const el = document.createElement("li");
    el.append(...nodes);
    links.append(el);
  };
  if (p.homepage) item(link(p.homepage, "Homepage", `${p.name} homepage`));
  item(link(`${SRC}/${p.name}/package.nix`, "package.nix", `Nix source for ${p.name}`));
  if (p.hasReadme) item(link(`${SRC}/${p.name}/README.md`, "README", `README for ${p.name}`));
  item(described("platforms", p.platforms.join(", ")));

  let panel = null;
  const open = (on) => {
    toggle.setAttribute("aria-expanded", on);
    li.classList.toggle("open", on);
    if (on && !panel) {
      panel = installPanel(p);
      panel.id = `install-${p.name}`;
      toggle.setAttribute("aria-controls", panel.id);
      li.append(panel);
    }
    if (panel) panel.hidden = !on;
  };
  toggle.addEventListener("click", () => {
    const on = toggle.getAttribute("aria-expanded") !== "true";
    state.open = on ? p.name : "";
    open(on);
    writeUrl();
  });
  open(state.open === p.name);
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

// Reuse the cache-busting query from our own URL for packages.json.
const res = await fetch(`packages.json${new URL(import.meta.url).search}`);
state.pkgs = (await res.json()).map((p) => ({
  ...p,
  _hay: `${p.name} ${p.description} ${p.category} ${p.mainProgram}`.toLowerCase(),
}));
readUrl();
buildChips();
render();
for (const el of [q, platform]) el.addEventListener("input", render);
addEventListener("keydown", (e) => {
  if (e.key === "/" && document.activeElement !== q) {
    e.preventDefault();
    q.focus();
  }
});
