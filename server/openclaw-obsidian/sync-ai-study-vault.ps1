[CmdletBinding()]
param(
  [string]$VaultPath = 'D:\AI-自学OS\server\data\obsidian-vault\1',
  [string]$OpenClawPath = 'openclaw',
  [string]$StatePath = 'D:\AI-自学OS\server\data\openclaw-ai-study-ingest.json'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $VaultPath -PathType Container)) {
  throw "Vault not found: $VaultPath"
}

$stateDirectory = Split-Path -Parent $StatePath
if ($stateDirectory -and -not (Test-Path -LiteralPath $stateDirectory)) {
  New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
}

$knownHashes = @{}
if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
  try {
    $saved = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    foreach ($property in $saved.PSObject.Properties) {
      $knownHashes[$property.Name] = [string]$property.Value
    }
  } catch {
    Write-Warning "Cannot read ingest state; rebuilding it: $StatePath"
  }
}

# These are AILearningOS-owned source folders. OpenClaw-managed folders such as
# sources/, entities/, concepts/ and reports/ are deliberately not traversed.
$sourceFolders = @('captures', 'Learning', 'Recording', 'Work', 'Personal', 'Inbox')
$files = @(
  foreach ($folder in $sourceFolders) {
    $directory = Join-Path $VaultPath $folder
    if (Test-Path -LiteralPath $directory -PathType Container) {
      Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.md'
    }
  }
)

$nextHashes = @{}
$imported = 0
$failed = 0

foreach ($file in $files) {
  $fullPath = $file.FullName
  $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
  if ($knownHashes.ContainsKey($fullPath) -and $knownHashes[$fullPath] -eq $hash) {
    $nextHashes[$fullPath] = $hash
    continue
  }

  Write-Host "Ingesting: $fullPath"
  & $OpenClawPath wiki ingest $fullPath
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "wiki ingest failed with exit code ${LASTEXITCODE}: $fullPath"
    $failed += 1
    continue
  }
  $nextHashes[$fullPath] = $hash
  $imported += 1
}

if ($imported -gt 0) {
  Write-Host "Compiling memory-wiki after $imported changed file(s)."
  & $OpenClawPath wiki compile
  if ($LASTEXITCODE -ne 0) {
    throw "wiki compile failed with exit code $LASTEXITCODE"
  }
} else {
  Write-Host 'No new or changed AILearningOS notes.'
}

($nextHashes | ConvertTo-Json -Depth 3) |
  Set-Content -LiteralPath $StatePath -Encoding UTF8

if ($failed -gt 0) {
  throw "$failed file(s) failed to ingest. The successful file hashes were saved; failed files will retry next run."
}

Write-Host "AILearningOS vault ingest complete. Imported: $imported."
