# Hesam Void 4SUPER Windows runtime fetcher.
# Downloads signed/runtime dependencies into Flutter assets for a local Windows build.
# Do not commit the generated xray.exe or wintun.dll files.

$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$target = Join-Path $root 'assets\runtime\win32'
New-Item -ItemType Directory -Force -Path $target | Out-Null

$xrayVersion = 'v26.3.27'
$xrayUrl = "https://github.com/XTLS/Xray-core/releases/download/$xrayVersion/Xray-windows-64.zip"
$wintunVersion = '0.14.1'
$wintunUrl = "https://www.wintun.net/builds/wintun-$wintunVersion.zip"
$wintunSha256 = '07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51'

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('hesam-void-runtime-' + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
  $xrayZip = Join-Path $temp 'xray.zip'
  $wintunZip = Join-Path $temp 'wintun.zip'
  Invoke-WebRequest -Uri $xrayUrl -OutFile $xrayZip
  Invoke-WebRequest -Uri $wintunUrl -OutFile $wintunZip

  $actualHash = (Get-FileHash -Algorithm SHA256 -Path $wintunZip).Hash.ToLowerInvariant()
  if ($actualHash -ne $wintunSha256) {
    throw "Wintun SHA-256 mismatch. Expected $wintunSha256, received $actualHash."
  }

  Expand-Archive -Path $xrayZip -DestinationPath (Join-Path $temp 'xray') -Force
  Expand-Archive -Path $wintunZip -DestinationPath (Join-Path $temp 'wintun') -Force

  Copy-Item (Join-Path $temp 'xray\xray.exe') (Join-Path $target 'xray.exe') -Force
  Copy-Item (Join-Path $temp 'wintun\wintun\bin\amd64\wintun.dll') (Join-Path $target 'wintun.dll') -Force
  Write-Host "Windows runtime staged in $target"
} finally {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temp
}
