#!/usr/bin/env python3
import json
import sys
import tarfile


def main() -> int:
    if len(sys.argv) < 2:
        print("")
        return 0

    har_path = sys.argv[1]
    try:
        with tarfile.open(har_path, "r:gz") as tf:
            member = tf.extractfile("package/oh-package.json5")
            if member is None:
                print("")
                return 0
            manifest = json.loads(member.read().decode("utf-8"))

        name = manifest.get("name")
        version = manifest.get("version")
        if not name or not version:
            print("")
            return 0

        print(f"{name}-{version}.har")
    except Exception:
        print("")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
