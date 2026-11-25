#!/usr/bin/env python3
"""Default --auto-update to false in the JS payload embedded in the cortex binary."""

import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()

pattern = re.compile(
    rb'\{name:"auto-update",type:"boolean",description:'
    rb'(?:"(?:\\.|[^"\\])*"|'
    rb"'(?:\\.|[^'\\])*'),"
    rb"default:!0\}"
)
matches = list(pattern.finditer(data))
if len(matches) != 1:
    sys.exit(f"auto-update option not found exactly once (found {len(matches)})")

match = matches[0]
old = match.group(0)
data = data[: match.start()] + old[:-2] + b"1}" + data[match.end() :]

path.write_bytes(data)
