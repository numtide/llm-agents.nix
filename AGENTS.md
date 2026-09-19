# Repository Guidelines

## Project Structure & Module Organization

- Root: `flake.nix`, `flake.lock`, `devshell.nix`, `README.md`.
- Packages live under `packages/<tool>/` with `package.nix`, optional `update.py`, and lockfiles when needed.
- Formatting config: `packages/formatter/treefmt.nix`.
- Utilities and docs: `scripts/`, `docs/`, `.github/`.

## Build, Test, and Development Commands

- Enter dev shell: `nix develop`.
- Build a package: `nix build --accept-flake-config .#<package>` (e.g., `nix build .#claude-code`).
- Run without installing: `nix run .#<package> -- --help`.
- Repo checks (builds + lints): `nix flake check`.
- Format everything: `nix fmt`.
- Regenerate README package section: `./scripts/generate-package-docs.nu`.

## Coding Style & Naming Conventions

- Indentation: 2 spaces; avoid tabs.
- Nix: small, composable derivations; prefer `buildNpmPackage`/`rustPlatform.buildRustPackage`/`stdenv.mkDerivation` as in existing packages.
- File layout per package: `package.nix` (definition), `update.py` (optional custom updater), `nix-update-args` (optional nix-update flags). `package.nix` is called from a scope that contains all in-repo packages and helpers (`buildNpmPackage`, `wrapBuddy`, `formatelf`, `versionCheckHomeHook`, `bun2nixLib`, `platformSource`, `flake`, ...), so declaring one of these names as a function argument is enough.
- Tools via treefmt: nixfmt, deadnix, shfmt, shellcheck, mdformat, yamlfmt, taplo. Always run `nix fmt` before committing.

### Updating Packages

**Prefer `nix-update` over custom update scripts.** Most packages can be updated with:

```bash
nix run nixpkgs#nix-update -- --flake <package>
```

For this to work, `package.nix` must have version/hash attributes inline (not loaded from JSON):

```nix
buildGoModule rec {
  pname = "example";
  version = "1.0.0";  # nix-update finds and updates this

  src = fetchFromGitHub {
    owner = "owner";
    repo = "repo";
    rev = "v${version}";
    hash = "sha256-...";  # nix-update updates this
  };

  subPackages = [ "." ];  # for go find the relevant packages containing the binary

  vendorHash = "sha256-...";  # nix-update updates this too
}
```

**Testing updates**: After writing or modifying a package, verify updates work by:

1. Temporarily downgrading the version in `package.nix`
1. Running `nix run nixpkgs#nix-update -- --flake <package>`
1. Confirming version and hashes are updated correctly

**When nix-update cannot handle the package**, prefer a declarative
`passthru.updater` config (validated by `lib/mk-updater.nix`, executed by
`scripts/updater/run.py`). Kinds: `github-source`, `npm`, `bun-github`,
`platform`, `manifest`, `manifest-checksums`. See migrated packages such as
`packages/claude-code/package.nix` for examples.

Only fall back to a custom `update.py` script when no declarative kind fits
(special hash calculation, unusual upstream APIs). Custom updaters should use
the `scripts/updater/` library.

### Package Metadata Requirements

Every package MUST have proper metadata in `package.nix`:

```nix
meta = with lib; {
  description = "Clear, concise description";
  homepage = "https://project-homepage.com";
  changelog = "https://github.com/owner/repo/releases/tag/v${version}";
  license = licenses.mit; # or licenses.unfree, etc.
  sourceProvenance = with lib.sourceTypes; [ fromSource ];
  maintainers = with maintainers; [ username ];
  mainProgram = "binary-name";
  platforms = platforms.all; # or specific platforms
};
```

### Pinning GitHub Sources by Tag

Use `fetchFromGitHub`'s `tag = "v${version}"`, not `rev = "v${version}"`. `rev`
fetches the ambiguous `archive/v${version}.tar.gz`, which errors when a repo has
a branch and tag of the same name; `tag` uses `refs/tags/` and is hash-identical.
Enforced by an ast-grep rule (see below).

The `changelog` attribute is **required** — our updater uses it to generate release notes. Use a version-specific URL matching the upstream tag format (e.g. `v${version}`, `${version}`, `rust-v${version}`). Fall back to `/releases` when tags are inconsistent. Verify the URL doesn't 404.

### Package Categories

Every package should have a category in `passthru` for README organization:

```nix
passthru.category = "AI Coding Agents";

meta = { ... };
```

Available categories (in display order):

- **AI Coding Agents** - Main AI coding assistants (claude-code, codex, gemini-cli, etc.)
- **AI Assistants** - General-purpose AI assistants not focused on coding (localgpt, openclaw, etc.)
- **Claude Code Ecosystem** - Tools specifically for Claude Code (claudebox, catnip, etc.)
- **ACP Ecosystem** - Agent Control Protocol implementations (claude-code-acp, codex-acp, agent-client-protocol)
- **Usage Analytics** - Usage tracking and analysis tools (ccusage and variants)
- **Workflow & Project Management** - Project/spec management tools (backlog-md, beads, openspec, spec-kit)
- **Code Review** - Code review tools (coderabbit-cli, tuicr)
- **Utilities** - Other useful tools (coding-agent-search, handy, happy-coder, openskills)

#### Custom Maintainers

For maintainers not yet in nixpkgs, define them in `lib/default.nix`:

```nix
{ inputs, ... }:
inputs.nixpkgs.lib.extend (
  _final: prev: {
    maintainers = prev.maintainers // {
      username = {
        github = "github-username";
        githubId = 123456; # Get from: curl -s https://api.github.com/users/username | jq -r '.id'
        name = "Full Name";
      };
    };
  }
)
```

Then in `packages/<package>/package.nix`, declare `flake` as an argument (the
scope provides it) and reference custom maintainers:

```nix
{
  lib,
  flake,
  # ... other args
}:

stdenv.mkDerivation rec {
  # ...
  meta = with lib; {
    maintainers = with flake.lib.maintainers; [ username ];
    # ... other meta
  };
}
```

### Output Layout

A package output must have an FHS-like root. The only entries allowed directly
under `$out` are:

```text
bin sbin lib lib64 libexec share include etc opt Applications nix-support
```

`checks/fhs-layout.nix` enforces this for every attribute of
`packages.<system>`, `passthru.hideFromDocs` ones included.

Anything in the package root also lands in the top level of every profile built
with `pkgs.buildEnv` or home-manager's `home.packages`. Two packages shipping
the same root file name — an `index.js`, a `node`, an `rg` — then collide and
the profile fails to build (#9364).

So put the payload one level down, where only the package itself looks:

- `$out/share/<pname>` for data, JS bundles and unpacked app trees;
- `$out/lib/<pname>` for native libraries that sit next to a binary;
- `$out/libexec/<pname>` for helper executables the main program calls.

Then keep `$out/bin/<mainProgram>` working. A symlink is enough when the
launcher resolves its siblings itself; use a `makeWrapper` wrapper when it
needs the new directory on `PATH`, or when it locates its data relative to
`process.execPath`/`current_exe` and the real path has to be the one it sees.

```nix
installPhase = ''
  runHook preInstall
  mkdir -p $out/bin $out/share
  cp -r dist $out/share/example
  makeWrapper $out/share/example/example $out/bin/example \
    --prefix PATH : $out/share/example
  runHook postInstall
'';
```

### Version Check Hooks

Use `versionCheckHook` to verify packages report correct versions during build:

```nix
doInstallCheck = true;
nativeInstallCheckInputs = [ versionCheckHook ];
```

**For tools that need a writable HOME directory** (many CLI tools try to create config/cache directories), use the in-repo `versionCheckHomeHook`. Declare it as a `package.nix` argument and add it to the install check inputs:

```nix
{
  versionCheckHook,
  versionCheckHomeHook,
  # ...
}:
stdenv.mkDerivation {
  # ...
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
}
```

### Code Signature Check Hook

Upstream macOS binaries that ship with a Developer ID signature can be pinned to
their publisher. `codesignCheckHook` fails the build unless every Mach-O in the
outputs and in `codesignSources` is signed by `codesignTeamId` with a certificate
that chains to Apple's root CA. It runs on Linux too, so pass the darwin
artifacts through `codesignSources`; `platformSource` exposes them as
`darwinSrcs`. Keep `dontStrip = true`: stripping invalidates the signature.

```nix
{
  platformSource,
  versionCheckHook,
  codesignCheckHook,
  # ...
}:
stdenv.mkDerivation {
  # ...
  dontStrip = true;
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    codesignCheckHook
  ];
  codesignTeamId = "433DLLA855";
  codesignSources = source.darwinSrcs;
}
```

Find the team ID with `rcodesign print-signature-info <binary>` (`team_name`).
Ad-hoc or linker-signed binaries (most bun-compiled tools) carry no publisher
and cannot use the hook.

## Linting with ast-grep

Structural lint rules live in `rules/*.yml` (wired via `sgconfig.yml`). Run
`ast-grep scan packages`; the `treefmt` flake check (`checks/treefmt.nix`)
enforces them in CI together with the formatters. Do not duplicate
`checks/meta-completeness.nix` as ast-grep rules: required `meta`/`passthru`
attributes are already enforced at eval time, where overrides and
`hideFromDocs` resolve correctly.

## Testing Guidelines

- Build locally: `nix build .#<package>`.
- Run flake checks: `nix flake check`.
- Per-package checks (when defined): `nix build .#checks.$(nix eval --raw --impure --expr builtins.currentSystem).pkgs-<package>`.
- For scripts, ensure `shellcheck` passes; enable `doCheck = true` in packages when feasible.

## Commit & Pull Request Guidelines

- Commit style mirrors history: `<package>: summary`.
  - Version bumps: `<package>: X -> Y (#123)`; new packages: `<package>: init at X.Y.Z`.
- PRs: clear description, rationale, and testing notes; link issues; include sample run output for CLIs.
- Before pushing: run `nix fmt` and `nix flake check`.

## Security & Configuration Tips

- Some tools are unfree; enable unfree if needed in your Nix config.
- Sandbox experiments: see `packages/claudebox/` for a confined execution wrapper.
- Pin sources with hashes; avoid network access at build time.

## Installing Nix (Required for Package Testing)

When working on package requests or fixes, you MUST install Nix from the official installer to properly test changes,
unless already present

```bash
# Install Nix with daemon mode
sh <(curl -L https://nixos.org/nix/install) --daemon

# Enable flakes and nix-command (required for this repository)
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf

# Restart the Nix daemon to apply changes
if [[ "$OSTYPE" == "darwin"* ]]; then
  sudo launchctl kickstart -k system/org.nixos.nix-daemon
else
  sudo systemctl restart nix-daemon
fi
```

### Common Issues and Solutions

1. **npm packages**: Declare `buildNpmPackage` as a `package.nix` argument; the scope provides the in-repo builder (packages/buildNpmPackage), which is nixpkgs' builder plus an eval-time guard that fails fast with a helpful message when the consumer's nixpkgs predates `fetcherVersion = 2`, instead of a cryptic FOD hash mismatch (#4320). Do not use `pkgs.buildNpmPackage`.

1. **Rust packages with git dependencies**: May fail during cargo vendoring if dependencies have workspace inheritance issues. Consider using pre-built binaries as a workaround.

1. **Binary packages**: When packaging pre-built binaries:

   - Use `dontUnpack = true` if the download is a single executable file
   - Use `autoPatchelfHook` on Linux to handle dynamic library dependencies
   - Common missing libraries: `gcc-unwrapped.lib` for libgcc_s.so.1

1. **Bun-compiled binaries**: Single-file executables produced by `bun build --compile` embed the JS bytecode at the tail of the binary. Stripping corrupts that payload, so always set `dontStrip = true` for bun-compiled tools. Use `coderabbit-cli` as the reference example; other bun-compiled packages in this repo include `amp`, `claude-code`, `cubic`, `opencode`, and `qoder-cli`.

   To detect whether an upstream binary is bun-compiled, run it with the `BUN_BE_BUN` environment variable set — bun-compiled binaries will print bun's CLI usage instead of running the embedded entrypoint:

   ```bash
   BUN_BE_BUN=1 nix run --accept-flake-config path:.#<package>
   ```

   Note: `claude-code` is also bun-compiled, but Anthropic patches the runtime to disable `BUN_BE_BUN`, so this detection trick does not work for it. For every other tool the flag is a reliable indicator.

1. **Update scripts**: Follow shellcheck recommendations - declare and assign variables separately to avoid masking return values.

1. **Custom nix-update arguments**: For packages that need special nix-update flags (e.g., filtering out nightly releases), create a `nix-update-args` file with one argument per line:

   ```text
   # packages/qwen-code/nix-update-args
   --use-github-releases
   --version-regex
   ^v([0-9]+\.[0-9]+\.[0-9]+)$
   ```

   The CI workflow reads this file and passes the arguments to nix-update automatically.
