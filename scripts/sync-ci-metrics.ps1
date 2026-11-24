<#
.SYNOPSIS
  Publica en el Pushgateway local las metricas del ultimo pipeline de GitHub Actions
  (cobertura, pruebas, tiempos de despliegue) para verlas en el dashboard de Grafana.

.DESCRIPTION
  El job "4c. Metricas del pipeline" deja el archivo ci-metrics.prom como artefacto de cada run.
  Este script busca el ultimo run terminado que tenga ese artefacto, lo descarga con GitHub CLI (gh)
  y lo envia al Pushgateway (http://localhost:9091). Prometheus lo recolecta desde ahi.

.EXAMPLE
  .\scripts\sync-ci-metrics.ps1
  .\scripts\sync-ci-metrics.ps1 -Branch main
  .\scripts\sync-ci-metrics.ps1 -Loop                      # repite cada 60 segundos
  .\scripts\sync-ci-metrics.ps1 -File .\ci-metrics.prom    # usa un archivo descargado a mano
#>
param(
  [string]$File,
  [string]$Branch,
  [switch]$Loop,
  [int]$IntervalSeconds = 60,
  [string]$Pushgateway = "http://localhost:9091"
)

$ErrorActionPreference = "Stop"

function Get-LatestMetricsFile {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "No se encontro GitHub CLI (gh). Instalalo con 'winget install GitHub.cli' y luego 'gh auth login', o usa -File con el artefacto descargado a mano."
  }

  $runs = gh run list --workflow ci-cd.yml --limit 15 --json databaseId,status,headBranch,conclusion,displayTitle | ConvertFrom-Json
  $runs = $runs | Where-Object { $_.status -eq "completed" }
  if ($Branch) { $runs = $runs | Where-Object { $_.headBranch -eq $Branch } }

  foreach ($run in $runs) {
    $dir = Join-Path $env:TEMP "ci-metrics-$($run.databaseId)"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    gh run download $run.databaseId -n ci-metrics -D $dir 2>$null
    $path = Join-Path $dir "ci-metrics.prom"
    if ($LASTEXITCODE -eq 0 -and (Test-Path $path)) {
      Write-Host "Run #$($run.databaseId) ($($run.headBranch), $($run.conclusion)): $($run.displayTitle)"
      return $path
    }
  }
  throw "Ningun run reciente tiene el artefacto 'ci-metrics'. Espera a que termine un pipeline con el job 4c."
}

function Publish-Metrics([string]$path) {
  # el Pushgateway exige saltos de linea LF y un salto al final
  $text = [IO.File]::ReadAllText((Resolve-Path $path)).Replace("`r`n", "`n")
  if (-not $text.EndsWith("`n")) { $text += "`n" }
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)

  # PUT reemplaza todas las metricas anteriores del grupo job="ci_pipeline"
  Invoke-WebRequest -Method Put -Uri "$Pushgateway/metrics/job/ci_pipeline" -Body $bytes `
    -ContentType "text/plain; version=0.0.4" -UseBasicParsing | Out-Null

  Write-Host "Metricas publicadas en $Pushgateway :"
  $text.Split("`n") | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object { Write-Host "  $_" }
}

do {
  try {
    $path = if ($File) { $File } else { Get-LatestMetricsFile }
    Publish-Metrics $path
  } catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $Loop) { exit 1 }
  }
  if ($Loop) { Start-Sleep -Seconds $IntervalSeconds }
} while ($Loop)