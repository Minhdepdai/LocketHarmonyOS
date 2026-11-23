#!/usr/bin/env python3
"""Automated project integrity verifier for LocketHarmonyOS (HarmonyOS NEXT API 12+)."""

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

SAFE_EMAIL_DOMAINS = {
    "example.com",
    "example.org",
    "example.net",
    "test.com",
    "placeholder.com",
}


def strip_json5_comments(text: str) -> str:
    """Strip // and /* */ comments and trailing commas while preserving strings."""
    out = []
    i = 0
    n = len(text)
    in_str = False
    str_char = ""
    while i < n:
        ch = text[i]
        if in_str:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                i += 1
                out.append(text[i])
            elif ch == str_char:
                in_str = False
            i += 1
            continue

        if ch in ('"', "'"):
            in_str = True
            str_char = ch
            out.append(ch)
            i += 1
        elif ch == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] != "\n":
                i += 1
        elif ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
        else:
            out.append(ch)
            i += 1

    cleaned = "".join(out)
    # Remove trailing commas before } or ]
    cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
    return cleaned


def load_json5(path: Path):
    raw = path.read_text(encoding="utf-8")
    return json.loads(strip_json5_comments(raw))


def collect_resource_refs(obj, refs=None):
    if refs is None:
        refs = []
    if isinstance(obj, dict):
        for v in obj.values():
            collect_resource_refs(v, refs)
    elif isinstance(obj, list):
        for item in obj:
            collect_resource_refs(item, refs)
    elif isinstance(obj, str):
        for m in re.finditer(r"\$(media|string|color|profile):([A-Za-z0-9_]+)", obj):
            refs.append((m.group(1), m.group(2)))
    return refs


def load_element_keys(base_dir: Path, element_type: str) -> set:
    path = base_dir / "element" / f"{element_type}.json"
    if not path.is_file():
        return set()
    data = load_json5(path)
    items = data.get(element_type, [])
    return {item.get("name") for item in items if isinstance(item, dict) and "name" in item}


def media_exists(base_dir: Path, name: str) -> bool:
    media_dir = base_dir / "media"
    if not media_dir.is_dir():
        return False
    for f in media_dir.iterdir():
        if f.is_file() and f.stem == name:
            return True
    return False


def profile_exists(base_dir: Path, name: str) -> bool:
    profile_dir = base_dir / "profile"
    if not profile_dir.is_dir():
        return False
    return (profile_dir / f"{name}.json").is_file()


def check_json_files(errors: list) -> None:
    count = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git", ".hvigor", "oh_modules", "build", ".idea"}]
        for fname in filenames:
            if fname.endswith((".json", ".json5")):
                fpath = Path(dirpath) / fname
                count += 1
                try:
                    load_json5(fpath)
                except Exception as exc:
                    errors.append(f"Invalid JSON/JSON5: {fpath.relative_to(ROOT)} -> {exc}")
    print(f"[CHECK 1] Parsed {count} JSON/JSON5 files.")


def check_resource_references(errors: list) -> None:
    appscope_res = ROOT / "AppScope" / "resources" / "base"
    entry_res = ROOT / "entry" / "src" / "main" / "resources" / "base"

    targets = [
        (ROOT / "AppScope" / "app.json5", [appscope_res]),
        (ROOT / "entry" / "src" / "main" / "module.json5", [entry_res, appscope_res]),
        (entry_res / "profile" / "form_config.json", [entry_res, appscope_res]),
        (entry_res / "media" / "layered_image.json", [entry_res]),
    ]

    ref_count = 0
    for cfg_path, search_dirs in targets:
        if not cfg_path.is_file():
            errors.append(f"Missing required config file: {cfg_path.relative_to(ROOT)}")
            continue
        data = load_json5(cfg_path)
        for res_type, res_name in collect_resource_refs(data):
            ref_count += 1
            found = False
            for rdir in search_dirs:
                if res_type in ("string", "color"):
                    if res_name in load_element_keys(rdir, res_type):
                        found = True
                        break
                elif res_type == "media":
                    if media_exists(rdir, res_name):
                        found = True
                        break
                elif res_type == "profile":
                    if profile_exists(rdir, res_name):
                        found = True
                        break
            if not found:
                errors.append(
                    f"Unresolved resource reference ${res_type}:{res_name} in {cfg_path.relative_to(ROOT)}"
                )
    print(f"[CHECK 2] Verified {ref_count} resource references ($media/$string/$color/$profile).")


def check_pages_and_widgets(errors: list) -> None:
    entry_main = ROOT / "entry" / "src" / "main"
    main_pages_path = entry_main / "resources" / "base" / "profile" / "main_pages.json"
    form_config_path = entry_main / "resources" / "base" / "profile" / "form_config.json"

    checked = 0
    if main_pages_path.is_file():
        pages_data = load_json5(main_pages_path)
        for page in pages_data.get("src", []):
            checked += 1
            ets_path = entry_main / "ets" / f"{page}.ets"
            if not ets_path.is_file():
                errors.append(f"Missing page file for main_pages.json entry '{page}': {ets_path.relative_to(ROOT)}")
            else:
                content = ets_path.read_text(encoding="utf-8")
                if "@Entry" not in content:
                    errors.append(f"Page file missing @Entry decorator: {ets_path.relative_to(ROOT)}")
    else:
        errors.append("Missing entry/src/main/resources/base/profile/main_pages.json")

    if form_config_path.is_file():
        form_data = load_json5(form_config_path)
        for form in form_data.get("forms", []):
            src = form.get("src", "")
            checked += 1
            rel = src[2:] if src.startswith("./") else src
            ets_path = entry_main / rel
            if not ets_path.is_file():
                errors.append(f"Missing widget card file for form '{form.get('name')}': {ets_path.relative_to(ROOT)}")
            else:
                content = ets_path.read_text(encoding="utf-8")
                if "@Entry" not in content:
                    errors.append(f"Widget card missing @Entry decorator: {ets_path.relative_to(ROOT)}")
    else:
        errors.append("Missing entry/src/main/resources/base/profile/form_config.json")

    print(f"[CHECK 3] Checked {checked} page/widget @Entry targets.")


def check_png_files(errors: list) -> None:
    png_count = 0
    for base in (ROOT / "AppScope" / "resources", ROOT / "entry" / "src" / "main" / "resources"):
        if not base.is_dir():
            continue
        for fpath in base.rglob("*.png"):
            png_count += 1
            with fpath.open("rb") as f:
                magic = f.read(8)
            if magic != PNG_MAGIC:
                errors.append(f"Invalid PNG magic bytes: {fpath.relative_to(ROOT)}")
    if png_count == 0:
        errors.append("No PNG media assets found in resources directories.")
    print(f"[CHECK 4] Verified {png_count} PNG files have valid magic headers.")


def check_no_hardcoded_credentials(errors: list) -> None:
    email_re = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
    jwt_re = re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")
    scanned = 0

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git", ".hvigor", "oh_modules", "build", ".idea", "__pycache__"}]
        for fname in filenames:
            if fname.endswith((".png", ".jpg", ".jpeg", ".webp", ".hap", ".app", ".pyc")):
                continue
            fpath = Path(dirpath) / fname
            if fpath == Path(__file__).resolve():
                continue
            scanned += 1
            try:
                content = fpath.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue

            for m in email_re.finditer(content):
                domain = m.group(1).lower()
                if domain not in SAFE_EMAIL_DOMAINS:
                    errors.append(
                        f"Possible real email address '{m.group(0)}' in {fpath.relative_to(ROOT)}"
                    )

            if jwt_re.search(content):
                errors.append(f"Possible hardcoded JWT/auth token in {fpath.relative_to(ROOT)}")

    print(f"[CHECK 5] Scanned {scanned} text files for hardcoded credentials/tokens.")


def main() -> int:
    errors: list[str] = []
    check_json_files(errors)
    check_resource_references(errors)
    check_pages_and_widgets(errors)
    check_png_files(errors)
    check_no_hardcoded_credentials(errors)

    if errors:
        print("\nVERIFICATION FAILED:")
        for err in errors:
            print(f"  - {err}")
        return 1

    print("\nALL CHECKS PASSED!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
