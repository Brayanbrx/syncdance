#!/bin/sh
# Copia de la base de datos (pg_dump, formato custom) y de los archivos subidos
# (videos maestros, referencias y APK) en BACKUP_DIR.
#
#   backup.sh          una copia ahora
#   backup.sh --loop   una copia cada BACKUP_INTERVAL_HOURS (servicio "backup")
#
# Corre en la imagen postgres:16-alpine con las variables de .env.prod.
set -u

BACKUP_DIR="${BACKUP_DIR:-/backups}"
MEDIA_DIR="${MEDIA_DIR:-/uploads}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
BACKUP_INTERVAL_HOURS="${BACKUP_INTERVAL_HOURS:-24}"

export PGHOST="${PGHOST:-postgres}"
export PGUSER="${POSTGRES_USER:?falta POSTGRES_USER}"
export PGPASSWORD="${POSTGRES_PASSWORD:?falta POSTGRES_PASSWORD}"
export PGDATABASE="${POSTGRES_DB:?falta POSTGRES_DB}"

log() {
    printf '{"time":"%s","level":"%s","logger":"backup","message":"%s"%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${3:-}"
}

# Write to a .partial name and rename at the end: a copy that exists is complete.
backup_once() {
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    db="$BACKUP_DIR/db-$stamp.dump"
    media="$BACKUP_DIR/media-$stamp.tar.gz"
    mkdir -p "$BACKUP_DIR" || return 1

    if ! pg_dump --format=custom --file="$db.partial"; then
        rm -f "$db.partial"
        log ERROR "database backup failed"
        return 1
    fi
    mv "$db.partial" "$db"

    if ! tar -czf "$media.partial" -C "$MEDIA_DIR" .; then
        rm -f "$media.partial"
        log ERROR "media backup failed" ",\"database\":\"$db\""
        return 1
    fi
    mv "$media.partial" "$media"

    find "$BACKUP_DIR" -maxdepth 1 -type f \
        \( -name 'db-*.dump' -o -name 'media-*.tar.gz' \) \
        -mtime +"$BACKUP_KEEP_DAYS" -delete
    log INFO "backup done" \
        ",\"database\":\"$db\",\"database_bytes\":$(wc -c < "$db"),\"media\":\"$media\",\"media_bytes\":$(wc -c < "$media")"
}

if [ "${1:-}" = "--loop" ]; then
    while true; do
        backup_once || true
        sleep "$((BACKUP_INTERVAL_HOURS * 3600))"
    done
fi
backup_once
