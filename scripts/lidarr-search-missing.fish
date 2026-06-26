#!/usr/bin/env fish
# Search Lidarr missing albums one-by-one with a delay to avoid C411 rate limits.
# Requires two port-forwards running before starting this script:
#   kubectl --context=default port-forward -n media svc/lidarr   8686:8686
#   kubectl --context=default port-forward -n media svc/prowlarr 9696:80
#
# Usage:
#   lidarr-search-missing.fish [--auto-grab [--force]] [--fast] [--output FILE] [--limit N]
#
#   (no flags)     search + analyze + write markdown report, no grabs (default)
#   --auto-grab    also POST-grab the best release Lidarr would ACCEPT per album
#                  (approve-only + edition guard: skips live/deluxe/box/reissue/
#                  compilation/remix editions the wanted album doesn't ask for).
#                  This is the safe default — it will NOT grab a release Lidarr
#                  rejected, which is what previously clogged the import queue.
#   --force        with --auto-grab: last-resort override — grab the best
#                  downloadable release even if Lidarr rejected it (import may
#                  still fail). The edition guard still applies. Use sparingly.
#   --fast         original fire-and-forget, 10 s delay, no analysis
#   --output FILE  report path (default: lidarr-report-YYYYMMDD-HHMMSS.md)
#   --limit N      process only first N albums (for testing)

# API keys come from the environment — never hard-code secrets in the repo:
#   set -x LIDARR_API_KEY   <key>
#   set -x PROWLARR_API_KEY <key>
set LIDARR_BASE     (set -q LIDARR_BASE; and echo $LIDARR_BASE; or echo "http://localhost:8686")
set PROWLARR_BASE   (set -q PROWLARR_BASE; and echo $PROWLARR_BASE; or echo "http://localhost:9696")
set LIDARR_APIKEY   $LIDARR_API_KEY
set PROWLARR_APIKEY $PROWLARR_API_KEY
set C411_INDEXER_ID 27   # Prowlarr indexer ID for C411
set LIDARR_APP_ID   6    # Prowlarr app ID for Lidarr

if test -z "$LIDARR_APIKEY" -o -z "$PROWLARR_APIKEY"
    echo "ERROR: set LIDARR_API_KEY and PROWLARR_API_KEY in the environment first, e.g." >&2
    echo "  set -x LIDARR_API_KEY <key>; set -x PROWLARR_API_KEY <key>" >&2
    exit 1
end

set DELAY       10   # seconds between searches (minimum)
set CHECK_EVERY  5   # check indexer health every N searches
set SYNC_WAIT   15   # seconds to wait after triggering Prowlarr sync
set CMD_TIMEOUT 120  # max seconds to wait for a search command to complete

set HELPERS (dirname (status filename))/lidarr-search-helpers.py

# ── parse flags ───────────────────────────────────────────────────────────────

set AUTO_GRAB false
set FORCE     false
set FAST      false
set LIMIT     0
set REPORT_FILE "lidarr-report-"(date +%Y%m%d-%H%M%S)".md"

set _skip false
for idx in (seq (count $argv))
    if $_skip
        set _skip false
        continue
    end
    set arg $argv[$idx]
    set next_idx (math $idx + 1)
    switch $arg
        case --auto-grab
            set AUTO_GRAB true
        case --force
            set FORCE true
        case --fast
            set FAST true
        case --output
            if test $next_idx -gt (count $argv)
                echo "--output requires a value" >&2; exit 1
            end
            set REPORT_FILE $argv[$next_idx]
            set _skip true
        case --limit
            if test $next_idx -gt (count $argv)
                echo "--limit requires a value" >&2; exit 1
            end
            set LIMIT $argv[$next_idx]
            if not string match -qr '^\d+$' -- $LIMIT
                echo "--limit must be a non-negative integer (got: $LIMIT)" >&2; exit 1
            end
            set _skip true
        case '*'
            echo "Unknown flag: $arg" >&2
    end
end

# ── helpers ───────────────────────────────────────────────────────────────────

function is_c411_blocked
    set status_json (curl -sf "$PROWLARR_BASE/api/v1/indexerstatus" \
        -H "X-Api-Key: $PROWLARR_APIKEY")
    if test -z "$status_json"
        return 1  # can't tell — assume fine
    end
    set blocked (echo $status_json | python3 -c \
        "import sys,json; r=json.load(sys.stdin); print('yes' if any(x.get('indexerId')==$C411_INDEXER_ID for x in r) else 'no')" 2>/dev/null)
    test "$blocked" = "yes"
end

function refresh_prowlarr_sync
    echo "  → Triggering Prowlarr ApplicationIndexerSync for Lidarr..."
    curl -sf -X POST "$PROWLARR_BASE/api/v1/command" \
        -H "X-Api-Key: $PROWLARR_APIKEY" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"ApplicationIndexerSync\", \"applicationIds\": [$LIDARR_APP_ID]}" > /dev/null
    echo "  → Waiting $SYNC_WAIT s for sync to propagate..."
    sleep $SYNC_WAIT
end

function ensure_indexer_available
    if is_c411_blocked
        echo "[!] C411 is blocked in Prowlarr — refreshing..."
        refresh_prowlarr_sync
        if is_c411_blocked
            echo "[!] C411 still blocked after sync. Waiting 60s before retrying..."
            sleep 60
            if is_c411_blocked
                echo "[!] C411 still blocked. Continuing anyway — searches may silently fail."
            end
        else
            echo "  → C411 is available again."
        end
    end
end

# Poll a search command until terminal state. Echoes: completed / failed / aborted / timeout
function wait_for_command
    set cmd_id $argv[1]
    set elapsed 0
    while test $elapsed -lt $CMD_TIMEOUT
        set s (curl -sf "$LIDARR_BASE/api/v1/command/$cmd_id" \
            -H "X-Api-Key: $LIDARR_APIKEY" \
            | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null)
        switch $s
            case completed failed aborted
                echo $s
                return
        end
        sleep 3
        set elapsed (math $elapsed + 3)
    end
    echo timeout
end

# Fetch "title\tartist" for an album
function fetch_album_meta
    set album_id $argv[1]
    curl -sf "$LIDARR_BASE/api/v1/album/$album_id" \
        -H "X-Api-Key: $LIDARR_APIKEY" \
        | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("title","?")+"\t"+d.get("artist",{}).get("artistName","?"))' 2>/dev/null
end

# Fetch raw release JSON from Lidarr's 30-min post-search cache
function fetch_releases
    set album_id $argv[1]
    curl -sf "$LIDARR_BASE/api/v1/release?albumId=$album_id" \
        -H "X-Api-Key: $LIDARR_APIKEY"
end

# Classify releases and append report block. Prints outcome.
function analyze_releases
    set album_id   $argv[1]
    set title      $argv[2]
    set artist     $argv[3]
    set rel_json   $argv[4]
    set rfile      $argv[5]
    echo $rel_json | python3 $HELPERS analyze $album_id "$title" "$artist" "$rfile"
end

# Grab the best Lidarr-acceptable release (approve-only + edition guard; with
# $FORCE, falls back to the override set). Prints: ok / failed(CODE) / none
function grab_best_release
    set album_id $argv[1]
    set rel_json $argv[2]
    set title    $argv[3]
    set force_arg $argv[4]

    set payload (echo $rel_json | python3 $HELPERS grab-payload $album_id "$title" $force_arg)
    if test -z "$payload"
        echo none
        return
    end

    set http_code (curl -sf -o /dev/null -w '%{http_code}' -X POST "$LIDARR_BASE/api/v1/release" \
        -H "X-Api-Key: $LIDARR_APIKEY" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if test "$http_code" = "200"
        echo ok
    else
        echo "failed($http_code)"
    end
end

# Print any queue items currently stuck as importFailed (the fallout this script
# previously left behind). Read-only — never deletes anything.
function report_import_failures
    curl -sf "$LIDARR_BASE/api/v1/queue?pageSize=500" \
        -H "X-Api-Key: $LIDARR_APIKEY" \
    | python3 $HELPERS queue-failures
end

# ── fetch missing album IDs ───────────────────────────────────────────────────

set total (curl -sf "$LIDARR_BASE/api/v1/wanted/missing?pageSize=1" \
    -H "X-Api-Key: $LIDARR_APIKEY" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["totalRecords"])')

if test -z "$total"
    echo "ERROR: could not reach Lidarr at $LIDARR_BASE — is the port-forward running?"
    exit 1
end

if test "$total" = "0"
    echo "No missing albums — nothing to do."
    exit 0
end

echo "Missing albums: $total — fetching all IDs..."

set all_ids (curl -sf "$LIDARR_BASE/api/v1/wanted/missing?page=1&pageSize=$total" \
    -H "X-Api-Key: $LIDARR_APIKEY" \
    | python3 -c 'import sys,json; [print(r["id"]) for r in json.load(sys.stdin)["records"]]')

set count (count $all_ids)

if test $LIMIT -gt 0 -a $LIMIT -lt $count
    set all_ids $all_ids[1..$LIMIT]
    set count $LIMIT
    echo "Limiting to first $count albums (--limit $LIMIT)"
end

echo "Loaded $count album IDs."

if $FAST
    echo "Mode: fast (no analysis)"
    echo "Delay: $DELAY s | Indexer check every $CHECK_EVERY | Estimated: "(math $count x $DELAY / 60)" min"
else
    if $AUTO_GRAB; and $FORCE
        echo "Mode: analyze + report + auto-grab --FORCE → $REPORT_FILE"
        echo "[!] --force: will override Lidarr rejections (edition guard still on)."
        echo "    Imports may still fail; check the post-run queue summary."
    else if $AUTO_GRAB
        echo "Mode: analyze + report + auto-grab (approve-only) → $REPORT_FILE"
    else
        echo "Mode: analyze + report (read-only) → $REPORT_FILE"
        if $FORCE
            echo "[!] --force has no effect without --auto-grab."
        end
    end

    printf '# Lidarr Missing Album Report — %s\n\n**Total scanned**: %s  \n\n## Albums Requiring Attention\n\n' \
        (date +"%Y-%m-%d %H:%M:%S") $count > $REPORT_FILE
end
echo ""

ensure_indexer_available

# ── counters ──────────────────────────────────────────────────────────────────

set n_none     0
set n_grabbed  0
set n_rejected 0
set n_temp     0
set n_error    0

# ── main loop ─────────────────────────────────────────────────────────────────

set i 0
for id in $all_ids
    set i (math $i + 1)

    if test (math $i % $CHECK_EVERY) -eq 0
        ensure_indexer_available
    end

    set t_start (date +%s)

    set resp (curl -sf -X POST "$LIDARR_BASE/api/v1/command" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $LIDARR_APIKEY" \
        -d "{\"name\": \"AlbumSearch\", \"albumIds\": [$id]}")

    if test -z "$resp"
        echo "[$i/$count] album $id — WARN: empty response from Lidarr"
        if not $FAST; set n_error (math $n_error + 1); end
        sleep $DELAY
        continue
    end

    if $FAST
        echo "[$i/$count] album $id queued"
        if test $i -lt $count
            sleep $DELAY
        end
        continue
    end

    # ── analysis mode ─────────────────────────────────────────────────────────

    set cmd_id (echo $resp | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
    if test -z "$cmd_id"
        echo "[$i/$count] album $id — WARN: no command id in response"
        set n_error (math $n_error + 1)
        sleep $DELAY
        continue
    end

    set meta (fetch_album_meta $id)
    set album_title (echo $meta | cut -f1)
    set artist_name (echo $meta | cut -f2)

    set cmd_status (wait_for_command $cmd_id)
    set releases_json (fetch_releases $id)

    set outcome (analyze_releases $id "$album_title" "$artist_name" "$releases_json" "$REPORT_FILE")

    switch $outcome
        case none;          set n_none    (math $n_none + 1)
        case grabbed;       set n_grabbed (math $n_grabbed + 1)
        case all_rejected partial; set n_rejected (math $n_rejected + 1)
        case temp_rejected; set n_temp    (math $n_temp + 1)
        case '*';           set n_error   (math $n_error + 1)
    end

    set grab_result ""
    if $AUTO_GRAB; and contains -- $outcome all_rejected partial
        if $FORCE
            set grab_result (grab_best_release $id "$releases_json" "$album_title" force)
        else
            set grab_result (grab_best_release $id "$releases_json" "$album_title" "")
        end
    end

    set label "[$i/$count] \"$album_title\" — $outcome"
    if test -n "$grab_result"
        set label "$label → grab:$grab_result"
    end
    echo $label

    # honour DELAY minus time already spent polling
    set t_end (date +%s)
    set elapsed_s (math $t_end - $t_start)
    set remaining (math $DELAY - $elapsed_s)
    if test $remaining -gt 0 -a $i -lt $count
        sleep $remaining
    end
end

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Done. $count searches sent."

if not $FAST
    python3 $HELPERS patch-report "$REPORT_FILE" $count \
        $n_none $n_grabbed $n_rejected $n_temp $n_error

    echo "No results:   $n_none"
    echo "Grabbed:      $n_grabbed"
    echo "All rejected: $n_rejected"
    echo "Temp blocked: $n_temp"
    echo "Errors:       $n_error"
    echo ""

    if $AUTO_GRAB
        echo "── post-run queue check ──"
        report_import_failures
        echo ""
    end

    echo "Report: $REPORT_FILE"
end
