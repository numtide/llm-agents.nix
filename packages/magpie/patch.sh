#!/usr/bin/env bash
# ast-grep metavariables must remain literal.
# shellcheck disable=SC2016

set -euo pipefail

platform=$1
launcher=$2
bun=$3

replace_function() {
  local file=$1 signature=$2 body=$3
  local pattern="func $signature { \$\$\$BODY }"
  ast-grep run --lang go --pattern "$pattern" \
    --rewrite "func $signature { $body }" --update-all "$file"
}

contains() {
  local file=$1 needle=$2
  grep -Fq -- "$needle" "$file" || {
    echo "patch.sh: $file does not contain: $needle" >&2
    exit 1
  }
}

case $platform in
linux)
  # Nix supplies the desktop entry; one written at startup would shadow it
  # and point at the unwrapped binary.
  replace_function internal/gui/scheme_linux.go 'registerScheme() error' 'return nil'

  # Keep AppImage precedence and name the PATH launcher, whose profile
  # symlink survives package updates, without resolving it.
  replace_function internal/autostart/autostart.go 'self() (string, error)' "
		if p := os.Getenv(\"APPIMAGE\"); p != \"\" { return p, nil }
		if p, err := exec.LookPath(\"magpie\"); err == nil { return p, nil }
		return \"$launcher\", nil
	"

  # Repoint entries older versions wrote to a store path; leave disabled
  # entries and custom commands alone.
  replace_function internal/autostart/autostart_other.go 'refresh() error' '
		body, err := os.ReadFile(record())
		if os.IsNotExist(err) { return nil }
		if err != nil { return err }
		lines := strings.Split(string(body), "\n")
		for i, line := range lines {
			key, value, ok := strings.Cut(line, "=")
			if !ok || strings.TrimSpace(key) != "Exec" { continue }
			value = strings.TrimSpace(value)
			if !strings.HasSuffix(value, " " + Arg) { return nil }
			exe := strings.Trim(strings.TrimSuffix(value, " " + Arg), "\"")
			if !strings.HasPrefix(exe, "/nix/store/") || !strings.HasSuffix(exe, "/bin/.magpie-wrapped") && !strings.HasSuffix(exe, "/bin/magpie") { return nil }
			launcher, err := self()
			if err != nil { return err }
			q := strings.NewReplacer("\\", "\\\\", "\"", "\\\"", "\x60", "\\\x60", "$", "\\$").Replace(launcher)
			replacement := "Exec=\"" + q + "\" " + Arg
			if line == replacement { return nil }
			lines[i] = replacement
			return os.WriteFile(record(), []byte(strings.Join(lines, "\n")), 0o644)
		}
		return nil
	'

  # goimports removes the imports the rewritten functions leave unused but
  # needs the new package declared explicitly.
  ast-grep run --lang go --pattern 'import ($$$IMPORTS)' \
    --rewrite 'import ("os/exec"; $$$IMPORTS)' --update-all internal/autostart/autostart.go
  goimports -w internal/gui/scheme_linux.go \
    internal/autostart/autostart.go internal/autostart/autostart_other.go

  # Fail loudly instead of silently leaving the upstream behavior in place.
  contains internal/gui/scheme_linux.go 'func registerScheme() error { return nil }'
  contains internal/autostart/autostart.go 'exec.LookPath("magpie")'
  contains internal/autostart/autostart_other.go 'strings.HasPrefix(exe, "/nix/store/")'
  ;;
darwin)
  # Keep the bundle executable native: an exec wrapper breaks Launch
  # Services tracking, so bake the Bun path into the binary instead.
  ast-grep run --lang go --pattern 'func main() { $$$BODY }' \
    --rewrite 'func main() { os.Setenv("MAGPIE_BUN", "'"$bun"'"); $$$BODY }' --update-all main.go
  ast-grep run --lang go --pattern 'import ($$$IMPORTS)' \
    --rewrite 'import ("os"; $$$IMPORTS)' --update-all main.go
  goimports -w main.go
  contains main.go 'os.Setenv("MAGPIE_BUN"'
  ;;
esac
