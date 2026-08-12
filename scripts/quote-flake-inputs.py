#!/usr/bin/env python3
"""Treefmt formatter: quote the attribute after `inputs.`.

Rewrites `inputs.nixpkgs` to `inputs."nixpkgs"` in .nix files.

A plain regex would also hit comments and strings, so this walks the
file with a minimal Nix lexer and only rewrites in code context.
Interpolations (`inputs.${...}`) and already-quoted names are left
alone, which makes the rewrite idempotent.
"""

import re
import sys
from pathlib import Path

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_'-]*")


class Rewriter:
    """Single-pass rewriter over one Nix source file."""

    def __init__(self, text: str) -> None:
        """Set up the cursor and context stack for one file."""
        self.text = text
        self.out: list[str] = []
        self.i = 0
        # Context stack. "code" at the bottom; strings push themselves,
        # interpolations push "code" again. Interpolation depth rides
        # on the brace counter stack.
        self.ctx: list[str] = ["code"]
        self.braces: list[int] = []

    def run(self) -> str:
        """Walk the whole file and return the rewritten text."""
        handlers = {
            "code": self.code,
            "dquote": self.dquote,
            "indent": self.indent,
        }
        while self.i < len(self.text):
            handlers[self.ctx[-1]]()
        return "".join(self.out)

    def emit(self, n: int) -> None:
        """Copy n chars to the output verbatim."""
        self.out.append(self.text[self.i : self.i + n])
        self.i += n

    def emit_until(self, marker: str, skip: int) -> None:
        """Copy verbatim up to and including the next marker."""
        j = self.text.find(marker, self.i + skip)
        j = len(self.text) if j == -1 else j + len(marker)
        self.out.append(self.text[self.i : j])
        self.i = j

    def enter_interpolation(self) -> None:
        """Push a code context for a ${...} interpolation."""
        self.ctx.append("code")
        self.braces.append(0)
        self.emit(2)

    def code(self) -> None:
        """Handle one token in code context."""
        t, i = self.text, self.i
        if t[i] == "#":
            # line comments run to EOL, minus the newline itself
            self.emit_until("\n", 1)
            if self.out[-1].endswith("\n"):
                self.out[-1] = self.out[-1][:-1]
                self.i -= 1
            return
        if t.startswith("/*", i):
            self.emit_until("*/", 2)
            return
        if t[i] == '"':
            self.ctx.append("dquote")
            self.emit(1)
            return
        if t.startswith("''", i):
            self.ctx.append("indent")
            self.emit(2)
            return
        if t[i] in "{}":
            self.brace(t[i])
            return
        m = IDENT.match(t, i)
        if m:
            self.ident(m)
            return
        self.emit(1)

    def brace(self, c: str) -> None:
        """Track interpolation depth for { and }."""
        if self.braces:
            if c == "{":
                self.braces[-1] += 1
            elif self.braces[-1] == 0:
                # end of interpolation, back into the string
                self.braces.pop()
                self.ctx.pop()
            else:
                self.braces[-1] -= 1
        self.emit(1)

    def ident(self, m: re.Match[str]) -> None:
        """Quote the attribute that follows an `inputs.` token."""
        t, i = self.text, self.i
        prev = t[i - 1] if i > 0 else ""
        boundary = not (prev.isalnum() or prev in "_'-")
        end = m.end()
        if m.group(0) == "inputs" and boundary and t[end : end + 1] == ".":
            nm = IDENT.match(t, end + 1)
            if nm:
                self.out.append(f'inputs."{nm.group(0)}"')
                self.i = nm.end()
                return
        self.emit(end - i)

    def dquote(self) -> None:
        """Handle one token inside a "..." string."""
        t, i = self.text, self.i
        if t[i] == "\\":
            self.emit(2)
        elif t.startswith("${", i):
            self.enter_interpolation()
        elif t[i] == '"':
            self.ctx.pop()
            self.emit(1)
        else:
            self.emit(1)

    def indent(self) -> None:
        """Handle one token inside an ''...'' string."""
        t, i = self.text, self.i
        if t.startswith("''$", i) or t.startswith("'''", i):
            self.emit(3)
        elif t.startswith("${", i):
            self.enter_interpolation()
        elif t.startswith("''", i):
            self.ctx.pop()
            self.emit(2)
        else:
            self.emit(1)


def main() -> None:
    """Rewrite each file given on the command line in place."""
    for arg in sys.argv[1:]:
        path = Path(arg)
        text = path.read_text()
        new = Rewriter(text).run()
        if new != text:
            path.write_text(new)


if __name__ == "__main__":
    main()
