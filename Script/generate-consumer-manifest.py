#!/usr/bin/env python3
"""Generate a Package.swift binary-target snippet for the Moreboxed consumer."""

import hashlib
import os
import sys

if len(sys.argv) != 3:
    print("Usage: generate-consumer-manifest.py <artifacts_dir> <base_url>")
    sys.exit(1)

artifacts_dir = sys.argv[1]
base_url = sys.argv[2]

names = [
    "libghostty",
    "MSDisplayLink",
    "GhosttyKit",
    "GhosttyTerminal",
    "GhosttyTheme",
    "ShellCraftKit",
]

lines = ["// Copy these binary targets into ui/Package.swift"]
for name in names:
    zip_name = f"{name}.xcframework.zip"
    path = os.path.join(artifacts_dir, zip_name)
    with open(path, "rb") as f:
        checksum = hashlib.sha256(f.read()).hexdigest()
    lines.append(f"""
        .binaryTarget(
            name: \"{name}\",
            url: \"{base_url}/{zip_name}\",
            checksum: \"{checksum}\"
        ),""")

with open(os.path.join(artifacts_dir, "Package.consumer.swift"), "w") as f:
    f.write("\n".join(lines))

print("[*] wrote Package.consumer.swift")
