# Costos de Roastfolio

Estimación mensual en USD para el proyecto `ai-experiments-487722`, con precios de lista vigentes al **28 de septiembre de 2026**. Los precios salen del Cloud Billing Catalog API y se confirmaron contra las páginas oficiales de precios. El consumo por roast se midió en producción (logs, Cloud Monitoring y buckets).

## Resumen

| Escenario | Roasts/mes | Total GCP | + Apify | Total |
|-----------|-----------:|----------:|--------:|------:|
| **(c) Sin uso**: el piso fijo | 0 | **$33.29** | $0 | **$33.29** |
| **(a) Tráfico de demo** | 1,000 | **$113.95** | $1.20 | **$115.15** |
| **(b) 10×** | 10,000 | **$854.36** | $12.00 | **$866.36** |

- **Costo marginal: unos $0.08 por roast.** Un tercio es Nano Banana ($0.034), otro tercio Gemini 3.8 Flash ($0.032) y el resto sale casi todo de Document AI ($0.014 en promedio).
- **Precio introductorio de Gemini 3.8 Flash.** Hasta el 31 de diciembre de 2026, Google cobra $0.75 / $3.75 por millón de tokens de entrada/salida en vez de $1.50 / $7.50. Mientras dure, (a) queda en **$97.75** y (b) en **$692.36**. La tabla usa el precio estándar porque es el que publica el catálogo y el que aplica desde el 1 de enero de 2027.
- **Medir cambió la foto de Gemini.** La primera estimación, hecha antes de tener tráfico real, suponía $2–5 al mes; medido en producción ronda $32. La diferencia está en los tokens de razonamiento (*thinking*), que se cobran como salida: cada roast genera unos 3,800 tokens de salida aunque el JSON visible apenas llega a 900.

## Supuestos

**Tráfico**

| | (a) | (b) | (c) |
|---|---:|---:|---:|
| Roasts | 1,000 | 10,000 | 0 |
| PDF (70 %, 2 páginas en promedio) | 700 → 1,400 páginas | 7,000 → 14,000 páginas | 0 |
| URL de LinkedIn (30 %) | 300 | 3,000 | 0 |
| Page views del sitio | 20,000 | 200,000 | 0 |
| Vistas de tarjeta (5 por roast) | 5,000 | 50,000 | 0 |

**Medido en producción (28-sep-2026)**

- **Cloud Run.** `roastfolio-worker` usa 1 vCPU, 1 GiB, concurrencia 4, máximo 5 instancias y mínimo 0. `roastfolio-web` usa 1 vCPU, 512 MiB, concurrencia 40, máximo 5 y mínimo 0. Los dos tienen facturación por request y *startup CPU boost*.
- **Tiempo del worker por roast.** Los pasos duran 10.8 s (extracting), 23.0 s (roasting) y 3.7 s (rendering), según `step_finished`. La métrica `billable_instance_time` marcó 57 s para un roast aislado con arranque en frío. **Supuesto: 55 s facturables por roast.**
- **Tiempo de web por roast.** Se midieron unos 14 s facturables en una hora con un solo roast (POST más *polling*). **Supuesto: 15 s por roast y 1 s por cada vista compartida.**
- **Tokens de Gemini 3.8 Flash** (Cloud Monitoring, `publisher/online_serving/token_count`). Un CV de 1 página usó 1,750 tokens de entrada y 3,797 de salida en 2 llamadas; uno de LinkedIn, unos 1,650 y 3,250. Si escalas a CVs de 2 páginas y ponderas 70/30, salen **2,350 de entrada y 3,850 de salida por roast**.
- **Tokens de Nano Banana 2 Lite** (`gemini-3.1-flash-lite-image`). Cada imagen usa unos 245 tokens de entrada y **1,120 de salida (imagen 1K)**, lo mismo que dice la página de precios.
- **Tamaños de archivo.** La tarjeta JPEG pesa 156.5 KB en promedio (3 tarjetas en `gs://…-cards`). El PDF subido pesa 91 KB y se asumen 150 KB para uno de 2 páginas. Una carga completa del sitio pesa 254 KB (`index.html` 1.3 KB, JS 235 KB, CSS 17 KB y favicon), sin compresión.
- **Cloud Build.** Cada build tarda unos 3 minutos; se asumen 30 *pushes* al mes, o sea 90 minutos.
- **Artifact Registry.** El repositorio `roastfolio` pesa 994 MB hoy. La política de limpieza (conservar 10 versiones y borrar las de más de 30 días) lo mantiene estable.

**Llamadas por roast**

| Qué | Por roast |
|-----|-----------|
| Requests a web (pasan por Cloud Armor) | 1 POST + ~25 consultas de estado cada 2 s, más 2 por cada vista compartida (`/r/{id}` + `/api/roasts/{id}`) |
| Lecturas de Firestore | 1 del worker + 25 consultas, más 2 por vista compartida |
| Escrituras de Firestore | 6 (create + 5 cambios de estado); 1 borrado por TTL |
| Tareas de Cloud Tasks | ~2 operaciones (crear + despachar) |
| Operaciones clase A de Storage | 1 por PDF + 1 por tarjeta |
| Operaciones clase B de Storage | 1 por PDF, ~2 por tarjeta (llenado del CDN) y 1 por page view (el CDN revalida `index.html` porque tiene `no-cache`) |
| Lecturas de CDN | 4 por page view y 1 por vista de tarjeta |

Se dejan fuera los reintentos: las llamadas que fallan con 429 no se cobran en Vertex, y el pipeline guarda cada paso para no volver a pagar Document AI ni Gemini. **Las capas gratuitas de Cloud Run, Cloud Build, Storage, Tasks y Secret Manager son por cuenta de facturación.** Por eso al final hay una columna sin capa gratuita.

## Costo por servicio

Precios de us-central1 o globales. Todos los meses se calculan con 730 horas.

| # | Servicio | Precio unitario | Capa gratuita | Fórmula | (a) | (b) | (c) |
|---|----------|-----------------|---------------|---------|----:|----:|----:|
| 1 | **Load Balancer** (2 reglas de forwarding: HTTPS :443 y redirect :80) | $0.025/h cubre las primeras 5 reglas | — | 0.025 × 730 | 18.25 | 18.25 | 18.25 |
| 2 | **Cloud Armor Standard** (1 política, 10 reglas: 8 OWASP + 2 rate limits) | $5/política, $1/regla al mes, $0.75/M requests | — | 5 + 10 × 1 + req × 0.75/M (37k / 370k req) | 15.03 | 15.27 | 15.00 |
| 3 | **Document AI** Layout Parser | $10 / 1,000 páginas | — | páginas × 0.01 (1,400 / 14,000) | 14.00 | 140.00 | 0 |
| 4 | **Gemini 3.8 Flash** (global) | $1.50/M entrada, $7.50/M salida con razonamiento | — | R × (2,350 × 1.5 + 3,850 × 7.5)/1M = R × $0.0324 | 32.40 | 324.00 | 0 |
| 5 | **Nano Banana 2 Lite** (global) | $30/M tokens de imagen de salida, $0.25/M de entrada | — | R × (1,120 × 30 + 245 × 0.25)/1M = R × $0.03366 | 33.66 | 336.61 | 0 |
| 6 | **Cloud CDN** (site + cards) | Salida de caché a Latinoamérica $0.09/GiB; lectura $0.0075/10k; llenado $0.01/GiB | — | (a): 5.45 GiB × 0.09 + 85k × 0.75/M + 0.29 GiB × 0.01 | 0.56 | 5.57 | 0 |
| 7 | **Cloud Run** (web + worker) | $0.000024/vCPU-s, $0.0000025/GiB-s, $0.40/M req | 180k vCPU-s, 360k GiB-s, 2M req | (a): 75k vCPU-s, 65k GiB-s, 37k req → todo gratis. (b): (750k − 180k) × 0.000024 + (650k − 360k) × 0.0000025 | 0 | 14.41 | 0 |
| 8 | **Firestore** (base `roastfolio`) | $0.30/M lecturas, $0.90/M escrituras, $0.10/M borrados por TTL | 50k lecturas y 20k escrituras al día, 1 GiB | (b): unas 12k lecturas y 2k escrituras al día, dentro de la cuota. Solo se pagan los borrados por TTL | 0.00 | 0.00 | 0 |
| 9 | **Cloud Storage** (3 buckets, Standard) | $0.02/GB-mes, clase A $5/M, clase B $0.40/M | 5 GB, 5k A, 50k B | (b): (17k − 5k) × 5/M + (228k − 50k) × 0.4/M; almacenamiento < 0.2 GB | 0 | 0.13 | 0 |
| 10 | **Cloud Tasks** | $0.40/M operaciones | 1M operaciones | 2k / 20k operaciones | 0 | 0 | 0 |
| 11 | **Salida a internet + procesamiento del LB** (respuestas de web) | ~$0.12/GiB de salida + $0.008/GiB procesado | — | ~0.05 / 0.5 GiB | 0.01 | 0.07 | 0 |
| 12 | **Artifact Registry** | $0.10/GB-mes | 0.5 GB | (0.93 GiB − 0.5) × 0.10 | 0.04 | 0.04 | 0.04 |
| 13 | **Cloud Build** | $0.006/min (e2-standard-2) | 2,500 min | 90 min | 0 | 0 | 0 |
| 14 | **Cloud Logging / Monitoring** | $0.50/GiB de logs; métricas $0.258/MiB | 50 GiB de logs por proyecto; 150 MiB de métricas | ~0.16 / 1.6 GiB de logs (incluye los del LB en `rf-web-backend`) | 0 | 0 | 0 |
| 15 | **Secret Manager** (1 secreto) | $0.06/versión, $0.03/10k accesos | 6 versiones, 10k accesos | 1 versión; el token se lee una vez por instancia (`lru_cache`) | 0 | 0 | 0 |
| 16 | **IAM, IP estática** | La IP asignada a una regla de forwarding no cobra | — | — | 0 | 0 | 0 |
| | **Total GCP** | | | | **113.95** | **854.36** | **33.29** |
| — | Apify (fuera de GCP) | ~$4 / 1,000 perfiles | — | perfiles × 0.004 | 1.20 | 12.00 | 0 |

**Sin ninguna capa gratuita** (si la cuenta de facturación ya la gastó), los totales de GCP suben a **$116.50** en (a) y **$860.47** en (b). Lo que más cambia es Cloud Run: $1.98 en (a) y $19.77 en (b). Además, Cloud Build agrega $0.54, y Firestore y Storage agregan centavos.

**Monitoring:** las alertas no se cobran todavía. Desde el 1 de septiembre de 2027 costarán $0.35 por referencia a una métrica, así que la alerta de tasa de error (2 métricas) pasará a unos $0.70 al mes.

## Fijos vs. variables

| | (a) | (b) | (c) |
|---|---:|---:|---:|
| **Fijos:** LB $18.25 + Armor $15 + Artifact Registry $0.04 | 33.29 | 33.29 | 33.29 |
| **Variables:** IA (Gemini + Nano Banana + Document AI) | 80.06 | 800.61 | 0 |
| **Variables:** todo lo demás (CDN, Run, Armor por request, red, Storage) | 0.60 | 20.46 | 0 |

Con 1,000 roasts, el piso fijo pesa el 29 % de la factura. Con 10,000, el 94 % es IA. Si no hay tráfico, pagas $33.29 solo por tener la puerta abierta: el LB y Armor cobran por hora aunque nadie entre.

## Cómo bajarlo

1. **Quita el Load Balancer y Cloud Armor: ahorras $33.25 fijos, el mayor recorte sin tráfico.** Puedes servir el sitio con Firebase Hosting (que trae CDN), dejar web con `--ingress=all` y pasar el rate limit a la app o a Firestore. Pierdes el WAF, el ruteo por path y el certificado de nip.io, que justo son parte de lo que muestra la demo. Si solo necesitas la demo en clase, crea el LB y Armor antes de la sesión y bórralos después (`gcloud compute forwarding-rules delete …`).
2. **Baja el *thinking* de Gemini.** ✅ Aplicado el 2026-09-28: se eliminó la llamada de normalización (el roast lee el texto extraído directo) y el roast corre con `thinking_level=low`. Pasamos de 2 llamadas a 1 y el razonamiento (unos 2/3 de la salida) casi desaparece: recorta unos $15–20 por cada 1,000 roasts y ~35 s de espera. Las cifras de tokens de arriba son de antes de este cambio.
3. **Nano Banana en Flex.** La tarjeta se genera después de que el usuario ya ve el roast, así que tolera más latencia. En Flex, la imagen de salida cuesta $15/M en vez de $30/M: **−$16.83 por cada 1,000 roasts**. Otra opción: generarla solo cuando el usuario toca "Compartir", o usar la plantilla de Pillow (`mock_card`) y dejarla en $0.
4. **Document AI solo cuando haga falta.** Los CVs exportados ya traen texto: si lo extraes con `pypdf` y dejas Document AI solo para PDFs sin texto, Layout Parser (**$14 por cada 1,000 roasts**) queda en casi nada. Enterprise Document OCR cuesta $1.50 por cada 1,000 páginas.
5. **Mantén `min-instances=0`.** Así está hoy. Una instancia mínima cobra tarifa idle ($0.0000025 por vCPU-s y por GiB-s): +$13.14 al mes en el worker y +$9.86 en web.
6. **Comprime el JS del sitio.** Súbelo con `gcloud storage cp -Z` para que baje de 235 KB a unos 70 KB. Reduce la salida del CDN a menos de la mitad, aunque en (a) eso solo son centavos.

Si aplicas del 2 al 4, el costo marginal baja de $0.08 a unos $0.03 por roast. Si además aplicas el 1, (a) queda en unos $35 al mes.

## Cómo reproducirlo en la Calculadora de precios

Entra a https://cloud.google.com/products/calculator, elige *Add to estimate* y agrega cada servicio con estos valores del escenario (a). Para (b), multiplica por 10 todo menos el LB, Armor (política y reglas) y Artifact Registry.

| Servicio en la calculadora | Qué escribir |
|---------------------------|--------------|
| Cloud Load Balancing | Global external Application Load Balancer · 2 forwarding rules · datos entrantes procesados 0.15 GiB · datos salientes 0.05 GiB |
| Cloud Armor | Standard · 1 security policy · 10 rules · 0.037 millones de requests |
| Cloud CDN | Cache egress: 5.45 GiB a Latin America · Cache fill: 0.29 GiB dentro de North America · Cache lookups: 85,000 |
| Cloud Run (servicio 1, worker) | us-central1 · Request-based billing · 1 vCPU · 1 GiB · 1,000 requests/mes · 55,000 ms por request · concurrencia 1 · min instances 0 |
| Cloud Run (servicio 2, web) | us-central1 · Request-based billing · 1 vCPU · 0.5 GiB · 36,000 requests/mes · 550 ms por request · concurrencia 1 · min instances 0 |
| Document AI | Layout Parser · 1,400 páginas |
| Vertex AI (Gemini) | Gemini 3.8 Flash, global · 2.35 M tokens de entrada · 3.85 M de salida. Si el modelo no aparece, usa $1.50 / $7.50 por M de otro Flash como referencia |
| Vertex AI (imagen) | Gemini 3.1 Flash-Lite Image · 1,000 imágenes 1K de salida (1.12 M tokens) · 0.25 M tokens de entrada |
| Firestore | us-central1 · 1,200 lecturas/día · 200 escrituras/día · 33 borrados/día · 0.01 GiB |
| Cloud Storage | Standard · us-central1 · 0.02 GiB · 1,700 operaciones clase A · 23,200 clase B |
| Cloud Tasks | 2,000 operaciones |
| Artifact Registry | 1 GB de almacenamiento |
| Cloud Build | e2-standard-2 · 90 build-minutes |
| Cloud Logging | 0.2 GiB ingeridos |
| Secret Manager | 1 versión activa · 1,000 accesos |

La calculadora aplica las capas gratuitas como si tuvieras la cuenta solo para este proyecto. Para ver el peor caso, compárala con la columna "sin ninguna capa gratuita".

## Qué no se pudo verificar

- **La regla por defecto de Cloud Armor.** La política tiene 11 reglas (10 propias y la default `2147483647`). La página de precios no dice si la default se cobra; aquí se cuentan 10. Si la cobran, suma $1 al mes.
- **Firestore gratis.** La página de precios dice que las bases con nombre no tienen cuota gratuita, pero `gcloud firestore databases describe --database=roastfolio` devuelve `freeTier: True` (es la única base del proyecto). Sin cuota gratuita, Firestore costaría $0.02 en (a) y $0.16 en (b).
- **Apify.** El precio de `harvestapi/linkedin-profile-scraper` (~$4 por 1,000 perfiles) viene del README y no se revisó contra Apify.
- **Tokens por roast.** La muestra es pequeña (3 roasts reales). El razonamiento varía por perfil, así que Gemini podría moverse ±30 %.
- **El tráfico de CDN** supone que cada page view descarga el sitio completo, sin caché del navegador. Es conservador.

## Fuentes

**Cloud Billing Catalog API** (`cloudbilling.googleapis.com/v1/services/{id}/skus`, consultado el 28-sep-2026):

| Servicio (ID) | SKU y precio |
|---------------|--------------|
| Vertex AI (`C7E2-9256-1C43`) | `2A35-AC68-14D6` Gemini 3.8 Flash Global Text Input $1.50/M · `90FD-DC5F-DC55` Text Output $7.50/M · `70B7-E242-FB90` Gemini 3.1 Flash Lite Image Global Image Output $30/M · `27AB-6048-A0B0` Text Input $0.25/M · `09E9-5200-ADAA` Image Output Flex $15/M |
| Document AI (`D870-408D-92A6`) | `7011-20A1-70DB` Layout Parser $0.01 por página |
| Networking (`E505-1604-58F8`) | `DEE3-C42E-3E4D` Forwarding Rule Minimum Global $0.025/h · `4B13-E64F-4A2B` Armor Policy $5 · `A321-89BD-F5BC` Armor Rule $1 · `1A87-DEB9-C4BE` Armor Requests $0.75/M · `E141-D225-4599` CDN a Latinoamérica $0.09/GiB · `15AE-8E35-C42B` a Norteamérica $0.08/GiB · `4762-E550-B5D2` Cache Lookups $0.75/M · `C134-B6DB-FFCB` / `1481-64C8-6805` procesamiento del LB en Iowa $0.008/GiB |
| Cloud Run (`152E-C115-5142`) | `4856-B847-F1EB` CPU $0.000024/s · `02A2-9231-36A6` memoria $0.0000025/GiB-s · `2DA5-55D3-E679` requests (2M gratis, luego $0.40/M) · `7EBB-8579-2C98` y `740D-08F2-7A11` idle de instancias mínimas $0.0000025 |
| Firestore (`EE2C-7FAC-5E08`) | `F251-5791-CE45` lecturas en Iowa $0.30/M (50k gratis) · `63B3-E146-F0E9` escrituras $0.90/M (20k gratis) · `912E-6A61-9F29` borrados por TTL $0.10/M |
| Cloud Storage (`95FF-2EF5-5EA1`) | `E5F0-6A5D-7BAD` Standard regional $0.02/GB (5 GB gratis) · `4DBF-185F-A415` clase A · `7870-010B-2763` clase B |
| Otros | Cloud Tasks (`F3A6-D7B7-9BDA`) `378A-D762-1F74` · Artifact Registry (`149C-F9EC-3994`) `8502-299A-ABAF` · Secret Manager (`EE82-7A5E-871C`) · Cloud Logging (`5490-F7B7-8DF6`) |

**Páginas oficiales de precios** (28-sep-2026), usadas para confirmar las capas gratuitas y lo que no trae el catálogo:

- [Vertex AI generative AI](https://cloud.google.com/vertex-ai/generative-ai/pricing): precio introductorio de Gemini 3.8 Flash hasta el 31-dic-2026; 1,120 tokens por imagen 1K ($0.034); no cobra respuestas que no sean 200.
- [Document AI](https://cloud.google.com/document-ai/pricing): Layout Parser $10 por cada 1,000 páginas.
- [Cloud Armor](https://cloud.google.com/armor/pricing): Standard, por hora por política y regla.
- [Network pricing](https://cloud.google.com/vpc/network-pricing): primeras 5 reglas $0.025/h; la IP estática asignada a una regla no cobra.
- [Cloud CDN](https://cloud.google.com/cdn/pricing): llenado de caché dentro de Norteamérica $0.01/GiB.
- [Cloud Run](https://cloud.google.com/run/pricing): capa gratuita por request (180k vCPU-s, 360k GiB-s, 2M requests) y redondeo a 100 ms.
- [Firestore](https://cloud.google.com/firestore/pricing), [Cloud Storage](https://cloud.google.com/storage/pricing), [Cloud Tasks](https://cloud.google.com/tasks/pricing), [Cloud Build](https://cloud.google.com/build/pricing) (2,500 minutos gratis por cuenta), [Observability](https://cloud.google.com/stackdriver/pricing) (alertas desde el 1-sep-2027), [Secret Manager](https://cloud.google.com/secret-manager/pricing), [Artifact Registry](https://cloud.google.com/artifact-registry/pricing).

**Mediciones:** `gcloud run services describe`, `gcloud storage du` / `ls -l` de los tres buckets, `gcloud logging read` (`step_finished`, `roast_queued`, `roast_done`), las métricas `aiplatform.googleapis.com/publisher/online_serving/token_count` y `model_invocation_count` y `run.googleapis.com/container/billable_instance_time`, `gcloud builds list`, `gcloud artifacts repositories describe` y `gcloud compute security-policies describe rf-armor`.
