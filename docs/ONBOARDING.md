# Guía de onboarding

Esta guía es para quien llega nuevo al repo: estudiante del curso, colaborador o tú mismo dentro de seis meses. En una tarde deberías poder correr la app en tu máquina, entender por dónde pasa un roast y hacer un cambio que llegue a producción.

Si solo quieres ver la arquitectura, empieza por el [README](../README.md). Aquí vamos a lo práctico.

## 1. Lo que necesitas

| Herramienta | Para qué | Versión probada |
|---|---|---|
| [uv](https://docs.astral.sh/uv/) | Python de `web` y `worker` (instala Python 3.12 solo) | 0.8+ |
| Node.js | Frontend (Vite + React) | 24 |
| `gcloud` | Todo lo que toca GCP | reciente |
| Terraform | Solo si vas a usar la carpeta `terraform/` | 1.7+ |

Para trabajar en local **no necesitas cuenta de GCP**. Para desplegar necesitas rol de owner (o equivalente) en el proyecto y, si vas a usar URLs de LinkedIn, un token de Apify.

## 2. Mapa del repo

```
roastfolio/
├── frontend/          React + Vite + Tailwind. Se compila a estáticos que viven en el bucket site
│   └── src/
│       ├── Home.tsx       formulario: PDF o URL, intensidad, consentimiento
│       ├── RoastPage.tsx  pantalla de espera y resultado
│       └── useRoast.ts    polling a GET /api/roasts/{id} cada 2 s
├── web/               API pública (FastAPI en Cloud Run)
│   └── app/
│       ├── main.py        rutas: /api/roasts, /api/roasts/{id}, /r/{id}
│       ├── validation.py  límites del PDF y normalización de la URL de LinkedIn
│       ├── queue.py       crea la tarea en Cloud Tasks con token OIDC
│       └── store.py       Firestore + Storage (o archivos locales)
├── worker/            pipeline (FastAPI en Cloud Run, privado)
│   └── app/
│       ├── main.py        POST /internal/process, lo llama Cloud Tasks
│       ├── pipeline.py    máquina de estados y reintentos
│       ├── extract.py     Document AI (PDF) y Apify (LinkedIn)
│       ├── ai.py          prompts y llamadas a Gemini y Nano Banana
│       ├── card.py        convierte el certificado a JPEG 1200×630
│       └── log.py         logs JSON (las métricas dependen de ellos)
├── infra/             scripts gcloud numerados, idempotentes
├── terraform/         la misma infraestructura, declarativa
├── docs/              esta guía, costos y diagramas
└── cloudbuild.yaml    CI/CD: tests → imágenes → Cloud Run → bucket site
```

Dos servicios de Python con dependencias separadas a propósito: la imagen de `web` no carga Document AI ni `google-genai`, y la del `worker` no carga Cloud Tasks. Cada uno tiene su `pyproject.toml`, su `uv.lock` y su `Dockerfile`.

## 3. Correr todo en tu máquina

Dos variables cambian el comportamiento:

- `LOCAL_MODE=1`: Firestore y Storage se reemplazan por archivos en `.localdata/`.
- `MOCK_AI=1` (solo `worker`): Document AI, Apify, Gemini y Nano Banana se reemplazan por respuestas fijas. El certificado se dibuja con Pillow.

Abre tres terminales:

```bash
# 1. worker
cd worker && LOCAL_MODE=1 MOCK_AI=1 LOCAL_DATA_DIR=../.localdata uv run uvicorn app.main:app --port 8081

# 2. web (en local llama directo al worker en vez de usar Cloud Tasks)
cd web && LOCAL_MODE=1 LOCAL_DATA_DIR=../.localdata WORKER_URL=http://localhost:8081 uv run uvicorn app.main:app --port 8080

# 3. frontend (Vite hace proxy de /api y /cards hacia :8080)
cd frontend && npm install && npm run dev
```

Abre http://localhost:5173, sube cualquier PDF de una página y deberías ver pasar los estados hasta el certificado de prueba.

¿Quieres probar con IA real? Quita `MOCK_AI` del worker y autentícate con `gcloud auth application-default login`. Vertex AI y Document AI usarán tus credenciales.

### Tests

```bash
(cd web && uv run pytest) && (cd worker && uv run pytest) && (cd frontend && npm test)
```

Son los mismos que corre Cloud Build antes de desplegar. Si fallan en tu máquina, van a fallar en el pipeline.

## 4. El recorrido de un roast, en el código

Sigue un roast de principio a fin y tendrás el 80 % de la app en la cabeza.

1. **`frontend/src/Home.tsx`** arma un `multipart/form-data` con el PDF (o la URL), la intensidad y el consentimiento, y hace `POST /api/roasts`.
2. **`web/app/main.py` → `create_roast`** valida con `validation.py` (≤ 5 MB, ≤ 5 páginas, URL de perfil de LinkedIn), sube el PDF a `uploads`, crea `roasts/{id}` con `status: queued` y `expiresAt = ahora + 24 h`, y llama a `queue.py`.
3. **`web/app/queue.py`** crea una tarea HTTP en la cola `roasts` que apunta a `WORKER_URL/internal/process`, firmada con un token OIDC de `sa-tasks`.
4. **`worker/app/main.py`** recibe la tarea. Cloud Tasks manda el número de intento en un header, y el worker se lo pasa al pipeline.
5. **`worker/app/pipeline.py`** avanza `extracting → roasting → rendering → done`. Antes de cada paso revisa si el resultado ya está guardado. Así un reintento no vuelve a pagar Document AI ni Gemini.
6. **`frontend/src/useRoast.ts`** consulta el estado cada 2 s. En cuanto existe `result`, muestra el roast aunque el certificado siga en camino.
7. **`/r/{id}`** devuelve el `index.html` del sitio con meta tags Open Graph. Por eso el link compartido muestra el certificado como vista previa.

### Errores: permanentes o reintentables

Esta es la regla más importante del worker:

- **`PermanentError`** (en `worker/app/errors.py`): no tiene sentido reintentar. PDF ilegible, perfil de LinkedIn privado, contenido bloqueado por los filtros de seguridad. El roast pasa a `failed` con un mensaje para el usuario y el worker responde 200 para que Cloud Tasks no insista.
- **Cualquier otra excepción**: se asume pasajera (un 503 de Vertex, un timeout). El worker responde 500 y Cloud Tasks reintenta con backoff. En el último de los 4 intentos, el roast pasa a `failed` con un mensaje genérico.

Si agregas una llamada nueva a un servicio externo, decide a cuál de los dos grupos pertenece cada error.

## 5. Cambios comunes

**Ajustar el tono del roast.** Los prompts viven en `worker/app/ai.py`: `ROAST_SYSTEM`, `TONES` (uno por intensidad) y `CARD_PROMPT` con `CARD_STYLES`. `clean_result` recorta lo que el modelo devuelva de más (nombre ≤ 25 caracteres, titular ≤ 8 palabras, apertura ≤ 90 palabras, 3 a 5 `burns` con cita textual, 3 `tips` con `before`/`after`) y convierte un "después" vacío en "Bórralo del perfil.". El roast corre con `thinking_level=low` (`GEMINI_THINKING_LEVEL`): tarda ~10 s contra ~30 s con el razonamiento por defecto, sin perder calidad en las pruebas. Corre el worker con IA real para probar; los mocks no te dirán nada del tono.

**Cambiar de modelo.** `GEMINI_TEXT_MODEL` y `GEMINI_IMAGE_MODEL` son variables de entorno del worker, definidas en `infra/09-run.sh`.

**Cambiar configuración de runtime** (variables, memoria, concurrencia, service account). Va en `infra/09-run.sh` (y en `terraform/run.tf`). `cloudbuild.yaml` solo cambia la imagen, a propósito: así un push no puede cambiar permisos ni configuración sin que se note en la revisión de infra.

**Agregar un campo al resultado.** Toca el esquema `ROAST_SCHEMA` y `clean_result` en `ai.py`, el tipo en `frontend/src/api.ts` y la vista en `RoastPage.tsx`. Si el campo debe salir en la vista previa, también `render_share_page` en `web/app/main.py`.

**Agregar o cambiar un log.** Usa `log()` o `step()` de `worker/app/log.py`. No cambies los valores de `event` (`roast_queued`, `roast_done`, `roast_failed`, `step_finished`) sin actualizar `infra/12-observability.sh`: las métricas basadas en logs filtran por ellos.

## 6. Desplegar

### El día a día

Haz push a `main`. El trigger `roastfolio-main` de Cloud Build corre, en este orden:

1. Los tests de web, worker y frontend, en paralelo.
2. El build de las imágenes, que suben a Artifact Registry con `:BUILD_ID` y `:latest`.
3. El deploy del worker y de web en Cloud Run, y la copia del frontend al bucket `site`.

Sigue el build en la consola: Cloud Build → Historial (región `us-central1`), o con:

```bash
gcloud builds list --region=us-central1 --limit=3
```

Si un test falla, no se despliega nada.

### Desde cero en un proyecto nuevo

Tienes dos caminos que llegan al mismo lugar:

- **Scripts** (`infra/NN-*.sh`): imperativos, uno por servicio, fáciles de leer en clase. El orden está en el [README](../README.md#despliegue-desde-cero).
- **Terraform** (`terraform/`): declarativo, con `plan` antes de cada cambio. Instrucciones en [terraform/README.md](../terraform/README.md).

En los dos hay dos pasos que no se pueden automatizar:

1. **El token de Apify** entra a Secret Manager a mano, sin pasar por ningún archivo:
   ```bash
   printf '%s' 'apify_api_...' | gcloud secrets versions add apify-token --data-file=-
   ```
2. **La conexión con GitHub** necesita que alguien autorice la GitHub App de Cloud Build en el navegador. El script `13-build-trigger.sh` imprime el link. Después hay que volver a correrlo.

El certificado HTTPS tarda entre 15 y 60 minutos en quedar `ACTIVE` la primera vez. Mientras tanto el navegador muestra error de certificado. Es normal.

## 7. Depurar en producción

Cada línea de log trae `roastId`, así que casi todo empieza por ahí.

```bash
# Todo lo que pasó con un roast
gcloud logging read 'jsonPayload.roastId="<id>"' --freshness=1d --format='value(timestamp,jsonPayload.step,jsonPayload.message)'

# Roasts fallidos en la última hora
gcloud logging read 'jsonPayload.event="roast_failed"' --freshness=1h --format='value(jsonPayload.roastId,jsonPayload.error)'

# ¿Hay tareas atoradas en la cola?
gcloud tasks list --queue=roasts --location=us-central1
```

El documento del roast (estado, error, resultado) se ve en la consola: Firestore → base `roastfolio` → colección `roasts`.

En Cloud Monitoring hay un dashboard llamado **Roastfolio** con roasts por hora, latencia p95 por paso y cache hit ratio del CDN. La alerta "tasa de error > 10 % (15 min)" manda correo.

| Síntoma | Causa probable |
|---|---|
| Todos los roasts por URL fallan, los de PDF funcionan | El secreto `apify-token` no tiene versión habilitada, o el token venció |
| `429` al crear roasts | Cloud Armor: más de 5 `POST /api/roasts` por IP en 10 minutos. Es a propósito |
| El `*.run.app` de web responde 404 | Correcto: web solo acepta tráfico que llega por el Load Balancer |
| Un certificado viejo sigue apareciendo tras borrarse | El CDN lo guarda hasta 1 hora. La API ya lo trata como expirado |
| Roast en `rendering` por varios minutos | Nano Banana está lento o fallando. Revisa los logs del paso `rendering`; Cloud Tasks reintentará |

## 8. Convenciones

- **Código en inglés, interfaz en español** (de Guatemala, con "tú").
- **Logs en JSON a stdout**, con `roastId`, `step`, `event` y `durationMs`.
- **Nada de llaves JSON de service accounts.** Todo usa la identidad del servicio. La única llave del sistema es el token de Apify, y vive en Secret Manager.
- **Una service account por componente**, con roles sobre el recurso concreto cuando GCP lo permite (bucket, cola, servicio, secreto) y a nivel proyecto solo cuando no hay otra forma.
- **Los scripts de infra son idempotentes.** Si agregas uno, que se pueda correr dos veces sin romper nada.
- **Todo dato de usuario expira a las 24 horas.** Si agregas un lugar donde se guarda algo, dale su TTL o su lifecycle.
