"""Make the ck-profile helper scripts importable by name in tests.

The scripts are standalone CLIs, not an installed package, so their directory is
prepended to sys.path here once for the whole test session.
"""

import sys
from pathlib import Path

_CKP_SCRIPTS = (
    Path(__file__).resolve().parent.parent.parent / "skills" / "ck-profile" / "scripts"
)
if str(_CKP_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_CKP_SCRIPTS))
