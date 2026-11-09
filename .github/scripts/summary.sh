#!/usr/bin/env bash
# Construye el Job Summary a partir de los reportes de Checkov, Trivy e Infracost
# y decide si el despliegue queda aprobado (gate).
set -euo pipefail

R="${REPORTS_DIR:-reports}"
BUDGET="${MONTHLY_BUDGET_USD:-}" # vacío = el presupuesto lo valida el environment en el deploy
OUT="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
GATE_OUT="${GITHUB_OUTPUT:-/dev/null}"

ok()  { [ "$1" = "true" ] && echo "✅" || echo "❌"; }
sev() { case "$1" in CRITICAL) echo "🟥";; HIGH) echo "🟧";; MEDIUM) echo "🟨";; *) echo "⬜";; esac; }

# --- Checkov ---------------------------------------------------------------
ck_file="$R/checkov/checkov.json"
ck_ran=false; ck_passed=0; ck_failed=0
if [ -f "$ck_file" ]; then
  ck_ran=true
  # Con un solo framework Checkov devuelve un objeto; con varios, una lista.
  ck_json=$(jq 'if type=="array" then .[0] else . end' "$ck_file")
  ck_passed=$(jq '.summary.passed // 0' <<<"$ck_json")
  ck_failed=$(jq '.summary.failed // 0' <<<"$ck_json")
fi
ck_ok=$([ "$ck_ran" = true ] && [ "$ck_failed" -eq 0 ] && echo true || echo false)

# --- Trivy -----------------------------------------------------------------
tv_file="$R/trivy/trivy.json"
tv_ran=false; tv_c=0; tv_h=0; tv_m=0; tv_l=0
count_sev() { jq --arg s "$1" '[.Results[]?.Misconfigurations[]? | select(.Severity==$s)] | length' "$tv_file"; }
if [ -f "$tv_file" ]; then
  tv_ran=true
  tv_c=$(count_sev CRITICAL); tv_h=$(count_sev HIGH)
  tv_m=$(count_sev MEDIUM);   tv_l=$(count_sev LOW)
fi
tv_ok=$([ "$tv_ran" = true ] && [ $((tv_c + tv_h)) -eq 0 ] && echo true || echo false)

# --- Infracost -------------------------------------------------------------
ic_file="$R/infracost/infracost.json"
ic_base="$R/infracost/infracost-base.json"
ic_ran=false; cost_now=0; cost_base=0
if [ -f "$ic_file" ]; then
  ic_ran=true
  cost_now=$(jq -r '.totalMonthlyCost // "0"' "$ic_file")
  [ -f "$ic_base" ] && cost_base=$(jq -r '.totalMonthlyCost // "0"' "$ic_base")
fi
cost_delta=$(awk -v a="$cost_now" -v b="$cost_base" 'BEGIN{d=a-b; printf "%s$%.2f", (d<0 ? "-" : "+"), (d<0 ? -d : d)}')
cost_now_fmt=$(awk -v a="$cost_now" 'BEGIN{printf "%.2f", a}')
ic_ok=true
if [ -n "$BUDGET" ]; then
  ic_ok=$(awk -v a="$cost_now" -v b="$BUDGET" 'BEGIN{print (a<=b) ? "true" : "false"}')
fi
# Sin API key de Infracost el control se omite (no bloquea).
[ "$ic_ran" = false ] && ic_ok=true

# --- Gate ------------------------------------------------------------------
approved=$([ "$ck_ok" = true ] && [ "$tv_ok" = true ] && [ "$ic_ok" = true ] && echo true || echo false)
echo "approved=$approved" >> "$GATE_OUT"

# --- Summary ---------------------------------------------------------------
{
  echo "## 🛡️ Infra · Seguridad y costos · \`${ENVIRONMENT:-default}\`"
  echo
  echo "> \`${GITHUB_SHA:0:7}\` · ${GITHUB_EVENT_NAME:-local} · $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo
  echo "| Control | Resultado | Estado |"
  echo "|---|---|---|"
  if [ "$ck_ran" = true ]; then
    echo "| 🔐 **Checkov** (políticas IaC) | ${ck_passed} pasan · **${ck_failed} fallan** | $(ok "$ck_ok") |"
  else
    echo "| 🔐 **Checkov** | sin reporte | ❌ |"
  fi
  if [ "$tv_ran" = true ]; then
    echo "| 🔎 **Trivy** (misconfig) | 🟥 ${tv_c} critical · 🟧 ${tv_h} high · 🟨 ${tv_m} medium · ⬜ ${tv_l} low | $(ok "$tv_ok") |"
  else
    echo "| 🔎 **Trivy** | sin reporte | ❌ |"
  fi
  if [ "$ic_ran" = true ]; then
    if [ -n "$BUDGET" ]; then
      echo "| 💰 **Infracost** (costo mensual) | **\$${cost_now_fmt}/mes** (${cost_delta} vs base) · presupuesto \$${BUDGET} | $(ok "$ic_ok") |"
    else
      echo "| 💰 **Infracost** (costo mensual) | **\$${cost_now_fmt}/mes** (${cost_delta} vs base) · el presupuesto lo valida el environment en el deploy | ℹ️ |"
    fi
  else
    echo "| 💰 **Infracost** | omitido: falta el secret \`INFRACOST_API_KEY\` | ⏭️ |"
  fi
  echo
  if [ "$approved" = true ]; then
    echo "### ✅ Decisión: listo para desplegar"
    echo "Seguridad OK. En el deploy, el environment aplica sus reglas: aprobación y presupuesto (\`MONTHLY_BUDGET_USD\`)."
  else
    echo "### ⛔ Decisión: despliegue bloqueado"
    echo "Corrige los hallazgos de abajo."
  fi
  echo

  if [ "$ck_ran" = true ] && [ "$ck_failed" -gt 0 ]; then
    echo "<details><summary><b>🔐 Checkov: ${ck_failed} checks fallidos</b></summary>"
    echo
    echo "| Check | Recurso | Descripción |"
    echo "|---|---|---|"
    jq -r '.results.failed_checks[]? | "| `\(.check_id)` | `\(.resource)` | \(.check_name) |"' <<<"$ck_json" | head -n 25
    echo
    echo "</details>"
    echo
  fi

  if [ "$tv_ran" = true ] && [ $((tv_c + tv_h + tv_m + tv_l)) -gt 0 ]; then
    echo "<details><summary><b>🔎 Trivy: hallazgos por severidad</b></summary>"
    echo
    echo "| Sev. | ID | Recurso | Hallazgo | Cómo corregir |"
    echo "|---|---|---|---|---|"
    jq -r '
      [.Results[]?.Misconfigurations[]?]
      | sort_by({"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3}[.Severity] // 4)
      | .[]
      | "\(.Severity)\t\(.ID)\t\(.CauseMetadata.Resource // "-")\t\(.Title)\t\(.Resolution // "-")"' "$tv_file" \
    | head -n 25 \
    | while IFS=$'\t' read -r s id res title fix; do
        echo "| $(sev "$s") $s | \`$id\` | \`$res\` | $title | $fix |"
      done
    echo
    echo "</details>"
    echo
  fi

  if [ "$ic_ran" = true ]; then
    echo "<details><summary><b>💰 Infracost: recursos más caros</b></summary>"
    echo
    echo "| Recurso | Costo mensual |"
    echo "|---|---:|"
    jq -r '
      [.projects[].breakdown.resources[]? | select(.monthlyCost != null)]
      | sort_by(-(.monthlyCost | tonumber))
      | .[:8][]
      | "| `\(.name)` | $\(.monthlyCost | tonumber * 100 | round / 100) |"' "$ic_file"
    echo "| **Total** | **\$${cost_now_fmt}** |"
    echo
    echo "_Estimación con precios públicos de lista; no incluye uso variable (tráfico, requests) salvo que se configure \`infracost-usage.yml\`._"
    echo
    echo "</details>"
  fi
} >> "$OUT"

echo "Gate: approved=$approved (checkov=$ck_ok trivy=$tv_ok costo=$ic_ok)"
