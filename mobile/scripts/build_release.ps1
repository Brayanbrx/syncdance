<#
.SYNOPSIS
  Compila los APK de release que SyncDance reparte sin Google Play.

.DESCRIPTION
  Exige lo que una build de release necesita para funcionar en un teléfono:
  - un servidor HTTPS (Android bloquea http fuera de las builds de depuración)
  - la clave propia en android/key.properties (sin ella, el APK no actualiza
    al instalado y hay que desinstalar)
  - un código de versión mayor que el último publicado (la app avisa de una
    actualización comparando ese número)

  Al terminar imprime el tamaño y el SHA-256 de cada APK. Súbelo en
  <servidor>/panel/app: la versión y el código se leen del propio APK.

.EXAMPLE
  ./scripts/build_release.ps1 -Server https://syncdance.example.com -Version 1.1.0 -Build 2

.EXAMPLE
  # Un APK por arquitectura, más livianos (la mayoría de teléfonos usa arm64-v8a).
  ./scripts/build_release.ps1 -Server https://syncdance.example.com -Version 1.1.0 -Build 2 -SplitPerAbi
#>
param(
  [Parameter(Mandatory)] [string] $Server,
  [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+$')] [string] $Version,
  [Parameter(Mandatory)] [ValidateRange(1, 2100000000)] [int] $Build,
  [switch] $SplitPerAbi
)

$ErrorActionPreference = 'Stop'
$Server = $Server.TrimEnd('/')
if ($Server -notmatch '^https://[^/\s]+$') {
  throw "Server debe ser https://dominio (sin /api): Android bloquea http en release. Recibido: $Server"
}

$mobile = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not (Test-Path (Join-Path $mobile 'android/key.properties'))) {
  throw 'Falta android/key.properties: sin la clave propia el APK no podrá actualizar al instalado. Ver android/README.md.'
}

# The newest published build, to refuse a version code that would not update.
try {
  $latest = Invoke-RestMethod -Uri "$Server/api/app/latest/" -TimeoutSec 15
  if ($Build -le $latest.version_code) {
    throw "El código $Build no es mayor que el publicado ($($latest.version_name), código $($latest.version_code))."
  }
} catch [System.Net.WebException], [System.Net.Http.HttpRequestException], [Microsoft.PowerShell.Commands.HttpResponseException] {
  Write-Host 'No se pudo consultar la última versión publicada (¿primera publicación?). Sigo.'
}

Push-Location $mobile
try {
  $arguments = @(
    'build', 'apk', '--release',
    "--build-name=$Version",
    "--build-number=$Build",
    "--dart-define=API_BASE_URL=$Server/api"
  )
  if ($SplitPerAbi) { $arguments += '--split-per-abi' }
  flutter @arguments
  if ($LASTEXITCODE -ne 0) { throw 'La compilación falló.' }

  Write-Host ''
  Get-ChildItem 'build/app/outputs/flutter-apk/*-release.apk' | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    '{0}  {1:N1} MB  sha256 {2}' -f $_.Name, ($_.Length / 1MB), $hash
  }
  Write-Host ''
  Write-Host "Súbelo en $Server/panel/app (versión $Version, código $Build)."
} finally {
  Pop-Location
}
