# Clase 12: Terraform I (Docker)

Práctica con el provider `kreuzwerker/docker` 4.5.0: un `docker_image` (nginx:alpine) y un `docker_container` (`tf-web`).

## 4.2 Configuración inicial

- **¿Cuántos recursos se declaran?** Dos: `docker_image.web` y `docker_container.web`.
- **¿Cuál depende del otro?** El contenedor depende de la imagen.
- **¿Qué expresión establece la dependencia?** `image = docker_image.web.image_id`. Al referenciar un atributo de la imagen, Terraform sabe que debe crearla primero.

## 4.3 Init, validate, fmt, plan

- `terraform init` instaló el provider 4.5.0 y creó `.terraform.lock.hcl`.
- `terraform validate`: configuración válida.
- `terraform plan`: `Plan: 2 to add, 0 to change, 0 to destroy`. `docker ps -a` confirmó que `tf-web` no existía aún, porque plan no crea nada.

## 4.4 Apply

- `terraform apply`: `2 added`.
- `curl -I http://localhost:8080` respondió `HTTP/1.1 200 OK`.
- ID del contenedor: `3b98a02b9d796280be6eb52d7078e3be640659aaa039934a13eddb590de220c5`

## 4.5 Plan sin cambios

Resultado: `No changes. Your infrastructure matches the configuration.`

Para concluir que no hay cambios, Terraform necesita tres cosas: la configuración deseada (`main.tf`), el state, que registra qué objetos reales administra y con qué atributos, y el estado actual consultado al provider (Docker). Compara los tres y, al no haber diferencias, no propone acciones.

## 4.6 Actualización in situ (`memory = 256`)

- **Predicción:** Terraform podrá modificar el contenedor existente, porque el límite de memoria se puede cambiar en un contenedor en ejecución (`docker update`).
- **Plan:** `update in-place`, `0 to add, 1 to change, 0 to destroy`.
- **Incidencia:** el primer `apply` falló con `Memory limit should be smaller than already set memoryswap limit, update the memoryswap at the same time`. Docker exige actualizar `memory` y `memory_swap` juntos. Se agregó `memory_swap = 512` y el apply funcionó. El plan era correcto, pero la API del provider rechazó la operación al aplicarla.
- **¿Cambió el ID?** No: sigue siendo `3b98a02b…`.
- Verificación: `HostConfig.Memory` = 268435456 (256 MiB).

## 4.7 Reemplazo (puerto externo 8081)

- **Predicción:** Terraform deberá reemplazar el contenedor, porque los puertos publicados no se pueden cambiar en un contenedor ya creado.
- **Plan:** `docker_container.web must be replaced`, causado por `ports.external = 8080 -> 8081 # forces replacement`. Resumen: `Plan: 1 to add, 0 to change, 1 to destroy`.
- **Resultado:** ID nuevo `7731503e079f1f55a67ca95d571b938681162a1c242e6de3961b8fcb1460552a`. `curl -I http://localhost:8081` respondió 200.

| Cambio | Acción del plan | ¿Cambió el identificador? | Efecto observable |
|---|---|---|---|
| Límite de memoria (0 → 256) | update in-place | No | El contenedor siguió corriendo con el límite nuevo. |
| Puerto externo (8080 → 8081) | replace (destroy + create) | Sí | Se creó un contenedor nuevo. El puerto 8080 dejó de responder y 8081 responde. |

## 4.8 Destrucción

- `terraform plan -destroy`: `0 to add, 0 to change, 2 to destroy`.
- `terraform destroy`: `2 destroyed`.
- `docker ps -a` ya no muestra `tf-web`. La imagen `nginx:alpine` sigue local por `keep_locally = true`.

## 4.9 Análisis

1. **¿Qué información de `required_providers` identifica la implementación del provider?** El atributo `source` (`kreuzwerker/docker`, es decir `registry.terraform.io/kreuzwerker/docker`) indica de qué namespace y registro descargarlo, y `version` indica qué versión. El nombre local (`docker`) es solo un alias dentro del módulo.
2. **¿Por qué declarar dos providers no vuelve portables los recursos?** Cada tipo de recurso pertenece a un provider y modela la API de esa plataforma. Un `docker_container` no tiene equivalente en otro provider (por ejemplo Google Cloud), así que habría que reescribir los recursos con sus propios tipos y atributos. Terraform es un lenguaje común, no una abstracción común.
3. **¿Por qué el segundo `plan` no propone acciones?** Porque la configuración, el state y el estado real consultado a Docker coinciden. No hay diferencia que corregir.
4. **¿Diferencia entre editar la configuración y hacer `docker rm` + `docker run` a mano?** Al editar la configuración, Terraform calcula la diferencia contra el state, muestra un plan revisable y decide si actualiza o reemplaza. El cambio queda declarado y es reproducible. Con `docker rm` y `docker run` el cambio es imperativo: no queda registrado en el código, el state no se entera y Terraform lo detectará como deriva (drift) en el siguiente plan, sin revisión previa.
5. **¿Por qué el reemplazo merece más atención que una actualización in situ?** Destruye el objeto y crea uno nuevo con otro ID. Se pierde lo que no esté declarado (datos del contenedor, conexiones activas, permisos o configuración manual). Puede haber una interrupción del servicio y otros recursos que dependan de él pueden verse afectados. Por eso hay que leer qué atributo fuerza el reemplazo (`# forces replacement`) y no quedarse solo con el resumen de contadores.
6. **¿Qué archivos aparecieron?** Después de `init`: el directorio `.terraform/` (provider descargado) y `.terraform.lock.hcl` (versión y hashes del provider). Después de `apply`: `terraform.tfstate`. Al cambiar un recurso existente, Terraform también genera `terraform.tfstate.backup`.
7. **¿Cuál se estudiará en la siguiente clase y por qué lo necesita Terraform?** El archivo de state (`terraform.tfstate`). Terraform lo necesita para saber qué objetos reales corresponden a cada recurso declarado (por ejemplo el ID del contenedor), y así poder comparar, actualizar o destruir sin tener que adivinar.

## Estado final de `main.tf`

Tras los ejercicios quedó con `memory = 256`, `memory_swap = 512` y puerto externo 8081. Los recursos ya fueron destruidos.
