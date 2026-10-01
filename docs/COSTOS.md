# Costos de Roastfolio

Precios de lista vigentes al **28 de septiembre de 2026**, en USD, para el proyecto `ai-experiments-487722`. El consumo se midió en producción y con la API de Vertex AI después de la optimización del mismo día: una sola llamada a Gemini por roast, con razonamiento bajo.

## En una frase

**Tener Roastfolio en línea cuesta $33 al mes aunque nadie entre, y cada roast suma unos 6 centavos de dólar** (unos 50 centavos de quetzal). Una persona hace en promedio 1.5 roasts, así que **cada usuario cuesta unos 9 centavos**.

## Cuánto cuesta un roast

| Qué se paga | PDF | LinkedIn | Promedio (70 % PDF, 30 % LinkedIn) | % |
|---|---:|---:|---:|---:|
| Certificado con Nano Banana | $0.0337 | $0.0337 | $0.0337 | 54 % |
| Lectura del CV con Document AI (2 páginas) | $0.0200 | — | $0.0140 | 22 % |
| Roast con Gemini 3.8 Flash | $0.0105 | $0.0147 | $0.0118 | 19 % |
| Perfil de LinkedIn con Apify | — | $0.0040 | $0.0012 | 2 % |
| Servidores, base de datos, CDN y red | $0.0017 | $0.0017 | $0.0017 | 3 % |
| **Total por roast** | **$0.066** | **$0.054** | **$0.062** | |

- **El 97 % es IA pagada por uso.** No hay contrato ni mínimo: si nadie hace roasts, esa parte es $0.
- **El certificado es lo más caro.** Cuando Vertex AI no puede generarlo (cuota agotada o filtro de seguridad), el usuario recibe un certificado genérico ya hecho y ese roast cuesta $0.034 menos.
- **LinkedIn sale más barato que un PDF.** Apify cobra menos por perfil que Document AI por dos páginas, aunque le manda más texto a Gemini.

## Cuánto cuesta un usuario

Un **usuario** es una persona que hace al menos un roast en el mes. Los supuestos:

- **1.5 roasts por usuario.** Mucha gente prueba una segunda intensidad o roastea a un amigo.
- **Las vistas del link compartido casi no cuestan.** Sirven un HTML y una imagen desde el CDN: menos de una décima de centavo por vista.

Así, **un usuario cuesta $0.094 en costo variable**. El costo fijo se reparte entre todos: pesa mucho con poca gente y casi nada con mucha.

## La factura del mes según usuarios

Fórmula: **$33.29 + $0.062 × roasts**, con roasts = 1.5 × usuarios.

| Usuarios al mes | Roasts | Factura mensual | Costo por usuario | De eso, IA |
|---:|---:|---:|---:|---:|
| 0 | 0 | **$33** | — | 0 % |
| 100 | 150 | **$43** | $0.43 | 21 % |
| 1,000 | 1,500 | **$127** | $0.13 | 72 % |
| 10,000 | 15,000 | **$969** | $0.097 | 94 % |
| 100,000 | 150,000 | **$9,387** | $0.094 | 97 % |

La fórmula no descuenta las capas gratuitas de Cloud Run, Firestore y Storage, así que es conservadora. En el [detalle por servicio](#detalle-por-servicio), con capas gratuitas, 1,000 usuarios salen en $125 y 10,000 en $964.

**Precio introductorio.** Hasta el 31 de diciembre de 2026, Gemini 3.8 Flash cuesta la mitad. Mientras dure, cada roast baja $0.006: 1,000 usuarios salen en $118 y 10,000 en $880. Las tablas usan el precio estándar porque es el que aplica desde el 1 de enero de 2027.

## Para finanzas

**Estructura de costos.**

| | Monto | Qué lo mueve |
|---|---|---|
| Fijo | $33.29 al mes | Load Balancer ($18.25) y Cloud Armor ($15), que cobran por hora. No depende del tráfico |
| Variable | $0.062 por roast, $0.094 por usuario | Casi todo es IA facturada por uso (Vertex AI, Document AI y Apify) |

- **Punto de equilibrio del fijo.** Con unos 540 roasts al mes, el costo variable iguala al fijo. Por debajo de eso, más de la mitad de la factura es "tener la puerta abierta".
- **Margen si algún día se cobra.** Con $1 por roast, el margen bruto es de 94 % sobre el costo variable. Con $0.25, de 75 %.
- **Economías de escala.** Casi no hay. Arriba de 10,000 usuarios, el costo por usuario se queda en $0.09–0.10 porque lo domina la IA, que se cobra por unidad. Bajarlo requiere cambios de producto (sección siguiente), no volumen.

**Riesgos y controles.**

- **Abuso.** Cloud Armor limita a 5 roasts por IP cada 10 minutos. Aun así, alguien con muchas IPs podría generar tráfico caro. **El techo es de unos $30 al día:** web acepta como máximo 450 roasts diarios (`DAILY_ROAST_LIMIT`, hora de Guatemala), unos $28 de IA más el costo fijo, y rechaza el resto con un mensaje claro. Sin ese tope, el límite lo pondría el worker: 5 instancias con 4 roasts simultáneos procesan hasta 2,880 roasts por hora, unos $180 por hora.
- **Presupuesto.** Cloud Billing tiene un presupuesto de $900 al mes para el proyecto, con alertas por correo al 50, 90 y 100 % del gasto real y al 100 % del pronóstico (`infra/14-budget.sh`). Un presupuesto solo avisa; el que detiene el gasto es el tope diario.
- **Fin del precio introductorio (1-ene-2027).** Ya está incluido en las tablas: no es una sorpresa.
- **Cuota de imágenes de Vertex AI.** No es un costo sino un límite de capacidad. Si se agota, el usuario recibe el certificado genérico y el roast no falla. La métrica `roastfolio_cards_generic` cuenta cuántas veces pasa. Arriba de unos 10,000 usuarios al mes conviene pedir más cuota.
- **Tipo de cambio.** Todo se factura en USD. Los montos en quetzales usan 7.75 Q/USD como referencia.

## Cómo bajarlo

| Cambio | Ahorro | A cambio de |
|---|---|---|
| ✅ **Una sola llamada a Gemini, con razonamiento bajo** (aplicado el 28-sep-2026) | De $0.08 a $0.062 por roast, y ~35 s menos de espera | Nada: la calidad del roast se mantuvo en las pruebas |
| **Nano Banana en modo Flex** | $0.017 por roast (−27 %) | El certificado puede tardar más. Tolera la espera porque el roast ya está en pantalla |
| **Leer el PDF con `pypdf` y dejar Document AI solo para PDFs escaneados** | Hasta $0.014 por roast (−22 %) | Se pierde la demo de Document AI en la mayoría de los roasts |
| **Generar el certificado solo cuando el usuario comparte o descarga** | Hasta $0.034 por roast que no se comparte | Un paso más para quien sí comparte |
| **Quitar Load Balancer y Cloud Armor** (Firebase Hosting + Cloud Run con ingress público) | $33 fijos al mes | El WAF, el ruteo por path y el certificado de nip.io, que son parte de la demo |

Con Flex y `pypdf`, **un roast baja a $0.032 y un usuario a $0.047**: la mitad.

## Detalle por servicio

Escenarios: **(a)** 1,000 usuarios (1,500 roasts), **(b)** 10,000 usuarios (15,000 roasts) y **(c)** sin uso. Precios de us-central1 o globales; los meses se calculan con 730 horas.

| # | Servicio | Precio unitario | Capa gratuita | Fórmula | (a) | (b) | (c) |
|---|----------|-----------------|---------------|---------|----:|----:|----:|
| 1 | **Load Balancer** (2 reglas de forwarding: HTTPS :443 y redirect :80) | $0.025/h cubre las primeras 5 reglas | — | 0.025 × 730 | 18.25 | 18.25 | 18.25 |
| 2 | **Cloud Armor Standard** (1 política, 10 reglas: 8 OWASP + 2 rate limits) | $5/política, $1/regla al mes, $0.75/M requests | — | 5 + 10 × 1 + req × 0.75/M (37.5k / 375k req) | 15.03 | 15.28 | 15.00 |
| 3 | **Document AI** Layout Parser | $10 / 1,000 páginas | — | páginas × 0.01 (2,100 / 21,000) | 21.00 | 210.00 | 0 |
| 4 | **Gemini 3.8 Flash** (global) | $1.50/M entrada, $7.50/M salida | — | R × (3,040 × 1.5 + 960 × 7.5)/1M = R × $0.0118 | 17.70 | 177.00 | 0 |
| 5 | **Nano Banana 2 Lite** (global) | $30/M tokens de imagen de salida, $0.25/M de entrada | — | R × (1,120 × 30 + 394 × 0.25)/1M = R × $0.0337 | 50.55 | 505.48 | 0 |
| 6 | **Cloud CDN** (site + cards) | Salida de caché a Latinoamérica $0.09/GiB; lectura $0.0075/10k; llenado $0.01/GiB | — | (a): 8.2 GiB × 0.09 + 127.5k × 0.75/M + 0.44 GiB × 0.01 | 0.84 | 8.36 | 0 |
| 7 | **Cloud Run** (web + worker) | $0.000024/vCPU-s, $0.0000025/GiB-s, $0.40/M req | 180k vCPU-s, 360k GiB-s, 2M req | (a): 64.5k vCPU-s, 55k GiB-s → gratis. (b): (645k − 180k) × 0.000024 + (547.5k − 360k) × 0.0000025 | 0 | 11.63 | 0 |
| 8 | **Firestore** (base `roastfolio`) | $0.30/M lecturas, $0.90/M escrituras, $0.10/M borrados por TTL | 50k lecturas y 20k escrituras al día | (b): unas 9.5k lecturas y 3k escrituras al día, dentro de la cuota | 0 | 0 | 0 |
| 9 | **Cloud Storage** (3 buckets, Standard) | $0.02/GB-mes, clase A $5/M, clase B $0.40/M | 5 GB, 5k A, 50k B | (b): operaciones arriba de la cuota; almacenamiento < 0.3 GB | 0 | 0.20 | 0 |
| 10 | **Cloud Tasks** | $0.40/M operaciones | 1M operaciones | 3k / 30k operaciones | 0 | 0 | 0 |
| 11 | **Salida a internet + procesamiento del LB** (respuestas de web) | ~$0.12/GiB de salida + $0.008/GiB procesado | — | ~0.08 / 0.8 GiB | 0.02 | 0.11 | 0 |
| 12 | **Artifact Registry** | $0.10/GB-mes | 0.5 GB | (0.93 GiB − 0.5) × 0.10 | 0.04 | 0.04 | 0.04 |
| 13 | **Cloud Build** | $0.006/min (e2-standard-2) | 2,500 min | 90 min | 0 | 0 | 0 |
| 14 | **Cloud Logging / Monitoring** | $0.50/GiB de logs; métricas $0.258/MiB | 50 GiB de logs por proyecto; 150 MiB de métricas | ~0.25 / 2.5 GiB de logs | 0 | 0 | 0 |
| 15 | **Secret Manager** (1 secreto) | $0.06/versión, $0.03/10k accesos | 6 versiones, 10k accesos | 1 versión; el token se lee una vez por instancia | 0 | 0 | 0 |
| 16 | **IAM, IP estática** | La IP asignada a una regla de forwarding no cobra | — | — | 0 | 0 | 0 |
| | **Total GCP** | | | | **123.43** | **946.35** | **33.29** |
| — | Apify (fuera de GCP) | ~$4 / 1,000 perfiles | — | perfiles × 0.004 (450 / 4,500) | 1.80 | 18.00 | 0 |
| | **Total** | | | | **125.23** | **964.35** | **33.29** |

**Sin ninguna capa gratuita** (si la cuenta de facturación ya la gastó), Cloud Run suma $1.69 en (a) y $5.22 más en (b), y Cloud Build $0.54. Firestore y Storage agregan centavos. Esto importa porque **las capas gratuitas son por cuenta de facturación, no por proyecto**.

**Monitoring:** las alertas no se cobran todavía. No antes del 1 de septiembre de 2027 costarán $0.35 por referencia a una métrica, así que la alerta de tasa de error (2 métricas) pasará a unos $0.70 al mes.

## Supuestos y mediciones

**Tráfico por usuario**

| | Por usuario | (a) 1,000 usuarios | (b) 10,000 usuarios |
|---|---:|---:|---:|
| Roasts | 1.5 | 1,500 | 15,000 |
| PDF (70 %, 2 páginas en promedio) | 1.05 | 1,050 → 2,100 páginas | 10,500 → 21,000 páginas |
| URL de LinkedIn (30 %) | 0.45 | 450 | 4,500 |
| Page views del sitio (incluye visitas que no hacen roast) | 30 | 30,000 | 300,000 |
| Vistas del certificado compartido | 7.5 | 7,500 | 75,000 |

**Medido el 28-sep-2026, después de la optimización**

- **Tokens de Gemini 3.8 Flash** (`usage_metadata`, 6 roasts: 3 intensidades × 2 perfiles). Un CV de 2 páginas usa unos **2,200 tokens de entrada** y uno de LinkedIn unos **5,000**, porque el perfil trae más texto. La salida es de **~960 tokens** en los dos casos (entre 803 y 1,186), sin tokens de razonamiento. Promedio ponderado: **3,040 de entrada y 960 de salida por roast**. Antes de la optimización eran 2,350 y 3,850 en dos llamadas.
- **Tokens de Nano Banana 2 Lite** (`gemini-3.1-flash-lite-image`): **394 de entrada** (el prompt del certificado creció) y **1,120 de salida** por imagen 1K.
- **Tiempo del worker por roast.** Los pasos duran 3–7 s (extracting con PDF; 7–27 s con LinkedIn), ~10 s (roasting) y ~3 s (rendering), según `step_finished`. **Supuesto: 30 s facturables por roast**, con margen para arranques en frío. Antes eran 55 s.
- **Tiempo de web por roast.** El frontend consulta el estado cada 2 s y el roast termina antes que antes: ~12 consultas. **Supuesto: 10 s facturables por roast y 1 s por vista compartida.**
- **Cloud Run.** `roastfolio-worker` usa 1 vCPU, 1 GiB, concurrencia 4, máximo 5 instancias y mínimo 0. `roastfolio-web` usa 1 vCPU, 512 MiB, concurrencia 40, máximo 5 y mínimo 0. Los dos tienen facturación por request.
- **Archivos.** El certificado JPEG pesa ~150 KB. Un PDF de 2 páginas, ~150 KB. Una carga completa del sitio, ~265 KB sin compresión.
- **Cloud Build.** Cada build tarda unos 3 minutos; se asumen 30 *pushes* al mes.
- **Artifact Registry.** 994 MB, estable por la política de limpieza (10 versiones, 30 días).

**Llamadas por roast**

| Qué | Por roast |
|-----|-----------|
| Requests a web (pasan por Cloud Armor) | 1 POST + ~12 consultas de estado, más 2 por cada vista compartida |
| Lecturas de Firestore | 1 del worker + ~12 consultas, más 2 por vista compartida |
| Escrituras de Firestore | 6 (create + 5 cambios de estado); 1 borrado por TTL |
| Tareas de Cloud Tasks | ~2 operaciones (crear + despachar) |
| Operaciones de Storage | clase A: 1 por PDF + 1 por certificado; clase B: 1 por PDF, ~2 por certificado y 1 por page view |

Se dejan fuera los reintentos: las llamadas que fallan con 429 no se cobran en Vertex AI, y el pipeline guarda cada paso para no volver a pagar Document AI ni Gemini.

## Cómo reproducirlo en la Calculadora de precios

Entra a https://cloud.google.com/products/calculator, elige *Add to estimate* y agrega cada servicio con estos valores del escenario (a). Para (b), multiplica por 10 todo menos el LB, Armor (política y reglas) y Artifact Registry.

| Servicio en la calculadora | Qué escribir |
|---------------------------|--------------|
| Cloud Load Balancing | Global external Application Load Balancer · 2 forwarding rules · datos entrantes procesados 0.2 GiB · datos salientes 0.08 GiB |
| Cloud Armor | Standard · 1 security policy · 10 rules · 0.0375 millones de requests |
| Cloud CDN | Cache egress: 8.2 GiB a Latin America · Cache fill: 0.44 GiB dentro de North America · Cache lookups: 127,500 |
| Cloud Run (servicio 1, worker) | us-central1 · Request-based billing · 1 vCPU · 1 GiB · 1,500 requests/mes · 30,000 ms por request · concurrencia 1 · min instances 0 |
| Cloud Run (servicio 2, web) | us-central1 · Request-based billing · 1 vCPU · 0.5 GiB · 37,500 requests/mes · 600 ms por request · concurrencia 1 · min instances 0 |
| Document AI | Layout Parser · 2,100 páginas |
| Vertex AI (Gemini) | Gemini 3.8 Flash, global · 4.56 M tokens de entrada · 1.44 M de salida. Si el modelo no aparece, usa $1.50 / $7.50 por M de otro Flash como referencia |
| Vertex AI (imagen) | Gemini 3.1 Flash-Lite Image · 1,500 imágenes 1K de salida (1.68 M tokens) · 0.59 M tokens de entrada |
| Firestore | us-central1 · 950 lecturas/día · 300 escrituras/día · 50 borrados/día · 0.01 GiB |
| Cloud Storage | Standard · us-central1 · 0.03 GiB · 2,550 operaciones clase A · 34,800 clase B |
| Cloud Tasks | 3,000 operaciones |
| Artifact Registry | 1 GB de almacenamiento |
| Cloud Build | e2-standard-2 · 90 build-minutes |
| Cloud Logging | 0.25 GiB ingeridos |
| Secret Manager | 1 versión activa · 1,000 accesos |

La calculadora aplica las capas gratuitas como si tuvieras la cuenta solo para este proyecto. Para ver el peor caso, usa el párrafo "sin ninguna capa gratuita".

## Qué no se pudo verificar

- **Tokens por roast.** La muestra es de 6 roasts sobre 2 perfiles. Un CV más largo o un LinkedIn con mucha experiencia sube la entrada; la salida varía poco (803–1,186 tokens).
- **Roasts por usuario.** El 1.5 es un supuesto, no una medición: todavía no hay tráfico real suficiente. Con la métrica `roastfolio_roasts_queued` y un conteo de IPs únicas en los logs del LB se puede medir.
- **La regla por defecto de Cloud Armor.** La política tiene 11 reglas (10 propias y la default `2147483647`). La página de precios no dice si la default se cobra; aquí se cuentan 10. Si la cobran, suma $1 al mes.
- **Firestore gratis.** La página de precios dice que las bases con nombre no tienen cuota gratuita, pero `gcloud firestore databases describe --database=roastfolio` devuelve `freeTier: True` (es la única base del proyecto). Sin cuota gratuita, Firestore costaría unos $0.02 en (a) y $0.17 en (b).
- **Apify.** El precio de `harvestapi/linkedin-profile-scraper` (~$4 por 1,000 perfiles) viene del README del actor y no se revisó contra la factura de Apify.
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

**Mediciones:** tokens con `usage_metadata` de Vertex AI sobre 6 roasts (3 intensidades × 2 perfiles) y 1 certificado, el 28-sep-2026 después de quitar la normalización; `gcloud run services describe`, `gcloud storage du` / `ls -l` de los tres buckets, `gcloud logging read` (`step_finished`, `roast_queued`, `roast_done`), las métricas `aiplatform.googleapis.com/publisher/online_serving/token_count` y `model_invocation_count` y `run.googleapis.com/container/billable_instance_time`, `gcloud builds list`, `gcloud artifacts repositories describe` y `gcloud compute security-policies describe rf-armor`.
