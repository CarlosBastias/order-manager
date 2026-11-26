<#
.SYNOPSIS
  Levanta en local la malla de servicios: cluster kind + Istio + Prometheus + Kiali + order-manager
  con sidecar + un generador de trafico, para ver el grafo de la aplicacion en Kiali.

.DESCRIPTION
  Sigue los pasos de la guia "Istio y Kiali en EKS" del curso, pero sobre un cluster kind local
  (no hay cuentas AWS disponibles). Es idempotente: si algo ya existe, lo reutiliza.

    1. Crea el cluster kind (si no existe)
    2. Descarga istioctl (version mas reciente o la indicada con -IstioVersion)
    3. Instala Istio con recursos minimos (mismo comando que el material de clase)
    4. Instala Prometheus y Kiali desde los addons de Istio
    5. Construye la imagen de la app y la carga en el cluster
    6. Despliega order-manager con inyeccion automatica del sidecar
    7. Despliega el generador de trafico

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\istio-kiali-kind.ps1
  powershell -ExecutionPolicy Bypass -File .\scripts\istio-kiali-kind.ps1 -Delete   # borra el cluster
#>
param(
  [string]$Cluster = "order-manager-mesh",
  [string]$IstioVersion = "",
  [switch]$Delete
)

# los comandos externos (kind, kubectl) escriben avisos en stderr: se revisa el codigo de salida a mano
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Step([string]$text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Check([string]$what) {
  if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: fallo '$what'" -ForegroundColor Red; exit 1 }
}
function Need([string]$cmd, [string]$hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Host "Falta '$cmd'. $hint" -ForegroundColor Red; exit 1
  }
}

Need docker  "Instala Docker Desktop y dejalo abierto."
Need kubectl "Instalalo con: winget install -e --id Kubernetes.kubectl"
Need kind    "Instalalo con: winget install -e --id Kubernetes.kind  (y abre una terminal nueva)"

if ($Delete) {
  Step "Borrando el cluster $Cluster"
  kind delete cluster --name $Cluster
  exit 0
}

# ---------------------------------------------------------------------------
Step "1/7 Cluster kind '$Cluster'"
$existing = (kind get clusters 2>&1 | Out-String)
if ($existing -match "(?m)^$Cluster\s*$") {
  Write-Host "El cluster ya existe, se reutiliza."
} else {
  kind create cluster --name $Cluster --wait 180s
  Check "kind create cluster"
}
kubectl config use-context "kind-$Cluster" | Out-Null
Check "kubectl config use-context"
kubectl get nodes

# ---------------------------------------------------------------------------
Step "2/7 istioctl"
$istioRoot = Join-Path $root ".istio"
if (-not $IstioVersion) {
  $IstioVersion = (Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/istio/istio/releases/latest").tag_name
}
$istioHome = Join-Path $istioRoot "istio-$IstioVersion"
$istioctl = Join-Path $istioHome "bin\istioctl.exe"
if (-not (Test-Path $istioctl)) {
  New-Item -ItemType Directory -Force -Path $istioRoot | Out-Null
  $zip = Join-Path $istioRoot "istio-$IstioVersion.zip"
  $base = "https://github.com/istio/istio/releases/download/$IstioVersion"
  Write-Host "Descargando Istio $IstioVersion ..."
  try {
    Invoke-WebRequest -UseBasicParsing "$base/istio-$IstioVersion-win-amd64.zip" -OutFile $zip
  } catch {
    Invoke-WebRequest -UseBasicParsing "$base/istio-$IstioVersion-win.zip" -OutFile $zip
  }
  Expand-Archive -Path $zip -DestinationPath $istioRoot -Force
  Remove-Item $zip
}
& $istioctl version --remote=false

# ---------------------------------------------------------------------------
Step "3/7 Instalando Istio (perfil demo con recursos minimos, como en el material de clase)"
# holdApplicationUntilProxyStarts: la app no arranca hasta que su sidecar este listo,
# asi la primera conexion a postgres no falla
& $istioctl install `
  --set profile=demo `
  --set values.pilot.resources.requests.memory=256Mi `
  --set values.pilot.resources.requests.cpu=100m `
  --set values.global.proxy.resources.requests.cpu=50m `
  --set values.global.proxy.resources.requests.memory=128Mi `
  --set meshConfig.defaultConfig.holdApplicationUntilProxyStarts=true `
  -y
Check "istioctl install"

# ---------------------------------------------------------------------------
Step "4/7 Prometheus y Kiali (addons de Istio)"
$addons = Join-Path $istioHome "samples\addons"
kubectl apply -f (Join-Path $addons "prometheus.yaml")
Check "prometheus"
# la primera vez kiali a veces falla porque sus CRD aun no estan listas: se reintenta una vez
kubectl apply -f (Join-Path $addons "kiali.yaml")
if ($LASTEXITCODE -ne 0) {
  Start-Sleep -Seconds 10
  kubectl apply -f (Join-Path $addons "kiali.yaml")
  Check "kiali"
}
kubectl -n istio-system rollout status deployment/prometheus --timeout=300s
kubectl -n istio-system rollout status deployment/kiali --timeout=300s

# ---------------------------------------------------------------------------
Step "5/7 Imagen de la app"
docker build -t order-manager:local .
Check "docker build"
kind load docker-image order-manager:local --name $Cluster
Check "kind load docker-image"

# ---------------------------------------------------------------------------
Step "6/7 Desplegando order-manager con sidecar de Istio"
kubectl apply -f k8s/00-namespace.yaml
Check "namespace"
# con esta etiqueta Istio agrega su proxy (sidecar) a cada pod nuevo del namespace
kubectl label namespace order-manager istio-injection=enabled --overwrite
Check "label istio-injection"

# la clave de la base no esta en el repositorio: se genera al azar y se guarda como Secret
kubectl -n order-manager get secret order-manager-db 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  $pass = -join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
  kubectl -n order-manager create secret generic order-manager-db --from-literal=POSTGRES_PASSWORD=$pass
  Check "secret"
}

kubectl apply -k k8s
Check "kubectl apply -k k8s"
kubectl -n order-manager rollout status deployment/postgres --timeout=300s
kubectl -n order-manager rollout status deployment/order-manager --timeout=420s

# ---------------------------------------------------------------------------
Step "7/7 Generador de trafico"
kubectl apply -f observability/istio/generador-trafico.yaml
Check "generador de trafico"
kubectl -n order-manager rollout status deployment/generador-trafico --timeout=180s

# ---------------------------------------------------------------------------
Step "Listo. Pods del namespace order-manager (cada uno debe mostrar 2/2: app + sidecar)"
kubectl -n order-manager get pods -o wide

Write-Host ""
Write-Host "Para abrir Kiali (deja esta terminal abierta):" -ForegroundColor Green
Write-Host "  kubectl -n istio-system port-forward svc/kiali 20001:20001"
Write-Host "  http://localhost:20001  ->  Traffic Graph  ->  namespace order-manager"
Write-Host ""
Write-Host "Para borrar todo al terminar:" -ForegroundColor Green
Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\istio-kiali-kind.ps1 -Delete"