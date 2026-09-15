#!/usr/bin/env python3
"""
Archive a third-party skill repo at an exact commit.

Guard rails, each because the first draft of this got it wrong:
  * NO rm -rf anywhere. A destination that already holds something other than a
    matching PROVENANCE.json is refused, not cleared. The first draft did
    `rm -rf "$DEST/skills"` with $DEST built from an argument — one typo'd
    argument and it deletes the wrong tree.
  * The destination is RESOLVED and must sit under the vendor root. A path that
    escapes it (../ and friends) is refused.
  * No git. Downloads the tarball at a pinned SHA, so there is no clone, no
    remote, and nothing that can be mistaken for operating on a real checkout.
  * A LICENSE must be present in the source, or nothing is written. MIT requires
    the notice travel with the copy; a copy without it is not licensed.
"""
import io, json, pathlib, shutil, sys, tarfile, urllib.request
from datetime import date, timezone, datetime

VENDOR_ROOT = pathlib.Path(
    "/Users/meirpro/git/meirpro-dotfiles/claude/vendored-skills"
).resolve()
LICENSE_NAMES = ("LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE")


def vendor(repo: str, sha: str, name: str, fork: str, tarball: str) -> None:
    dest = (VENDOR_ROOT / name).resolve()
    if VENDOR_ROOT not in dest.parents:
        sys.exit(f"REFUSED: {dest} escapes the vendor root")

    if dest.exists():
        prov = dest / "PROVENANCE.json"
        if not prov.is_file():
            sys.exit(f"REFUSED: {dest} exists but has no PROVENANCE.json — "
                     "not clearing a directory this script did not create")
        if json.loads(prov.read_text()).get("source", "").rsplit("/", 2)[-2:] != repo.split("/"):
            sys.exit(f"REFUSED: {dest} holds a different source")

    # Downloaded by curl beforehand, NOT fetched here: Homebrew python is
    # denied outbound by Little Snitch on this machine and fails with a bare
    # EBADF, which reads like a code bug and is not one.
    print(f"→ {repo} @ {sha[:9]}")
    raw = pathlib.Path(tarball).read_bytes()
    tf = tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz")
    top = tf.getnames()[0].split("/")[0]

    staged = {}
    lic = None
    for m in tf.getmembers():
        if not m.isfile():
            continue
        rel = pathlib.PurePosixPath(m.name).relative_to(top)
        parts = rel.parts
        if parts and parts[0] == "skills":
            staged[rel] = tf.extractfile(m).read()
        elif len(parts) == 1 and parts[0] in LICENSE_NAMES and lic is None:
            lic = tf.extractfile(m).read()

    if lic is None:
        sys.exit("REFUSED: no LICENSE in the source — a copy without the "
                 "notice is not licensed")
    if not staged:
        sys.exit("REFUSED: no skills/ directory found in the source")

    # Only now do we touch disk, and only by writing files.
    for rel, data in staged.items():
        out = dest / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
    (dest / "LICENSE").write_bytes(lic)

    count = len([d for d in (dest / "skills").iterdir() if d.is_dir()])
    (dest / "PROVENANCE.json").write_text(json.dumps({
        "source": f"https://github.com/{repo}",
        "fork": fork,
        "commit": sha,
        "vendoredAt": date.today().isoformat(),
        "vendoredAtUtc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "license": "MIT",
        "skillCount": count,
        "why": ("Archived so these survive the upstream repo being deleted, made "
                "private, or moved behind a paywall. A COPY at a pinned commit — "
                "not a live mirror, and not automatically trusted."),
        "howToUpdate": [
            f"gh repo sync {fork} --source {repo}",
            f"gh api repos/{repo}/compare/{sha}...main --jq '.files[].filename'",
            "READ THE DIFF. A skill is an instruction the agent will follow.",
            "Only then re-run vendor_skills.py with the new SHA.",
        ],
    }, indent=2) + "\n")
    print(f"  ✓ {count} skills → {dest}")


if __name__ == "__main__":
    vendor("emilkowalski/skills",
           "85e8e2363b713506e1d5b6e07a0eb2da66be1bc3",
           "emilkowalski-skills", "meirpro/skills",
           "/private/tmp/claude-501/-Users-meirpro-git-hayom/225869f9-7c05-4f5c-9831-2b4d5e3ecbba/scratchpad/emil.tgz")
    vendor("Leonxlnx/taste-skill",
           "ccbc15639c97057cbfcf32ecebc38ef716e4bb37",
           "taste-skill", "meirpro/taste-skill",
           "/private/tmp/claude-501/-Users-meirpro-git-hayom/225869f9-7c05-4f5c-9831-2b4d5e3ecbba/scratchpad/taste.tgz")
