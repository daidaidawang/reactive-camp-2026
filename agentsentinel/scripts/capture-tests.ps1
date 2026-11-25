$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$Host.UI.RawUI.WindowTitle = 'AgentSentinel - Foundry test evidence'
try {
    $buffer = $Host.UI.RawUI.BufferSize
    $buffer.Width = 145
    $buffer.Height = 3000
    $Host.UI.RawUI.BufferSize = $buffer
    $window = $Host.UI.RawUI.WindowSize
    $window.Width = [Math]::Min(145, $Host.UI.RawUI.MaxPhysicalWindowSize.Width)
    $window.Height = [Math]::Min(48, $Host.UI.RawUI.MaxPhysicalWindowSize.Height)
    $Host.UI.RawUI.WindowSize = $window
} catch { }
Clear-Host
$evidence = Join-Path $projectRoot 'docs/evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
Write-Host ('Workspace: ' + $projectRoot)
Write-Host ('Captured run: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
Write-Host 'PS> forge test -vv'
& forge test -vv 2>&1 | Tee-Object -FilePath (Join-Path $evidence 'forge-test.txt')
$testExit = $LASTEXITCODE
Write-Host ('Exit code: ' + $testExit)
Set-Content -LiteralPath (Join-Path $evidence 'forge-test.exit.txt') -Value $testExit
