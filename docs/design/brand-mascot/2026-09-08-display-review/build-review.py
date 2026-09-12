#!/usr/bin/env python3
"""Embed the native Rive PNGs in the offline review page. Does not modify images."""
from pathlib import Path
import base64

root = Path(__file__).resolve().parent
html = (root / "review-template.html").read_text()
poses = ("idle", "holding", "thinking", "concerned", "happy", "wink", "tears", "doze")
for key in (*poses, *(pose + "-white" for pose in poses)):
    token = "__MASCOT_" + key.upper().replace("-", "_") + "_DATA_URI__"
    assert html.count(token) == 1, token
    png = (root / "assets" / (key + ".png")).read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n")
    html = html.replace(token, "data:image/png;base64," + base64.b64encode(png).decode())
assert "__MASCOT_" not in html
(root / "review.html").write_text(html)
print("Wrote offline review.html")
