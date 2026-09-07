param(
  [string]$DataDirectory = (Join-Path $PSScriptRoot 'data'),
  [ValidateRange(1, 65535)]
  [int]$Port = 8080,
  [string]$CodexCommand = 'codex',
  [switch]$DisableCodex
)

$ErrorActionPreference = 'Stop'

$serverExecutable = Join-Path $PSScriptRoot 'bin\server.exe'
if (-not (Test-Path -LiteralPath $serverExecutable -PathType Leaf)) {
  throw "AILearningOS backend was not found: $serverExecutable"
}

if ($DisableCodex) {
  $env:AILO_CODEX_GATEWAY_ENABLED = '0'
  Write-Host 'Codex gateway: disabled by request; Canvas and DeepSeek remain available.'
} else {
  $codex = Get-Command -Name $CodexCommand -All -CommandType Application,ExternalScript -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandType -eq 'Application' -and
    @('.exe', '.cmd', '.bat') -contains [System.IO.Path]::GetExtension($_.Source).ToLowerInvariant()
  } |
  Select-Object -First 1
if ($null -eq $codex) {
  throw 'Codex CLI is unavailable for this Windows service account. Install Codex and ensure codex.exe or codex.cmd is visible to the same account that starts AILearningOS.'
}

& $codex.Source --version
if ($LASTEXITCODE -ne 0) {
  throw "Codex CLI validation failed with exit code ${LASTEXITCODE}: $($codex.Source)"
}
  $env:AILO_CODEX_GATEWAY_ENABLED = '1'
  $env:AILO_CODEX_EXECUTABLE = $codex.Source
  Write-Host "Codex gateway: enabled ($($codex.Source))"
}

$data = New-Item -ItemType Directory -Path $DataDirectory -Force
$resolvedData = $data.FullName

$env:AILO_DATA_DIRECTORY = $resolvedData
$env:PORT = $Port.ToString()

Write-Host "AILearningOS data: $resolvedData"
Write-Host "AILearningOS port: $Port"

& $serverExecutable
exit $LASTEXITCODE
