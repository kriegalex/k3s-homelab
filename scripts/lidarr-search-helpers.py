#!/usr/bin/env python3
"""
Helper script for lidarr-search-missing.fish.
All dynamic values come via sys.argv; JSON data comes via stdin.

Subcommands:
  analyze ALBUM_ID TITLE ARTIST RFILE         < releases.json  → prints outcome
  grab-payload ALBUM_ID [ALBUM_TITLE] [FORCE] < releases.json  → prints grab JSON or empty
  patch-report RFILE TOTAL N_NONE N_GRABBED N_REJECTED N_TEMP N_ERROR

grab-payload FORCE: pass "force" to allow overriding Lidarr's rejections
(last resort). Default is approve-only. ALBUM_TITLE drives the edition guard.
"""
import sys
import json
import re


# Edition / variant markers. A release carrying one of these is skipped unless
# the wanted album title carries it too — this is what stops live recordings,
# deluxe/box/reissue sets and greatest-hits comps from being grabbed for the
# plain studio album (the dominant import-failure cause). Lidarr release JSON
# has no per-release track count, so this keyword guard + Lidarr's own
# `approved` flag are the practical filter.
EDITION_MARKERS = [
    "live", "deluxe", "remix", "remixes", "box", "coffret", "quad",
    "immersion", "redux", "rebuilt", "anthology", "essential",
    "greatest hits", "b-sides", "bsides", "reissue", "instrumental",
    "karaoke", "demos",
]


def _rank(r):
    return (r.get("customFormatScore") or 0, r.get("seeders") or 0)


def _edition_mismatch(release_title, album_title):
    """True if the release title advertises an edition the wanted album does not."""
    rt = (release_title or "").lower()
    at = (album_title or "").lower()
    for marker in EDITION_MARKERS:
        # word-boundary match so "live" doesn't trip on "Oliver", etc.
        if re.search(r"\b" + re.escape(marker) + r"\b", rt) and marker not in at:
            return True
    return False


def best_grabbable(releases, album_title=""):
    """Releases Lidarr would accept on its own (not rejected + downloadable),
    minus any whose title advertises an edition the wanted album doesn't."""
    return sorted(
        [
            r for r in releases
            if not r.get("rejected")
            and r.get("downloadAllowed")
            and not _edition_mismatch(r.get("title"), album_title)
        ],
        key=_rank,
        reverse=True,
    )


def best_override(releases, album_title=""):
    """Best downloadable release *ignoring* Lidarr's rejection rules — last
    resort, only via --force, to grab when Lidarr rejected everything. Still
    requires downloadAllowed and still honours the edition guard, since forcing
    a live/box/deluxe grab is exactly what clogged the import queue before."""
    return sorted(
        [
            r for r in releases
            if r.get("downloadAllowed")
            and not _edition_mismatch(r.get("title"), album_title)
        ],
        key=_rank,
        reverse=True,
    )


def _reasons(r):
    out = []
    for x in (r.get("rejections") or []):
        if isinstance(x, str):
            out.append(x)
        elif isinstance(x, dict):
            out.append(x.get("reason", "?"))
        else:
            out.append(str(x))
    return "; ".join(out) or "—"


def cmd_analyze(album_id, title, artist, rfile):
    try:
        releases = json.load(sys.stdin)
    except Exception:
        releases = []

    if not releases:
        print("none")
        with open(rfile, "a") as f:
            f.write(f"- **{title}** — {artist} (id: {album_id}): _no results_\n")
        return

    grabbed      = [r for r in releases if not r.get("rejected") and r.get("downloadAllowed")]
    temp_blocked = [r for r in releases if r.get("temporarilyRejected")]
    rejected     = [r for r in releases if r.get("rejected") and not r.get("temporarilyRejected")]

    if grabbed:
        outcome = "grabbed"
    elif temp_blocked and not rejected:
        outcome = "temp_rejected"
    elif rejected:
        outcome = "all_rejected"
    else:
        outcome = "partial"

    print(outcome)

    if outcome in ("all_rejected", "partial", "temp_rejected"):
        with open(rfile, "a") as f:
            f.write(f'\n### "{title}" — {artist} (id: {album_id})\n\n')
            f.write("| Release | Indexer | MB | Seeds | Status | Rejections |\n")
            f.write("|---------|---------|-----|-------|--------|------------|\n")
            for r in releases:
                name    = (r.get("title") or "?")[:60]
                indexer = r.get("indexer") or "?"
                size_mb = round((r.get("size") or 0) / 1_048_576)
                seeds   = r.get("seeders") or 0
                if r.get("temporarilyRejected"):
                    status = "temp-blocked"
                elif r.get("rejected"):
                    status = "rejected"
                elif r.get("approved"):
                    status = "approved"
                else:
                    status = "unknown"
                reasons = _reasons(r)
                f.write(f"| {name} | {indexer} | {size_mb} | {seeds} | {status} | {reasons} |\n")

            candidates = best_override(releases, title)
            if candidates:
                best = candidates[0]
                payload = json.dumps({
                    "guid": best["guid"],
                    "indexerId": best["indexerId"],
                    "albumId": album_id,
                })
                f.write("\n**Best override candidate** (grab only with "
                        "`--auto-grab --force`, within 30 min of search — Lidarr "
                        "rejected it, so import may still fail):\n")
                f.write(f"`POST /api/v1/release` → `{payload}`\n\n")


def cmd_grab_payload(album_id, album_title="", force=False):
    try:
        releases = json.load(sys.stdin)
    except Exception:
        print("")
        return

    # Default: only grab releases Lidarr would accept (approve-only + edition
    # guard). --force falls back to the override set when nothing is acceptable.
    candidates = best_grabbable(releases, album_title)
    if not candidates and force:
        candidates = best_override(releases, album_title)
    if not candidates:
        print("")
        return

    best = candidates[0]
    print(json.dumps({
        "guid": best["guid"],
        "indexerId": best["indexerId"],
        "albumId": album_id,
    }))


def cmd_queue_failures():
    """Read a Lidarr /api/v1/queue payload from stdin and list importFailed items."""
    try:
        recs = json.load(sys.stdin).get("records", [])
    except Exception:
        return
    bad = [r for r in recs if r.get("trackedDownloadState") == "importFailed"]
    if not bad:
        print("Queue import failures: 0 — clean.")
        return
    print(f"Queue import failures: {len(bad)} (will NOT auto-import — review/clear):")
    for r in bad:
        msgs = []
        for sm in (r.get("statusMessages") or []):
            msgs += (sm.get("messages") or [])
        why = "; ".join(dict.fromkeys(msgs))[:80] if msgs else "?"
        title = (r.get("title") or "?")[:55]
        print(f"  - [{r.get('id')}] {title} — {why}")


def cmd_patch_report(rfile, total, n_none, n_grabbed, n_rejected, n_temp, n_error):
    summary = (
        f"**No results**: {n_none} | **Grabbed**: {n_grabbed} | "
        f"**All rejected**: {n_rejected} | **Temp blocked**: {n_temp} | **Errors**: {n_error}"
    )
    placeholder = f"**Total scanned**: {total}  "
    with open(rfile, "r") as f:
        content = f.read()
    content = content.replace(placeholder, placeholder + "\n" + summary)
    with open(rfile, "w") as f:
        f.write(content)


if __name__ == "__main__":
    subcmd = sys.argv[1] if len(sys.argv) > 1 else ""

    if subcmd == "analyze":
        cmd_analyze(int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5])

    elif subcmd == "grab-payload":
        album_title = sys.argv[3] if len(sys.argv) > 3 else ""
        force = len(sys.argv) > 4 and sys.argv[4] == "force"
        cmd_grab_payload(int(sys.argv[2]), album_title, force)

    elif subcmd == "queue-failures":
        cmd_queue_failures()

    elif subcmd == "patch-report":
        cmd_patch_report(sys.argv[2], sys.argv[3], sys.argv[4],
                         sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8])

    else:
        print(f"Unknown subcommand: {subcmd}", file=sys.stderr)
        sys.exit(1)
