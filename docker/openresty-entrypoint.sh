#!/usr/bin/env sh
set -eu

OPENRESTY_BIN="${OPENRESTY_BIN:-/usr/local/openresty/bin/openresty}"
OPENRESTY_CONFIG="${OPENRESTY_CONFIG:-/etc/openresty/nginx.conf}"
OPENRESTY_HOT_RELOAD="${OPENRESTY_HOT_RELOAD:-true}"
OPENRESTY_HOT_RELOAD_MODE="${OPENRESTY_HOT_RELOAD_MODE:-poll}"
OPENRESTY_POLL_INTERVAL="${OPENRESTY_POLL_INTERVAL:-2}"
OPENRESTY_WATCH_PATHS="${OPENRESTY_WATCH_PATHS:-/etc/openresty/nginx.conf /etc/openresty/conf.d /etc/openresty/lua}"

log() {
    echo "[openresty-entrypoint] $*"
}

collect_watch_files() {
    for target in $OPENRESTY_WATCH_PATHS; do
        if [ -f "$target" ]; then
            echo "$target"
        elif [ -d "$target" ]; then
            find "$target" -type f | sort
        fi
    done
}

snapshot_watch_files() {
    files="$(collect_watch_files)"
    if [ -z "$files" ]; then
        echo "empty"
        return
    fi

    tmp_file="$(mktemp)"
    echo "$files" | while IFS= read -r file; do
        [ -n "$file" ] && sha256sum "$file"
    done > "$tmp_file"

    digest="$(sha256sum "$tmp_file" | awk '{print $1}')"
    rm -f "$tmp_file"
    echo "$digest"
}

reload_openresty() {
    log "detected config change, validating"
    if "$OPENRESTY_BIN" -t -c "$OPENRESTY_CONFIG"; then
        log "config valid, reloading"
        if ! "$OPENRESTY_BIN" -s reload -c "$OPENRESTY_CONFIG"; then
            log "reload failed"
        fi
    else
        log "config invalid, skip reload"
    fi
}

watch_with_polling() {
    log "hot reload mode=poll interval=${OPENRESTY_POLL_INTERVAL}s"
    last_snapshot="$(snapshot_watch_files)"
    while true; do
        sleep "$OPENRESTY_POLL_INTERVAL"
        current_snapshot="$(snapshot_watch_files)"
        if [ "$current_snapshot" != "$last_snapshot" ]; then
            last_snapshot="$current_snapshot"
            reload_openresty
        fi
    done
}

watch_with_inotify() {
    if ! command -v inotifywait >/dev/null 2>&1; then
        log "inotifywait not found, fallback to poll mode"
        watch_with_polling
        return
    fi

    log "hot reload mode=inotify"
    while inotifywait -qq -r -e modify,create,delete,move $OPENRESTY_WATCH_PATHS; do
        sleep 1
        reload_openresty
    done
}

start_hot_reload() {
    if [ "$OPENRESTY_HOT_RELOAD" != "true" ]; then
        log "hot reload disabled"
        return
    fi

    case "$OPENRESTY_HOT_RELOAD_MODE" in
        inotify)
            watch_with_inotify &
            ;;
        poll)
            watch_with_polling &
            ;;
        auto)
            if command -v inotifywait >/dev/null 2>&1; then
                watch_with_inotify &
            else
                watch_with_polling &
            fi
            ;;
        *)
            log "unsupported hot reload mode: $OPENRESTY_HOT_RELOAD_MODE"
            exit 1
            ;;
    esac
}

log "validating startup config"
"$OPENRESTY_BIN" -t -c "$OPENRESTY_CONFIG"

start_hot_reload

log "starting OpenResty"
exec "$OPENRESTY_BIN" -g "daemon off;" -c "$OPENRESTY_CONFIG"
