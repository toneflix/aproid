# Publishes the app and builds its installer: windows\publish\Aproid and windows\publish\Aproid-Setup-<version>.exe.
# Run from the windows folder: .\scripts\package.ps1 -Version 1.2.3
param(
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"

dotnet publish src/Aproid -c Release -r win-x64 -p:Platform=x64 --self-contained true -p:Version=$Version -o publish/Aproid
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$iscc = Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
    choco install innosetup --no-progress -y
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& $iscc /Qp "/DAppVersion=$Version" installer\Aproid.iss
exit $LASTEXITCODE
