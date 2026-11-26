#!/usr/bin/env bash
# Activa la protección de la rama main con los checks del pipeline como obligatorios.
# Requisitos: GitHub CLI (gh) con sesión iniciada con permisos de administrador del repo
#             (en repos privados con plan gratis GitHub no permite protección de ramas: hay que usar repo público).
# Uso:  bash scripts/branch-protection.sh            (usa el repo actual)
#       bash scripts/branch-protection.sh dueño/repo
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "Aplicando protección de rama a main en $REPO ..."

gh api -X PUT "repos/$REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "1. Build y pruebas (JUnit + JaCoCo)",
      "2. Seguridad de dependencias (Snyk)",
      "2. Calidad de código (SonarCloud)",
      "2c. Auditoría de cumplimiento",
      "3. Imagen Docker + escaneo de seguridad",
      "4b. Despliegue en Kubernetes (kind)"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

echo "Listo. Estado actual:"
gh api "repos/$REPO/branches/main/protection" --jq '{checks: .required_status_checks.contexts, reviews: .required_pull_request_reviews.required_approving_review_count}'
