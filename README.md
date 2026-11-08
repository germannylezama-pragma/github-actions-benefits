# github-actions-benefits

Ventajas y poder de GitHub Actions, con una demo real: un pipeline **reutilizable** en **3 fases** donde **la rama decide el ambiente**, analiza seguridad y costo antes de desplegar, lo resume en el Job Summary y solo despliega desde ramas `deploy/*`.

## Las 3 fases

```
            ┌─────────────── Fase 1 · Análisis ───────────────┐   Fase 2 · Revisión     Fase 3 · Deploy
rama ─► 🧭 ─┤ 🔐 Checkov  ∥  🔎 Trivy  ∥  💰 Infracost          ├─► 📋 Summary + gate ─► 🚀 solo ramas deploy/*
            └─────────────────────────────────────────────────┘
```

| Rama | Ambiente | Fase 1 y 2 | Fase 3 · Deploy |
|---|---|---|---|
| `dev` | dev | ✅ | — |
| `staging` | staging | ✅ | — |
| `main` | prod | ✅ | — |
| `deploy/dev` | dev | ✅ | ✅ |
| `deploy/staging` | staging | ✅ | ✅ |
| `deploy/prod` | prod | ✅ | ✅ con aprobación |
| PR hacia cualquiera de ellas | el de la rama **destino** | ✅ | — (despliega el merge) |
| cualquier otra rama (Run workflow) | dev | ✅ | — |

Flujo típico: `feature/x` → PR a `dev` → PR a `staging` → PR a `main` → PR a `deploy/prod` (aprobación) → producción.

## Qué muestra de GitHub Actions

| Capacidad | Dónde |
|---|---|
| **Workflows reutilizables** (`workflow_call`) | [`reusable-contexto.yml`](.github/workflows/reusable-contexto.yml) (rama → ambiente), [`reusable-infra-scan.yml`](.github/workflows/reusable-infra-scan.yml) (fases 1 y 2), [`reusable-deploy.yml`](.github/workflows/reusable-deploy.yml) (fase 3) |
| **Llamarlos desde otro repo / otra rama** | [infra-equipo](https://github.com/germannylezama-pragma/infra-equipo) los usa con `uses: …@main` |
| **Matriz** | [`nightly-audit.yml`](.github/workflows/nightly-audit.yml) (los 3 ambientes en paralelo, cada noche) y [`matrix-demo.yml`](.github/workflows/matrix-demo.yml) (SO × Node, 9 jobs) |
| **Control de ambientes** | environments `dev`, `staging`, `prod`: aprobación, ramas permitidas, secrets por ambiente, `concurrency` |
| **Disparadores** | PR, push, manual (`workflow_dispatch`), API (`repository_dispatch`), cron (`schedule`) |

Desde otro sistema por API:
```bash
gh api repos/germannylezama-pragma/github-actions-benefits/dispatches \
  -f event_type=deploy-infra -F 'client_payload[environment]=staging' -F 'client_payload[deploy]=true'
```

La infraestructura de [`infra/terraform`](infra/terraform) tiene **errores a propósito** (SSH abierto, base de datos pública y sin cifrar…) para que el gate se vea bloqueando. Los tamaños cambian por ambiente en [`infra/terraform/env/`](infra/terraform/env).

## Configuración

**Ramas:** `dev`, `staging`, `main`, `deploy/dev`, `deploy/staging`, `deploy/prod`.

**Settings → Environments:**

| Environment | Protección sugerida | Variables / secrets propios |
|---|---|---|
| `dev` | ninguna | `AWS_ROLE_ARN` de la cuenta dev |
| `staging` | *Wait timer* de 5 min | `AWS_ROLE_ARN` de staging |
| `prod` | *Required reviewers* + *Deployment branches*: solo `deploy/prod` | `AWS_ROLE_ARN` de prod |

**Settings → Secrets and variables → Actions:**

| Tipo | Nombre | Para qué |
|---|---|---|
| Secret | `INFRACOST_API_KEY` | Estimar costos (cuenta gratis en infracost.io) |
| Variable | `ENFORCE_GATE` | `false` para solo reportar sin bloquear (útil para ver el deploy en la demo) |

Sin `AWS_ROLE_ARN` el deploy es **simulado**, pero los environments, aprobaciones e historial funcionan igual.
