# Especificación: skills operativos para Aviva Chat Server

## Objetivo

Convertir la documentación y conocimiento operativo del servidor Aviva Chat / Element Server Suite en una colección de Hermes skills reutilizables para el perfil `aviva`, de modo que los agentes carguen instrucciones precisas sólo cuando vayan a trabajar con el servidor.

Esta fase es sólo especificación e inventario. No ejecuta comandos contra el servidor, no modifica Kubernetes, no rota secretos y no lanza workers.

## Ubicación propuesta de los skills

Skills locales del perfil Aviva:

- `~/.hermes/profiles/aviva/skills/aviva-chat/aviva-chat-server/SKILL.md`
- `~/.hermes/profiles/aviva/skills/aviva-chat/aviva-chat-access/SKILL.md`
- `~/.hermes/profiles/aviva/skills/aviva-chat/aviva-chat-backup-restore/SKILL.md`
- `~/.hermes/profiles/aviva/skills/aviva-chat/aviva-chat-upgrade/SKILL.md`
- `~/.hermes/profiles/aviva/skills/aviva-chat/aviva-chat-users-tokens/SKILL.md`
- `~/.hermes/profiles/aviva/skills/aviva-chat/aviva-chat-push/SKILL.md`
- `~/.hermes/profiles/aviva/skills/aviva-chat/aviva-chat-troubleshooting/SKILL.md`

Razonamiento:

- Son específicos del perfil Aviva y no deberían vivir en skills globales.
- La categoría `aviva-chat` permite agruparlos sin mezclar con skills generales de `devops`.
- El skill `aviva-chat-server` debe ser el índice/base: arquitectura, límites de seguridad, qué skill cargar para cada operación.

## Cómo funciona en Hermes

Hermes carga skills en el prompt cuando:

1. El usuario los invoca explícitamente con `/skill <name>` o mediante `skill_view`.
2. El agente detecta que una tarea coincide con la descripción del skill y lo carga antes de responder.
3. Un cron job o proceso futuro se configura con `skills=[...]`.

Por eso cada skill debe tener una descripción clara tipo “Use when…”, por ejemplo:

- `aviva-chat-access`: “Use when connecting to Aviva Chat server, opening the SSH tunnel, configuring kubectl, or checking cluster access.”
- `aviva-chat-upgrade`: “Use when planning or executing an ESS/Matrix/K3s/cert-manager upgrade for Aviva Chat.”

## Inventario encontrado en este repo

### Arquitectura actual documentada

Fuentes:

- `README.md`
- `infra/ess/README.md`
- `infra/ess/deploy.sh`
- `infra/ess/values/ess.yaml`
- `infra/ess/MIGRATION_RUNBOOK.md`

Datos documentados:

- Dominio principal: `chat.avivaeu.org`
- Servidor: `91.98.33.147`
- Hosting: Hetzner
- VM: `cx33`, Ubuntu 24.04
- Kubernetes: K3s single-node `v1.34.4+k3s1`
- Ingress: Traefik, default de K3s
- cert-manager: `v1.19.4`, instalado vía Helm OCI
- ESS Helm chart: `oci://ghcr.io/element-hq/ess-helm/matrix-stack`
- ESS release documentado: `26.2.3`
- Namespace Kubernetes: `ess`

### DNS y endpoints documentados

Todos apuntan al IP `91.98.33.147`:

- `chat.avivaeu.org`
- `web.chat.avivaeu.org`
- `matrix.chat.avivaeu.org`
- `admin.chat.avivaeu.org`
- `account.chat.avivaeu.org`
- `mrtc.chat.avivaeu.org`
- `push.chat.avivaeu.org`

Endpoints públicos:

- Element Web: `https://chat.avivaeu.org`
- Element Web directo: `https://web.chat.avivaeu.org`
- Element Admin: `https://admin.chat.avivaeu.org`
- MAS / Account: `https://account.chat.avivaeu.org`
- Synapse: `https://matrix.chat.avivaeu.org`
- RTC: `https://mrtc.chat.avivaeu.org`
- Sygnal push: `https://push.chat.avivaeu.org/_matrix/push/v1/notify`

### Acceso SSH/kubectl documentado

Fuentes:

- `README.md`
- `infra/ess/README.md`
- `/Users/fa2gq58/.zshrc`

SSH shortcut esperado:

- Host: `aviva-chat`
- HostName: `91.98.33.147`
- User: `root`
- IdentityFile: `~/.ssh/id_aviva`

Acceso kubectl local por túnel SSH:

- Túnel: `6443` local hacia `127.0.0.1:6443` remoto
- Kubeconfig local: `~/.kube/aviva-chat.yaml`
- Contexto: `aviva-chat`
- Funciones disponibles en `/Users/fa2gq58/.zshrc`:
  - `proxy-aviva-chat-on`
  - `proxy-aviva-chat-off`

Notas de seguridad:

- El kubeconfig de K3s da acceso admin al cluster.
- No debe copiarse ni incluirse en skills, repo, logs o prompts.

### Automatización existente

Fuentes:

- `infra/ess/deploy.sh`
- `infra/ess/teardown.sh`
- `infra/ess/values/ess.yaml`
- `infra/ess/manifests/clusterissuer.yaml`

`deploy.sh` instala o configura:

1. DNS check local.
2. K3s remoto.
3. Helm remoto.
4. cert-manager.
5. ClusterIssuer `letsencrypt-prod`.
6. ESS Helm release `ess` en namespace `ess`.

Observación importante:

- `deploy.sh` escribe valores ESS mínimos en `/root/ess-config-values/ess.yaml` en el servidor.
- El archivo local `infra/ess/values/ess.yaml` contiene `web.chat.avivaeu.org` para Element Web, pero el script `deploy.sh` usa `${DOMAIN}` para `elementWeb.ingress.host`; esto debería revisarse antes de tratarlo como fuente de verdad única.

### Configuración ESS adicional encontrada

Archivos:

- `infra/ess/values/auth-media-retention.yaml`
- `infra/ess/values/auth-media-autojoin.yaml`
- `infra/ess/values/smtp.yaml`

`auth-media-retention.yaml` documenta:

- Postgres storage: `12Gi`
- MAS password registration enabled.
- Registration token required.
- Password recovery enabled.
- Synapse media max upload size: `5M`
- Synapse media storage: `50Gi`
- Retention enabled con default max lifetime `30d`.

`auth-media-autojoin.yaml` documenta autojoin a:

- `#aviva:chat.avivaeu.org`
- `#publico:chat.avivaeu.org`

### Push gateway / Sygnal documentado

Fuentes:

- `infra/ess/README.md`
- `infra/ess/manifests/sygnal-*`

Se documenta Sygnal separado del chart ESS:

- APNs para iOS con secret Kubernetes `sygnal-apns`
- FCM v1 para Android con secret Kubernetes `sygnal-fcm`
- App IDs esperados:
  - iOS nuevo: `org.avivaeu.chat.ios.prod`
  - iOS legacy: `org.avivaeu.chat`
  - Android: `org.avivaeu.chat.android`
- Endpoint esperado: `https://push.chat.avivaeu.org/_matrix/push/v1/notify`
- Verificación esperada para GET: HTTP `405`

### Migración / rollback documentados

Fuente:

- `infra/ess/MIGRATION_RUNBOOK.md`

Contiene runbook para:

- Snapshot Hetzner.
- Crear VM nueva desde snapshot.
- Validar K3s y pods.
- Actualizar DNS vía STRATO DynDNS.
- Validar endpoints.
- Recuperar pods críticos tras migración.
- Rollback por DNS.

Notas:

- Credenciales STRATO DynDNS deben vivir fuera de git, por ejemplo `.secrets/.dyndns`.
- No deben incluirse secretos reales en skills.

## Skills propuestos

### 1. `aviva-chat-server`

Propósito:

Skill índice/base para cualquier tarea sobre el servidor Aviva Chat.

Debe contener:

- Arquitectura resumida.
- Dominios y endpoints.
- Componentes: Hetzner, K3s, Traefik, cert-manager, ESS, MAS, Synapse, Element Web/Admin, Sygnal.
- Namespace y release names.
- Reglas de seguridad.
- Tabla: “si vas a hacer X, carga skill Y”.

No debe contener:

- Kubeconfig.
- SSH private key.
- Passwords.
- Tokens de registro reales.
- APNs/FCM/STRATO secrets.

### 2. `aviva-chat-access`

Propósito:

Acceso seguro y verificación pasiva del cluster.

Debe contener:

- Cómo usar `ssh aviva-chat`.
- Cómo abrir/cerrar túnel con `proxy-aviva-chat-on/off`.
- Cómo usar `KUBECONFIG=~/.kube/aviva-chat.yaml` y contexto `aviva-chat`.
- Comandos read-only permitidos para discovery.
- Qué comandos requieren confirmación explícita.
- Cómo comprobar salud: nodes, pods, ingress, certs, helm status.

Pendiente:

- Confirmar si `~/.kube/aviva-chat.yaml` existe y funciona.
- Confirmar si el host SSH `aviva-chat` sigue siendo válido.

### 3. `aviva-chat-backup-restore`

Propósito:

Backups antes de upgrades/migraciones/cambios peligrosos y pasos de restore.

Debe contener:

- Snapshot Hetzner como safety point.
- Backup lógico o físico de Postgres/Synapse si aplica.
- Qué volúmenes/PVCs existen y cómo identificarlos.
- Qué se debe verificar antes de declarar backup válido.
- Ruta de restore o rollback.
- Diferencia entre snapshot VM, backup DB y backup de media.

Pendiente crítico:

- Investigar la estructura real de PVCs y bases de datos del chart ESS actual.
- Definir comando oficial de backup para Postgres del despliegue ESS.
- Definir si se respaldan media store y configuración de MAS/Synapse por separado.

### 4. `aviva-chat-upgrade`

Propósito:

Planificar y ejecutar upgrades seguros de ESS, Matrix/Synapse/MAS, cert-manager, K3s o componentes relacionados.

Debe contener:

- Nunca upgrade directo sin backup y plan de rollback.
- Cómo revisar release actual y valores efectivos.
- Cómo revisar chart latest y notas de release.
- Cómo detectar breaking changes.
- Orden sugerido: discovery → backup → dry-run/template → maintenance window → helm upgrade → health checks → rollback si falla.
- Validaciones post-upgrade.

Pendiente crítico:

- Identificar cómo obtener la versión real instalada desde Helm en el cluster.
- Confirmar versión actual real vs documentación (`26.2.3`).
- Investigar notas oficiales de ESS para rutas de upgrade.

### 5. `aviva-chat-users-tokens`

Propósito:

Operaciones de usuarios, admins, registration tokens y recuperación de acceso.

Debe contener:

- Crear primer/super admin con `mas-cli manage register-user`.
- Crear usuarios/admins con password temporal.
- Flujo para tokens de registro si MAS lo soporta en este despliegue.
- Qué datos pedir al usuario antes de ejecutar.
- Cómo evitar exponer passwords/tokens en logs.

Pendiente crítico:

- Confirmar comandos exactos de MAS para registration tokens en la versión instalada.
- Definir política: generar password/token localmente o pedir al usuario que lo entregue.
- Confirmar si el comando debe correr con `kubectl exec` en `deployment/ess-matrix-authentication-service`.

### 6. `aviva-chat-push`

Propósito:

Operar Sygnal/APNs/FCM para notificaciones iOS/Android.

Debe contener:

- Arquitectura Sygnal separada de ESS.
- Secrets Kubernetes `sygnal-apns` y `sygnal-fcm`.
- App IDs esperados.
- Cómo aplicar manifiestos.
- Cómo verificar logs y endpoint.
- Cómo rotar APNs/FCM sin commitear secretos.

Pendiente:

- Confirmar estado real de pods Sygnal.
- Confirmar si las plantillas actuales tienen todos los campos necesarios.
- Documentar prueba end-to-end desde cliente Matrix.

### 7. `aviva-chat-troubleshooting`

Propósito:

Diagnóstico y recuperación de incidentes.

Debe contener:

- Checklist read-only inicial.
- Logs por componente: Synapse, MAS, Element Web/Admin, Postgres, HAProxy, Sygnal, cert-manager, Traefik.
- Problemas comunes: certs pendientes, pods stuck, ingress 404/502, push 405 esperado, DNS incorrecto, storage lleno.
- Acciones de recuperación con confirmación explícita.
- Cuándo escalar o detenerse.

Pendiente:

- Mapear nombres reales de deployments/statefulsets en este chart.
- Documentar umbrales de disco/memoria y comandos de inspección.

### 8. `aviva-chat-migration`

Propósito:

Convertir `infra/ess/MIGRATION_RUNBOOK.md` en skill operativo.

Debe contener:

- Snapshot Hetzner.
- Crear VM desde snapshot.
- DNS STRATO DynDNS.
- Validar endpoints.
- Rollback DNS.
- Limpieza post-migración.

Puede ser skill separado o referencia dentro de `aviva-chat-backup-restore`.

## Información que todavía falta documentar

### Acceso y credenciales

- Confirmar archivo SSH config real y host `aviva-chat`.
- Confirmar dónde vive el kubeconfig local y permisos.
- Confirmar si `hcloud` está instalado y autenticado.
- Confirmar ubicación local de secretos fuera del repo:
  - STRATO DynDNS password.
  - APNs `.p8`.
  - Firebase service account JSON.
  - Cualquier SMTP secret.

### Estado real del cluster

Discovery read-only pendiente:

- `kubectl get nodes -o wide`
- `kubectl -n ess get pods -o wide`
- `kubectl -n ess get pvc`
- `kubectl -n ess get ingress`
- `helm -n ess list`
- `helm -n ess get values ess --all`
- `helm -n ess status ess`
- `kubectl -n cert-manager get pods`

Estos comandos requieren túnel y deben ejecutarse sólo tras confirmación explícita.

### Backups

- Método oficial/validado para Postgres ESS.
- Dónde vive media store Synapse.
- Tamaño real de PVCs.
- Retención esperada.
- Dónde guardar backups.
- Cómo probar restore sin dañar producción.

### Upgrade

- Versión real instalada.
- Última versión ESS estable.
- Release notes relevantes.
- Rutas intermedias si no se puede saltar directo.
- Compatibilidad con K3s/cert-manager actuales.
- Plan de rollback Helm/VM snapshot.

### Usuarios/tokens

- Comando exacto para crear registration token en MAS.
- Política de expiración/cupo de tokens.
- Cómo auditar usuarios/admins existentes sin exponer datos sensibles.

## Reglas de seguridad para todos los skills

1. No ejecutar comandos mutating sin confirmación explícita del usuario.
2. Separar discovery read-only de ejecución.
3. No guardar secretos en skills ni en repo.
4. No pegar kubeconfig, private keys, tokens, passwords ni service account JSON en la conversación.
5. Antes de upgrade/migración/rotación: backup/snapshot + rollback plan + validación de salud inicial.
6. Usar placeholders para secretos: `<registration-token>`, `<strong-password>`, `<secret-file>`.
7. Preferir comandos que no impriman secretos en stdout.
8. Si hay que generar un token/password, decidir antes si lo genera el usuario o una herramienta local y cómo se comunica.

## Propuesta de orden de trabajo

### Fase A: skills sin tocar servidor

Crear skills iniciales desde documentación existente:

1. `aviva-chat-server`
2. `aviva-chat-access`
3. `aviva-chat-push`
4. `aviva-chat-migration`

Resultado esperado:

- Skills útiles para orientar agentes.
- Marcas explícitas de “pendiente confirmar en cluster”.

### Fase B: discovery read-only con aprobación

Abrir túnel y ejecutar comandos read-only para capturar estado real:

1. Acceso/kubectl.
2. Inventario Kubernetes/Helm/PVCs.
3. Versiones reales.
4. Nombres reales de workloads.
5. Estado de Sygnal/cert-manager.

Resultado esperado:

- Actualizar `aviva-chat-server`, `aviva-chat-access`, `aviva-chat-troubleshooting`.
- Base sólida para backup/upgrade.

### Fase C: skills operativos sensibles

Crear o completar:

1. `aviva-chat-backup-restore`
2. `aviva-chat-upgrade`
3. `aviva-chat-users-tokens`
4. `aviva-chat-troubleshooting`

Resultado esperado:

- Procedimientos con prechecks, comandos, confirmaciones, rollback y verificación.

## Criterios de aceptación de esta especificación

- Existe inventario de documentación actual.
- Hay lista clara de skills a crear.
- Cada skill tiene propósito, ubicación y pendientes.
- Se separa documentación no sensible de secretos.
- Se define que discovery del servidor requiere aprobación explícita.
- No se ejecutó ningún cambio contra producción.
