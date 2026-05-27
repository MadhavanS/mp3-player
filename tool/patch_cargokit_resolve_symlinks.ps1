# Patches metadata_god / cargokit resolve_symlinks.ps1 for Windows hidden folders
# (e.g. C:\Users\<you>\AppData) where Get-Item fails without -Force.
# Run after `flutter pub get` if Windows builds fail with:
#   Get-Item : Could not find item C:\Users\...\AppData

$ErrorActionPreference = 'Stop'

$needle = '$item = Get-Item $realPath'
$replacement = '$item = Get-Item -LiteralPath $realPath -Force'

$roots = @(
    "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev",
    "$env:LOCALAPPDATA\Pub\Cache\git"
)

$scriptName = 'resolve_symlinks.ps1'
$patched = 0

foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -Filter $scriptName -ErrorAction SilentlyContinue |
        ForEach-Object {
            $content = Get-Content -LiteralPath $_.FullName -Raw
            if ($content -notmatch [regex]::Escape($needle)) {
                if ($content -match 'Get-Item -LiteralPath \$realPath -Force') {
                    Write-Host "Already patched: $($_.FullName)"
                    $patched++
                }
                return
            }
            $content = $content.Replace($needle, $replacement)
            Set-Content -LiteralPath $_.FullName -Value $content -NoNewline
            Write-Host "Patched: $($_.FullName)"
            $patched++
        }
}

$ephemeral = Join-Path $PSScriptRoot '..\windows\flutter\ephemeral\.plugin_symlinks'
$ephemeral = [System.IO.Path]::GetFullPath($ephemeral)
if (Test-Path -LiteralPath $ephemeral) {
    Get-ChildItem -LiteralPath $ephemeral -Recurse -Filter $scriptName -ErrorAction SilentlyContinue |
        ForEach-Object {
            $content = Get-Content -LiteralPath $_.FullName -Raw
            if ($content -notmatch [regex]::Escape($needle)) {
                if ($content -match 'Get-Item -LiteralPath \$realPath -Force') {
                    Write-Host "Already patched: $($_.FullName)"
                    $patched++
                }
                return
            }
            $content = $content.Replace($needle, $replacement)
            Set-Content -LiteralPath $_.FullName -Value $content -NoNewline
            Write-Host "Patched: $($_.FullName)"
            $patched++
        }
}

if ($patched -eq 0) {
    Write-Warning "No $scriptName files found to patch. Run flutter pub get first."
    exit 1
}

Write-Host "Done. Patched $patched file(s)."
