#!/bin/sh
# Restaurar o comprobar una copia de ops/backup.sh.
#
#   restore.sh --verify /backups/db-AAAAMMDD-HHMMSS.dump
#       Restaura en una base temporal, cuenta usuarios, rutinas y prácticas, y
#       la borra. No toca la base real: sirve para probar las copias.
#
#   restore.sh /backups/db-....dump [/backups/media-....tar.gz]
#       Reemplaza la base real (y los archivos subidos, si se indica el .tar.gz).
#       Detener antes backend, celery y celery-beat (ver ops/README.md).
set -eu

export PGHOST="${PGHOST:-postgres}"
export PGUSER="${POSTGRES_USER:?falta POSTGRES_USER}"
export PGPASSWORD="${POSTGRES_PASSWORD:?falta POSTGRES_PASSWORD}"
export PGDATABASE="${POSTGRES_DB:?falta POSTGRES_DB}"
MEDIA_DIR="${MEDIA_DIR:-/uploads}"

if [ "${1:-}" = "--verify" ]; then
    dump="${2:?indica el archivo .dump}"
    check_db="restore_check_$(date -u +%s)"
    createdb "$check_db"
    trap 'dropdb --if-exists "$check_db"' EXIT
    pg_restore --no-owner --exit-on-error --dbname="$check_db" "$dump"
    psql --dbname="$check_db" --tuples-only --no-align --command "
        SELECT 'usuarios=' || (SELECT count(*) FROM accounts_user)
            || ' rutinas=' || (SELECT count(*) FROM routines_routine)
            || ' practicas=' || (SELECT count(*) FROM training_dancesession);"
    echo "Copia válida: $dump"
    exit 0
fi

dump="${1:?indica el archivo .dump}"
pg_restore --clean --if-exists --no-owner --exit-on-error --dbname="$PGDATABASE" "$dump"
echo "Base restaurada desde $dump"

if [ -n "${2:-}" ]; then
    find "$MEDIA_DIR" -mindepth 1 -delete
    tar -xzf "$2" -C "$MEDIA_DIR"
    echo "Archivos restaurados desde $2"
fi
