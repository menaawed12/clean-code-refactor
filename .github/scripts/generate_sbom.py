#!/usr/bin/env python3
"""Writes a CycloneDX 1.6 SBOM for a clean-code-refactor release package.

The package has no third-party runtime dependencies, so the SBOM describes the package
itself and every file it ships, with SHA-256 hashes. Output is reproducible: the
timestamp comes from --timestamp (the tagged commit's time) and the serial number is
derived from the repository and version.

Usage: generate_sbom.py --package-zip FILE --version X.Y.Z --repository OWNER/NAME
                        --timestamp EPOCH_SECONDS --output FILE
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import uuid
import zipfile
from datetime import datetime, timezone


def file_components(package_zip: str) -> list[dict]:
    components = []
    with zipfile.ZipFile(package_zip) as archive:
        for info in sorted(archive.infolist(), key=lambda item: item.filename):
            if info.is_dir():
                continue
            # Drop the archive's top-level folder so names match the repository layout.
            name = info.filename.split("/", 1)[1] if "/" in info.filename else info.filename
            digest = hashlib.sha256(archive.read(info)).hexdigest()
            components.append({
                "type": "file",
                "bom-ref": f"file:{name}",
                "name": name,
                "hashes": [{"alg": "SHA-256", "content": digest}],
            })
    return components


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package-zip", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--timestamp", required=True, type=int)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository):
        parser.error("--version must be MAJOR.MINOR.PATCH and --repository OWNER/NAME")

    purl = f"pkg:github/{args.repository}@v{args.version}"
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, purl)}",
        "version": 1,
        "metadata": {
            "timestamp": datetime.fromtimestamp(args.timestamp, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tools": {"components": [{"type": "application", "name": "generate_sbom.py", "version": args.version}]},
            "component": {
                "type": "application",
                "bom-ref": purl,
                "name": "clean-code-refactor",
                "version": args.version,
                "purl": purl,
                "licenses": [{"license": {"id": "MIT"}}],
                "externalReferences": [{"type": "vcs", "url": f"https://github.com/{args.repository}"}],
            },
        },
        "components": file_components(args.package_zip),
        "dependencies": [{"ref": purl, "dependsOn": []}],
    }
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(bom, handle, indent=2)
        handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
