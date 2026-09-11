from pathlib import Path
import re
import sys

PROJECT_ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
BUILD_PROFILE = PROJECT_ROOT / "entry" / "build-profile.json5"


def active_rules(path: Path) -> list[str]:
    return [
        line.split("#", 1)[0].strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.split("#", 1)[0].strip()
    ]


def configured_rule_files() -> list[Path]:
    profile = BUILD_PROFILE.read_text(encoding="utf-8")
    matches = re.findall(r'["\']([^"\']*obfuscation-rules[^"\']*)["\']', profile)
    return [(BUILD_PROFILE.parent / match).resolve() for match in matches]


def main() -> int:
    rule_files = configured_rule_files()
    if not rule_files:
        print("FAIL: release obfuscation is enabled without a project rule file")
        return 1

    failures: list[str] = []
    for rule_file in rule_files:
        if not rule_file.is_file():
            failures.append(f"configured rule file does not exist: {rule_file}")
            continue
        if "-enable-property-obfuscation" in active_rules(rule_file):
            failures.append(
                f"{rule_file}: property obfuscation renames server JSON keys "
                "such as error_code, thread_list, and has_more"
            )

    if failures:
        print("FAIL: unsafe release obfuscation configuration")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("PASS: release obfuscation preserves wire-format property names")
    return 0


if __name__ == "__main__":
    sys.exit(main())
