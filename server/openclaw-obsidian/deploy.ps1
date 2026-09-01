param(
  [string]$OpenClawDir = (Get-Location).Path,
  [string]$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
  [int]$ObsidianUserId = 1,
  [string]$VaultPath = ''
)

$ErrorActionPreference = 'Stop'
$composeFile = Join-Path $OpenClawDir 'docker-compose.yml'
$overlayFile = Join-Path $PSScriptRoot 'docker-compose.obsidian.yml'

if (-not (Test-Path -LiteralPath $composeFile)) {
  throw "OpenClaw docker-compose.yml was not found in $OpenClawDir. Pass -OpenClawDir with the official OpenClaw repository root."
}

if ([string]::IsNullOrWhiteSpace($VaultPath)) {
  $VaultPath = Join-Path $ProjectDir "server\data\obsidian-vault\$ObsidianUserId"
}

New-Item -ItemType Directory -Force -Path $VaultPath | Out-Null
$agentsPath = Join-Path $VaultPath 'AGENTS.md'
if (-not (Test-Path -LiteralPath $agentsPath)) {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AGENTS.md') -Destination $agentsPath
}

$env:AI_STUDY_OBSIDIAN_VAULT_HOST_PATH = (Resolve-Path -LiteralPath $VaultPath).Path
if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_TZ)) {
  $env:OPENCLAW_TZ = 'Asia/Shanghai'
}

function Invoke-OpenClawCompose {
  param([string[]]$Arguments)
  Push-Location $OpenClawDir
  try {
    & docker compose -f $composeFile -f $overlayFile @Arguments
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed with exit code $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
}

Write-Host 'Validating OpenClaw + AILearningOS Compose configuration...'
Invoke-OpenClawCompose @('config', '--quiet')

Write-Host "Starting OpenClaw Gateway with the mounted vault: $($env:AI_STUDY_OBSIDIAN_VAULT_HOST_PATH)"
Invoke-OpenClawCompose @('up', '-d', 'openclaw-gateway')

Write-Host 'Running the read-only health probe...'
Invoke-OpenClawCompose @('exec', '-T', 'openclaw-gateway', 'sh', '-lc', 'curl -fsS http://127.0.0.1:18789/healthz')

Write-Host ''
Write-Host 'Gateway is running. Apply openclaw.obsidian.json5 to openclaw.json, then run:'
Write-Host '  docker compose -f docker-compose.yml -f docker-compose.obsidian.yml run --rm openclaw-cli wiki init'
Write-Host '  docker compose -f docker-compose.yml -f docker-compose.obsidian.yml run --rm openclaw-cli wiki compile'
Write-Host '  docker compose -f docker-compose.yml -f docker-compose.obsidian.yml run --rm openclaw-cli wiki lint'
