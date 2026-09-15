"""Length-preserving edits to the JS payload embedded in the cortex binary.

- The version parser only accepts execPath under ~/.local/share/cortex/<v>;
  drop that prefix guard so $out/share/cortex/<v> is recognised.
- Default --auto-update to false.
"""

import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()

ident = rb"[A-Za-z_$][A-Za-z0-9_$]*"
guard = re.compile(rb"if\((" + ident + rb")\.startsWith\(" + ident + rb"\+" + ident + rb"\.sep\)\)\{")
(m,) = guard.finditer(data)
repl = b"if(" + m.group(1) + b"){"
data = data[: m.start()] + repl.ljust(len(m.group(0)), b";") + data[m.end() :]

old = b'description:"Auto-update on launch (use --no-auto-update to disable)",default:!0}'
assert data.count(old) == 1, "auto-update option not found exactly once"
data = data.replace(old, old[:-2] + b"1}")

path.write_bytes(data)
