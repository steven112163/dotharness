"""Make the ck-profile helpers importable by name in tests.

User-callable CLIs (ckAggregate, ckDepgraph) live in bin/.
Pure libs and data (gpu_specs, html_report, parse_resource_usage, etc.) live in
lib/ck-profile/. Both are added to sys.path so tests can import by module name.
"""

import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent.parent
_BIN = _REPO / "bin"
_LIB = _REPO / "lib" / "ck-profile"

for _p in (_LIB, _BIN):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))
