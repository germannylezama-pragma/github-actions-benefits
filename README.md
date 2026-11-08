# github-actions-benefits

Ventajas y poder de GitHub Actions, con una demo real: un pipeline **reutilizable** que analiza la infraestructura de **varios ambientes en paralelo** (seguridad + costo), lo resume en el Job Summary y **promueve** el despliegue dev → staging → prod con controles por ambiente.

## Qué muestra

| Capacidad | Dónde verla |
|---|---|
| **Workflows reutilizables** (`workflow_call`) | [`reusable-infra-scan.yml`](.github/workflows/reusable-infra-scan.yml), [`reusable-deploy.yml`](.github/workflows/reusable-deploy.yml) |
| **Llamar desde otro repo o desde otra rama** | [`examples/otro-repo/.github/workflows/infra.yml`](examples/otro-repo/.github/workflows/infra.yml) (`uses: …@main`, `@feature/x`, `@v1`) |
| **Matriz**: un YAML, muchas ejecuciones | `analizar` en [`infra-pipeline.yml`](.github/workflows/infra-pipeline.yml) (dev/staging/prod con presupuesto propio) y [`matrix-demo.yml`](.github/workflows/matrix-demo.yml) (SO × Node) |
| **Control de ambientes** | `deploy-*` + environments `dev`, `staging`, `prod` |
| **Varios disparadores** | PR, push, manual con inputs (`workflow_dispatch`), desde otro sistema (`repository_dispatch`) |
| **Seguridad y costo antes de desplegar** | Checkov + Trivy + Infracost → [`summary.sh`](.github/scripts/summary.sh) → gate |

```
                ┌─ Análisis · dev      (Checkov ∥ Trivy ∥ Infracost → Summary → gate)
PR / push / ────┼─ Análisis · staging  (…)                                           ─→ deploy-dev ─→ deploy-staging ─→ ✋ deploy-prod
manual / API    └─ Análisis · prod     (…)
```

- **PR**: solo analiza los 3 ambientes. Cada uno deja su tabla en el Summary.
- **Push a `main`**: analiza y promueve dev → staging → prod.
- **Manual** (Actions → Run workflow): eliges la **rama** y **hasta qué ambiente** desplegar.
- **API / otro repo**:
  ```bash
  gh api repos/germannylezama-pragma/github-actions-benefits/dispatches \
    -f event_type=deploy-infra -F 'client_payload[hasta]=staging'
  ```

La infraestructura de [`infra/terraform`](infra/terraform) tiene **errores a propósito** (SSH abierto, base de datos pública y sin cifrar…) para que el gate se vea bloqueando. Los tamaños cambian por ambiente en [`infra/terraform/env/`](infra/terraform/env).

## Configuración

**Settings → Environments** (crear `dev`, `staging`, `prod`):

| Environment | Protección sugerida | Variables / secrets propios |
|---|---|---|
| `dev` | ninguna: despliegue automático | `AWS_ROLE_ARN` de la cuenta dev |
| `staging` | *Wait timer* de 5 min | `AWS_ROLE_ARN` de staging |
| `prod` | *Required reviewers* + *Deployment branches*: solo `main` | `AWS_ROLE_ARN` de prod |

**Settings → Secrets and variables → Actions** (repo):

| Tipo | Nombre | Para qué |
|---|---|---|
| Secret | `INFRACOST_API_KEY` | Estimar costos (gratis en infracost.io). Sin ella se omite el costo |
| Variable | `ENFORCE_GATE` | `false` para solo reportar sin bloquear (útil para ver la promoción en la demo) |

Sin `AWS_ROLE_ARN` el deploy es **simulado**, pero los environments, aprobaciones e historial funcionan igual.
