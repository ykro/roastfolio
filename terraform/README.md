# Roastfolio en Terraform

La misma infraestructura que levantan los scripts `infra/NN-*.sh`, escrita como código declarativo. Sirve para dos cosas: **adoptar** lo que ya existe en `ai-experiments-487722` (con bloques `import {}`, sin recrear nada) o **levantar todo desde cero** en otro proyecto.

## Qué administra

| Archivo | Recursos |
|---------|----------|
| `apis.tf` | Las 13 APIs del proyecto (nunca las apaga al destruir) |
| `iam.tf` | `sa-web`, `sa-worker`, `sa-tasks`, `sa-build`, sus roles a nivel proyecto y los permisos de `actAs` |
| `storage.tf` | Buckets `site`, `uploads` y `cards`, lifecycle de 1 día y permisos por bucket |
| `firestore.tf` | Base `roastfolio` + política TTL sobre `roasts.expiresAt` |
| `documentai.tf` | Procesador Layout Parser en `us` |
| `tasks.tf` | Cola `roasts` + permiso de encolar para `sa-web` |
| `secrets.tf` | Secreto `apify-token` (solo el contenedor, nunca el valor) + acceso de `sa-worker` |
| `artifact_registry.tf` | Repositorio Docker con política de limpieza + escritura para `sa-build` |
| `run.tf` | `roastfolio-web` y `roastfolio-worker` con toda su configuración de runtime, `run.invoker` para `sa-tasks` y `run.developer` para `sa-build` **solo sobre esos dos servicios** |
| `lb.tf` | IP global, NEG serverless, backend service, backend buckets con CDN, URL map, certificado administrado para `<IP>.nip.io`, proxy HTTPS, forwarding rules y redirect HTTP → HTTPS |
| `armor.tf` | Política `rf-armor`: 8 reglas OWASP + 2 rate limits + regla por defecto |
| `observability.tf` | 4 métricas basadas en logs, canal de correo, alerta de tasa de error y dashboard |
| `build.tf` | Conexión a GitHub (2nd gen), repositorio, trigger `roastfolio-main` y permisos del agente de Cloud Build |
| `import.tf` | Bloques `import {}` que apuntan a los recursos vivos |

En total son 73 recursos.

## Requisitos

- Terraform ≥ 1.7 (`brew install hashicorp/tap/terraform`).
- Credenciales de aplicación con permisos de owner en el proyecto: `gcloud auth application-default login`.
- El estado es **local** (`terraform.tfstate`, ignorado por git). Para trabajar en equipo cambia a un backend `gcs` (hay un ejemplo comentado en `providers.tf`).

`terraform.tfvars` solo tiene valores no secretos (proyecto, región, correo de alertas, repo de GitHub). El token de Apify nunca pasa por Terraform.

## Opción A: adoptar lo que ya existe

Así se usa en este proyecto, donde todo lo crearon los scripts.

```bash
cd terraform
terraform init
terraform plan
```

El plan debe decir:

```
Plan: 73 to import, 0 to add, 1 to change, 0 to destroy.
```

El único cambio es de forma y no afecta nada: la política de limpieza `delete-old` de Artifact Registry tiene `tagState = TAG_STATE_UNSPECIFIED` porque la creó gcloud, y el provider solo acepta `ANY`, que significa lo mismo. Si ves algo `to destroy` o `must be replaced`, **no apliques**: alguien cambió el recurso a mano y hay que alinear el código primero.

```bash
terraform apply
```

Después del primer `apply`, los bloques de `import.tf` ya no hacen nada y los puedes borrar.

> **Ojo:** una vez adoptado, no vuelvas a correr `infra/09-run.sh` ni `infra/12-observability.sh`. El 12 borra y vuelve a crear la alerta y el dashboard (con otros IDs) y Terraform perdería el rastro. A partir de aquí los cambios de infraestructura se hacen en Terraform.

## Opción B: desde cero en un proyecto vacío

1. Borra `import.tf` (sus IDs son del proyecto actual) y ajusta `terraform.tfvars`: tu `project_id`, tu `alert_email` y, por ahora, **sin** `github_app_installation_id` ni `github_token_secret` (quítalos o déjalos en `null`).

2. Si el bucket `<project>_cloudbuild` no existe, créalo o corre una vez cualquier `gcloud builds submit`. Terraform solo le da permiso de lectura a `sa-build` (lo usa el `gcloud builds submit` manual); el bucket es compartido y no lo administra.

3. Primer `apply`:

   ```bash
   terraform init
   terraform apply
   ```

   Esto crea todo menos el repositorio y el trigger de Cloud Build. Los servicios de Cloud Run arrancan con una imagen de ejemplo (`var.initial_image`) porque todavía no hay imágenes propias; el primer build las reemplaza. El certificado tarda de 15 a 60 minutos en quedar `ACTIVE`.

4. **Token de Apify** (fuera de Terraform, para que no quede en el estado):

   ```bash
   printf '%s' 'apify_api_...' | gcloud secrets versions add apify-token --data-file=-
   ```

5. **Autorización de GitHub (manual, en el navegador).** La conexión `rf-github` queda pendiente. Abre el link que imprime:

   ```bash
   terraform output github_authorize_url
   ```

   Autoriza la GitHub App de Cloud Build e instálala en el repo (`ykro/roastfolio`). Durante este paso el agente de Cloud Build guarda el token de GitHub en un secreto regional; por eso, mientras la conexión está pendiente, Terraform le da `secretmanager.admin` a nivel proyecto.

6. Copia los dos datos que dejó la autorización a `terraform.tfvars`:

   ```bash
   gcloud builds connections describe rf-github --region=us-central1 \
     --format='value(githubConfig.appInstallationId,githubConfig.authorizerCredential.oauthTokenSecretVersion)'
   ```

   ```hcl
   github_app_installation_id = 12345678
   github_token_secret        = "rf-github-github-oauthtoken-xxxxxx"  # solo el nombre, sin projects/... ni /versions/latest
   ```

7. Segundo `apply`. Crea el repositorio y el trigger, le quita al agente el `secretmanager.admin` de proyecto y le deja solo `secretAccessor` sobre ese secreto.

8. Primer despliegue real (o haz push a `main`):

   ```bash
   gcloud builds triggers run roastfolio-main --region=us-central1 --branch=main
   ```

## Lo que queda fuera de Terraform (a propósito)

- **Las imágenes de Cloud Run.** Cloud Build las cambia en cada push (`gcloud run deploy --image`). Por eso `run.tf` ignora `image`, `client` y `client_version`: si no, cada `plan` querría regresar a la imagen anterior. Todo lo demás (variables, cuenta de servicio, ingress, límites) sí es de Terraform; si cambias una variable de entorno, hazlo aquí.
- **El contenido del bucket `site`.** Lo publica `cloudbuild.yaml`.
- **Los valores de los secretos.** Terraform crea `apify-token` y sus permisos, pero la versión con el token se agrega a mano. El secreto con el token de GitHub lo crea Cloud Build durante la autorización; Terraform solo administra quién lo puede leer.
- **La autorización de la GitHub App**, que necesita un humano en el navegador.
- **El bucket `<project>_cloudbuild`**, que es el bucket por defecto de Cloud Build y lo comparten otros builds del proyecto.
- **Workload Identity Federation / GitHub Actions**: se quitó del proyecto; el CI/CD es 100% Cloud Build.

## Destruir

`terraform destroy` no apaga APIs, y además se detiene en dos cosas a propósito:

- Los servicios de Cloud Run tienen `deletion_protection = true` (valor por defecto del provider). Cámbialo a `false` y aplica antes de destruir.
- La base de Firestore usa `deletion_policy = "ABANDON"`: Terraform la suelta del estado, pero no la borra.

## Problemas comunes

- **`Cloud Resource Manager API has not been used in project ...`**: tus credenciales de aplicación tienen un *quota project* que no tiene esa API habilitada. Habilítala en ese proyecto o quita el quota project de las ADC.
- **`Cannot find binding ... roles/run.developer`** al hacer `plan` en modo adopción: el permiso de `sa-build` todavía está a nivel proyecto y no en los servicios. Dale `run.developer` sobre `roastfolio-web` y `roastfolio-worker` (o borra ese bloque de `import.tf` y deja que Terraform lo cree).
