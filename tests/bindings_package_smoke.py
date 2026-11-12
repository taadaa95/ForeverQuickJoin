"""Validate the addon keybinding and built GitHub release archive."""
from __future__ import annotations

import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
toc = (ROOT / "ForeverQuickJoin.toc").read_text()
assert not re.search(r"^Bindings\.xml\s*$", toc, re.MULTILINE), "WoW auto-loads Bindings.xml"
root = ElementTree.parse(ROOT / "Bindings.xml").getroot()
assert root.tag == "Bindings"
actions = [node for node in root if node.tag == "Binding"]
assert len(actions) == 1, "Expect one player-configurable toggle action"
binding = actions[0]
assert binding.attrib["name"] == "FOREVERQUICKJOIN_TOGGLE"
assert "header" not in binding.attrib, (
    "Forever's keybinding UI incorrectly shows a separate HEADER_ action"
)
assert "category" not in binding.attrib, (
    "Leave this lone binding under the client's built-in Other category"
)
assert binding.attrib.get("default") == "CTRL-I", "Ctrl+I must be the native default key"
assert (binding.text or "").strip() == "ForeverQuickJoin_ToggleWindow()"
# Default is declarative only; never force-remap or save user keys from Lua.
source = (ROOT / "ForeverQuickJoin.lua").read_text()
assert "BINDING_HEADER_FOREVERQUICKJOIN" not in source, (
    "No legacy header label is needed without the header attribute"
)
assert not re.search(r"\b(?:SetBinding|SetOverrideBinding|SaveBindings)\s*\(", source), (
    "Never overwrite user-managed binding sets programmatically"
)

import sys
sys.path.insert(0, str(ROOT / "scripts"))
from package_release import build
archive, _, tag = build()
with zipfile.ZipFile(archive) as z:
    names = z.namelist()
    assert "ForeverQuickJoin/Bindings.xml" in names, "GitHub ZIP must ship bindings"
    assert "ForeverQuickJoin/ForeverQuickJoin.lua" in names
    assert "ForeverQuickJoin/ForeverQuickJoin.toc" in names
    assert z.testzip() is None
print(f"Native binding/packaging tests passed: {tag}")
