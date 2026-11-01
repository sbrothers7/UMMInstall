#!/usr/bin/env python3
"""Validate mods.json and keep its GitHub-hosted entries on their newest release.

    update_mods.py check             validate mods.json (syntax + fields)
    update_mods.py update [REPORT]   bump tracked entries, rewrite mods.json, and
                                     write broken links to REPORT (deleted if none)
    update_mods.py selftest          offline tests

Tracking fields on an entry (all optional; entries without them are left alone):
    repo        "owner/name" whose releases feed `url`
    asset       regex matched against that release's asset names
    assetMelon  regex for `urlMelon` (same repo unless repoMelon is set)
    repoMelon   repo for `urlMelon` when the MelonLoader build lives elsewhere
    prerelease  true to accept pre-releases (alpha-only mods)
The script writes `url` + `version` and `urlMelon` + `versionMelon`. `urlV2`
pins and non-GitHub links are never rewritten, only checked.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

MODS_JSON = os.path.join(os.path.dirname(__file__), "..", "..", "mods.json")

# (url field, repo field, asset field, version field)
TRACKS = [
    ("url", "repo", "asset", "version"),
    ("urlMelon", "repoMelon", "assetMelon", "versionMelon"),
]
LINK_FIELDS = ("url", "urlV2", "urlMelon")
STR_FIELDS = {"id", "slug", "url", "urlV2", "urlMelon", "install", "repo", "asset",
              "assetMelon", "repoMelon", "version", "versionMelon"}
BOOL_FIELDS = {"v2", "v3", "jalib", "prerelease"}


def validate(data):
    """Returns a list of problems; empty means the file is usable by the apps."""
    if not isinstance(data, dict) or not isinstance(data.get("mods"), list):
        return ['top level must be {"mods": [...]}']
    errors, seen, seen_slugs = [], set(), set()
    for i, m in enumerate(data["mods"]):
        where = f"mods[{i}]"
        if not isinstance(m, dict):
            errors.append(f"{where}: not an object")
            continue
        where = f"mods[{i}] ({m.get('id', '?')})"
        for key in ("id", "url"):
            if not isinstance(m.get(key), str) or not m[key]:
                errors.append(f"{where}: missing {key}")
        if m.get("id") in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(m.get("id"))
        slug = m.get("slug")
        if not isinstance(slug, str) or not slug:
            errors.append(f"{where}: missing slug")
        elif not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", slug):
            errors.append(f"{where}: bad slug {slug!r}")
        elif slug in seen_slugs:
            errors.append(f"{where}: duplicate slug")
        else:
            seen_slugs.add(slug)
        for key, value in m.items():
            if key in STR_FIELDS and not isinstance(value, str):
                errors.append(f"{where}: {key} must be a string")
            elif key in BOOL_FIELDS and not isinstance(value, bool):
                errors.append(f"{where}: {key} must be true/false")
            elif key not in STR_FIELDS | BOOL_FIELDS:
                errors.append(f"{where}: unknown field {key}")
        for _, repo_key, asset_key, _ in TRACKS:
            pattern = m.get(asset_key)
            if not isinstance(pattern, str):
                continue
            if not (m.get(repo_key) or m.get("repo")):
                errors.append(f"{where}: {asset_key} needs repo")
            try:
                re.compile(pattern)
            except re.error as e:
                errors.append(f"{where}: bad {asset_key} regex: {e}")
    return errors


def pick(releases, pattern, prerelease):
    """Newest eligible release's matching asset -> (version, url), or an error string."""
    for r in releases:
        if r.get("draft") or (r.get("prerelease") and not prerelease):
            continue
        tag = r["tag_name"]
        for a in r.get("assets", []):
            if re.search(pattern, a["name"]):
                return re.sub(r"^[vV](?=\d)", "", tag), a["browser_download_url"]
        return f"release {tag} has no asset matching {pattern!r}"
    return "no eligible release"


def fetch_releases(repo):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/releases?per_page=20",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "mods-json-bot"})
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def probe(url):
    """None if url downloads a zip, else a short reason."""
    req = urllib.request.Request(url, headers={"Range": "bytes=0-3", "User-Agent": "mods-json-bot"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            if r.read(4) != b"PK\x03\x04":
                return f"not a zip ({r.headers.get_content_type()})"
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code}"
    except Exception as e:
        return str(e)
    return None


def update(data, fetch=fetch_releases, check=probe):
    """Bumps tracked entries in place. Returns (changed, problems)."""
    changed, problems, cache, checked = False, [], {}, {}

    def check_once(url):
        if url not in checked:
            checked[url] = check(url)
        return checked[url]

    for m in data["mods"]:
        for url_key, repo_key, asset_key, ver_key in TRACKS:
            repo, pattern = m.get(repo_key) or m.get("repo"), m.get(asset_key)
            if not (repo and pattern):
                continue
            try:
                if repo not in cache:
                    cache[repo] = fetch(repo)
                result = pick(cache[repo], pattern, m.get("prerelease", False))
            except Exception as e:
                result = f"couldn't read releases of {repo}: {e}"
            if isinstance(result, str):
                problems.append(f"{m['id']} `{url_key}`: {result}")
                continue
            version, url = result
            if (m.get(url_key), m.get(ver_key)) == (url, version):
                continue
            err = check_once(url)
            if err:
                problems.append(f"{m['id']} `{url_key}`: new release {version} not usable ({err}), kept old link")
                continue
            m[url_key], m[ver_key] = url, version
            changed = True

    for m in data["mods"]:
        for key in LINK_FIELDS:
            if m.get(key) and (err := check_once(m[key])):
                problems.append(f"{m['id']} `{key}`: {err} — {m[key]}")
    return changed, problems


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "check"
    if cmd == "selftest":
        selftest()
        print("selftest ok")
        return 0
    try:
        data = load(MODS_JSON)
    except json.JSONDecodeError as e:
        print(f"mods.json is not valid JSON: {e}")
        return 1
    errors = validate(data)
    for e in errors:
        print(f"error: {e}")
    if errors:
        return 1
    if cmd == "check":
        print(f"mods.json ok ({len(data['mods'])} mods)")
        return 0
    if cmd != "update":
        print(__doc__)
        return 2

    changed, problems = update(data)
    if changed:
        with open(MODS_JSON, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
    print("mods.json updated" if changed else "mods.json already current")
    report = argv[2] if len(argv) > 2 else None
    for p in problems:
        print(f"problem: {p}")
    if report:
        if problems:
            with open(report, "w", encoding="utf-8") as f:
                f.write("The daily mods.json check found these problems:\n\n")
                f.writelines(f"- {p}\n" for p in problems)
        elif os.path.exists(report):
            os.remove(report)
    return 0


def selftest():
    rel = lambda tag, names, pre=False: {
        "tag_name": tag, "prerelease": pre, "draft": False,
        "assets": [{"name": n, "browser_download_url": f"https://dl/{tag}/{n}"} for n in names]}
    releases = [rel("v2.0.0-a1", ["Mod.zip"], pre=True), rel("v1.2.0", ["Mod.zip", "ModMelon.zip"])]

    assert pick(releases, r"^Mod\.zip$", False) == ("1.2.0", "https://dl/v1.2.0/Mod.zip")
    assert pick(releases, r"^Mod\.zip$", True) == ("2.0.0-a1", "https://dl/v2.0.0-a1/Mod.zip")
    assert pick(releases, r"Other", False).startswith("release v1.2.0 has no asset")
    assert pick([rel("latest-alpha", ["Mod.zip"])], "Mod", False)[0] == "latest-alpha"

    assert validate({"mods": [{"id": "A", "slug": "a", "url": "u"}]}) == []
    assert validate({"mods": [{"id": "A", "slug": "a"}]}) == ["mods[0] (A): missing url"]
    assert any("duplicate id" in e for e in validate({"mods": [{"id": "A", "slug": "a", "url": "u"}] * 2}))
    assert validate({"mods": [{"id": "A", "url": "u"}]}) == ["mods[0] (A): missing slug"]
    assert any("bad slug" in e for e in validate({"mods": [{"id": "A", "slug": "Abc", "url": "u"}]}))
    assert any("duplicate slug" in e for e in validate({"mods": [{"id": "A", "slug": "a", "url": "u"}, {"id": "B", "slug": "a", "url": "u"}]}))
    assert any("regex" in e for e in validate({"mods": [{"id": "A", "url": "u", "slug": "a", "repo": "o/r", "asset": "("}]}))
    assert any("unknown field" in e for e in validate({"mods": [{"id": "A", "url": "u", "slug": "a", "urll": "x"}]}))

    data = {"mods": [
        {"id": "A", "url": "https://dl/v1.0.0/Mod.zip", "repo": "o/a", "asset": r"^Mod\.zip$",
         "assetMelon": "Melon", "urlMelon": "old"},
        {"id": "B", "url": "https://dl/v1.0.0/B.zip", "repo": "o/b", "asset": "B"},
        {"id": "C", "url": "https://dead"},
    ]}
    fetch = {"o/a": releases, "o/b": [rel("v9", ["B.zip"])]}.__getitem__
    bad = {"https://dl/v9/B.zip": "HTTP 404", "https://dead": "HTTP 404"}
    changed, problems = update(data, fetch=fetch, check=bad.get)
    a, b = data["mods"][0], data["mods"][1]
    assert changed
    assert (a["url"], a["version"]) == ("https://dl/v1.2.0/Mod.zip", "1.2.0")
    assert (a["urlMelon"], a["versionMelon"]) == ("https://dl/v1.2.0/ModMelon.zip", "1.2.0")
    assert b["url"] == "https://dl/v1.0.0/B.zip" and "version" not in b  # broken new release: kept old
    assert any(p.startswith("B `url`: new release 9 not usable") for p in problems)
    assert any(p.startswith("C `url`: HTTP 404") for p in problems)
    assert update(data, fetch=fetch, check=bad.get)[0] is False  # second run is a no-op


if __name__ == "__main__":
    sys.exit(main(sys.argv))
