#!/usr/bin/env python3
"""Recheck exact App source APIs and the asset's feedback interruption routes.

Usage: python3 verify-app-runtime.py /path/to/RiveRuntime.xcframework/macos-arm64_x86_64
Uses an already downloaded official 6.25.1 framework; never builds or starts the App.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

audit_dir = Path(__file__).resolve().parent
repo = audit_dir.parents[4]
framework_dir = Path(sys.argv[1]).resolve()
compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
info = plistlib.loads((framework_dir / "RiveRuntime.framework/Resources/Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == "6.25.1"
source_names = ["MascotBehaviorState", "MascotController", "MascotPalette", "MascotRuntime", "BrandMascotView"]
sources = [repo / "Together/Features/BrandMascot" / f"{name}.swift" for name in source_names]
runtime_source = sources[3].read_text()
drain = [float(value) for value in re.findall(r"rive.stateMachine.advance\(by: ([\d.]+)\)", runtime_source)]
assert drain == [0, 2, 0.1, 0.1], "Update the asset interruption fixture if the production drain changes."
evidence = {
    "createdAt": datetime.now(timezone.utc).isoformat(),
    "runtimeVersion": info["CFBundleShortVersionString"],
    "compiler": compiler,
    "sdk": sdk,
    "newRuntimeVerification": "Typecheck exact production View/Runtime/Palette/Controller/Behavior against the official macOS framework, MainActor default isolation and complete concurrency checks.",
    "feedbackVerification": "Execute the official inspection API against the same exported asset to observe core state changes. This trace fixture is not the App's New Runtime adapter.",
    "sourceSHA256": {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
    "limits": ["No full iOS App build, device, rendering, touch, or energy validation.", "New Runtime APIs are compiler checked; the state-name traces use the SDK inspection API."],
}
with tempfile.TemporaryDirectory(prefix="together-rive-api-", dir="/private/tmp") as scratch:
    temp = Path(scratch)
    command = [compiler, "-sdk", sdk, "-typecheck", "-parse-as-library", "-swift-version", "5",
               "-default-isolation", "MainActor", "-strict-concurrency=complete", "-F", str(framework_dir),
               "-module-cache-path", str(temp / "modules"), *map(str, sources)]
    typecheck = subprocess.run(command, capture_output=True, text=True)
    evidence["newRuntimeTypecheck"] = {
        "passed": typecheck.returncode == 0,
        "command": command,
        "diagnostics": typecheck.stdout + typecheck.stderr,
    }
    if typecheck.returncode == 0:
        executable = temp / "feedback-audit"
        subprocess.run([compiler, "-sdk", sdk, str(audit_dir / "feedback-interruption-audit.swift"),
                        "-o", str(executable), "-F", str(framework_dir), "-framework", "RiveRuntime",
                        "-Xlinker", "-rpath", "-Xlinker", str(framework_dir),
                        "-module-cache-path", str(temp / "modules")], check=True)
        feedback = subprocess.run([
            str(executable), str(repo / "Together/Resources/BrandMascot/together_sphere_motion_study.riv"),
            str(audit_dir / "feedback-interruption-verification.json")], capture_output=True, text=True)
        evidence["feedbackInterruption"] = {"passed": feedback.returncode == 0, "output": feedback.stdout + feedback.stderr}
    evidence["passed"] = typecheck.returncode == 0 and evidence.get("feedbackInterruption", {}).get("passed", False)
(audit_dir / "new-runtime-api-verification.json").write_text(json.dumps(evidence, indent=2) + "\n")
print(json.dumps({"newRuntimeTypecheck": evidence["newRuntimeTypecheck"]["passed"],
                  "feedbackInterruption": evidence.get("feedbackInterruption"),
                  "passed": evidence["passed"]}, indent=2))
sys.exit(0 if evidence["passed"] else 1)
