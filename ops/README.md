# Operación en producción

Un servidor Linux con Docker y `docker-compose.prod.yml`:

| Servicio | Función |
| --- | --- |
| `caddy` | HTTPS con certificado automático; único punto expuesto (80 y 443) |
| `web` | nginx: landing, panel y entrada a Django (`/api`, `/admin`, `/static`) |
| `backend` | Django con gunicorn; aplica migraciones al arrancar |
| `celery`, `celery-beat` | Procesamiento de videos maestros y tareas periódicas |
| `postgres`, `redis` | Datos y cola, sin puertos expuestos |
| `backup` | Copia diaria de la base y de los archivos subidos en `./backups` |

No crea la cuenta `admin/admin`: esa semilla solo corre con DEBUG.

## Requisitos

- Un dominio con un registro A hacia el servidor y los puertos 80 y 443 abiertos.
- Al menos 4 GB de RAM: procesar videos con MediaPipe es lo más pesado
  (`CELERY_CONCURRENCY=1` procesa uno a la vez).

## Primer despliegue

```sh
git clone https://github.com/Brayanbrx/syncdance.git && cd syncdance
cp .env.prod.example .env.prod   # completar: dominio, secretos, correo
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml exec backend python manage.py createsuperuser
curl https://TU-DOMINIO/api/health/   # {"status":"ok", ..., "environment":"production"}
```

Generar secretos: `python -c "import secrets; print(secrets.token_urlsafe(50))"`.

Instalar el catálogo. Sin el último comando, la sección **Cantar** de la app
queda vacía. Los tres crean solo lo que falta y se pueden repetir:

```sh
docker compose -f docker-compose.prod.yml exec backend python manage.py load_default_catalog
docker compose -f docker-compose.prod.yml exec backend python manage.py generate_standard_catalog
docker compose -f docker-compose.prod.yml exec backend python manage.py generate_singing_catalog
```

## Actualizar

```sh
git pull
docker compose -f docker-compose.prod.yml up -d --build
```

Las migraciones corren solas al reiniciar `backend`.

## Logs

```sh
docker compose -f docker-compose.prod.yml logs -f backend celery
```

Una línea JSON por evento, con identificadores como `reference_id`,
`task_id` o `session_id`.

## Privacidad y términos

`/privacidad` y `/terminos` muestran el responsable (`LEGAL_CONTROLLER`) y el
correo de contacto (`LEGAL_CONTACT_EMAIL`) definidos en `.env.prod`;
`check --deploy` avisa si falta el correo. El registro guarda qué versión de
los textos aceptó cada persona (`LEGAL_TERMS_VERSION` en
`backend/config/settings/base.py`): al cambiar los textos, subir esa versión.
Los textos son un borrador a revisar con asesoría legal antes del lanzamiento.

## Correo

La recuperación de contraseña envía un enlace por SMTP. Variables en
`.env.prod`: `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`,
`EMAIL_HOST_PASSWORD`, `EMAIL_USE_TLS` y `DEFAULT_FROM_EMAIL`. El enlace apunta
a `https://SYNCDANCE_DOMAIN` (o a `PUBLIC_WEB_URL`, si se define).

## Copias de seguridad

El servicio `backup` guarda cada `BACKUP_INTERVAL_HOURS` (24 h por defecto),
en `./backups`:

- `db-AAAAMMDD-HHMMSS.dump`: la base completa (`pg_dump`, formato custom)
- `media-AAAAMMDD-HHMMSS.tar.gz`: videos maestros, referencias y APK

Borra las de más de `BACKUP_KEEP_DAYS` días (14 por defecto). Cada copia
escribe una línea JSON `backup done` con los tamaños en el log del servicio.

**Las copias en el mismo servidor no protegen si se pierde el servidor.**
Copiar `./backups` a otro lugar cada día (otra máquina, almacenamiento de
objetos) es parte de la operación. Se define al elegir el hosting.

### Probar una copia (sin tocar la base real)

```sh
docker compose -f docker-compose.prod.yml exec backup \
  sh /ops/restore.sh --verify /backups/db-AAAAMMDD-HHMMSS.dump
# usuarios=… rutinas=… practicas=…   Copia válida: …
```

Restaura en una base temporal, cuenta registros y la borra. Hacerlo al menos
una vez al mes.

### Restaurar

Reemplaza los datos actuales por los de la copia:

```sh
C="docker compose -f docker-compose.prod.yml"
$C stop backend celery celery-beat
$C run --rm -v syncdance-prod_media:/restore-uploads -e MEDIA_DIR=/restore-uploads \
  backup sh /ops/restore.sh /backups/db-AAAAMMDD-HHMMSS.dump /backups/media-AAAAMMDD-HHMMSS.tar.gz
$C start backend celery celery-beat
```

Sin el `.tar.gz` solo restaura la base. En Git Bash (Windows), anteponer
`MSYS_NO_PATHCONV=1` para que no convierta las rutas `/ops/...` y `/backups/...`.

## Probar la pila de producción en una laptop

```sh
# .env.prod con SYNCDANCE_DOMAIN=localhost y
# DJANGO_CSRF_TRUSTED_ORIGINS=https://localhost:8443
HTTP_PORT=8880 HTTPS_PORT=8443 docker compose -f docker-compose.prod.yml up -d --build
curl -k https://localhost:8443/api/health/
docker compose -f docker-compose.prod.yml down -v   # borra solo esta pila de prueba
```

Caddy usa su propia autoridad local para `localhost` (`curl -k`). La pila de
desarrollo (`docker-compose.yml`, puerto 8085) es otro proyecto y no se toca.

## Pendiente (al elegir el hosting)

- Almacenamiento de objetos para videos y APK, si el disco del servidor no alcanza.
- Copia diaria de `./backups` fuera del servidor.
- Monitoreo de errores (por ejemplo, Sentry) en Django, Celery y la app, sin
  imágenes, landmarks ni datos personales.
