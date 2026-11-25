param([ValidateSet('core','callback','reactive','orders1','orders2','crosschain','state','tests','failed','verified')][string]$Mode)

$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..\..'))
mode con: cols=135 lines=46 | Out-Null
Clear-Host
Write-Host "AgentSentinel / $Mode / 2026-11-25" -ForegroundColor Cyan

if ($Mode -eq 'tests') {
    Write-Host '> forge test -vv' -ForegroundColor Yellow
    forge test -vv | Select-Object -Last 22
    Write-Host "exit code: $LASTEXITCODE" -ForegroundColor Green
    return
}
if ($Mode -eq 'verified') {
    $jobs = @(
        @('AgentRegistry','facf704a-2ab1-4386-8dde-d858dab3da6e','11155111'),
        @('CapabilityRegistry','26d67ae3-e7fb-4b57-b346-96f71c6ff030','11155111'),
        @('AccountabilityVault','9fa305f6-cb1d-4d83-982a-b11e8df84982','11155111'),
        @('SentinelExecutor','b85f3999-0d2f-4021-9851-4f56c75e57f0','11155111'),
        @('SentinelCallbackTarget','555316b8-1eed-4688-adbf-ad64c56207f6','11155111'),
        @('AgentSentinel','e12722be-a1be-4f86-97cf-9b5cd9330150','5318007')
    )
    foreach ($j in $jobs) {
        Write-Host "> forge verify-check $($j[1]) --verifier sourcify --chain $($j[2])" -ForegroundColor Yellow
        $raw = forge verify-check $j[1] --verifier sourcify --chain $j[2] 2>&1
        if ($LASTEXITCODE -ne 0 -or ($raw -join ' ') -notmatch 'exact_match') { throw "verification failed: $($j[0])" }
        Write-Host "$($j[0]): exact_match" -ForegroundColor Green
    }
    Write-Host 'All six contracts verified.' -ForegroundColor Cyan
    return
}

$sepolia = 'https://sepolia.gateway.tenderly.co'
$lasna = 'https://lasna-rpc.rnk.dev'
if ($Mode -eq 'state') {
    $account = '0x4b55Cf75A3A18E58ed78c1B7f27Aa4F1be59410d'
    $cap = '0x91e9154c90e0310ca5f426f5b232ab224853a578903ba21ebea54912208a2aba'
    Write-Host '> Sepolia Executor.receipts(2)' -ForegroundColor Yellow
    cast call 0xB6Daf06E3D65008430ac9F2E3ca5F402134844A1 'receipts(uint256)(address,bytes32,uint256,uint256,bool,bool)' 2 --rpc-url $sepolia
    Write-Host '> Sepolia Callback.processed(2)' -ForegroundColor Yellow
    cast call 0x1A4DCB8DFEa162ed09C5a3Be1A6275F404a62384 'processed(uint256)(bool)' 2 --rpc-url $sepolia
    Write-Host '> Sepolia AgentRegistry.isActive(agent)' -ForegroundColor Yellow
    cast call 0xe29aC90eCf7D28D972Face09d77d74EcF351A3e5 'isActive(address)(bool)' $account --rpc-url $sepolia
    Write-Host '> Sepolia CapabilityRegistry.isActive(agent, capId)' -ForegroundColor Yellow
    cast call 0xe2E5738697cB8a17e018868460B8F8A0a3621c17 'isActive(address,bytes32)(bool)' $account $cap --rpc-url $sepolia
    Write-Host '> Sepolia Vault.forfeited()' -ForegroundColor Yellow
    cast call 0x3BdF77755307dE44625A8A0d1bC6b05B6Ee62476 'forfeited()(uint256)' --rpc-url $sepolia
    Write-Host '> Lasna Sentinel.seen(2)' -ForegroundColor Yellow
    cast call 0xAA9e4ad766f9370B693c3F0f4245FaFaE86434dB 'seen(uint256)(bool)' 2 --rpc-url $lasna
    Write-Host 'State readback complete.' -ForegroundColor Cyan
    return
}
$sets = @{
    core = @{ rpc=$sepolia; file='broadcast\Deploy.s.sol\11155111\run-1795591708226.json'; names=@('AgentRegistry','CapabilityRegistry','AccountabilityVault','SentinelExecutor','Vault.setExecutor') }
    callback = @{ rpc=$sepolia; file='broadcast\Deploy.s.sol\11155111\run-1795592089852.json'; names=@('SentinelCallbackTarget','Registry.setOperator','Capability.setRevoker','Vault.setSlasher','Executor.setResolver') }
    reactive = @{ rpc=$lasna; files=@('broadcast\Deploy.s.sol\5318007\run-1795591851582.json','broadcast\Deploy.s.sol\5318007\run-1795592154437.json'); names=@('AgentSentinel deploy','Sentinel.setRecipient') }
    orders1 = @{ rpc=$sepolia; file='broadcast\Demo.s.sol\11155111\run-latest.json'; names=@('registerAgent','grantCapability','fund 0.01 ETH','stake 0.005 ETH') }
    orders2 = @{ rpc=$sepolia; file='broadcast\Demo.s.sol\11155111\run-latest.json'; names=@('normal order 0.002 ETH','claimPayment','blocked order 0.004 ETH') }
}

if ($Mode -eq 'failed') {
    $items = @(
        @{ chain='Initial core deployment: insufficient gas limit'; rpc=$sepolia; hash='0x845ca572933b407172678f96803207b79865da45655d6dc4bdc215f6fb8a9059' },
        @{ chain='First retry: gas limit still insufficient'; rpc=$sepolia; hash='0xd525822279cc4dbbd4aff9df25a4cb109461bddc3848e646f955ffd8fb5a4a3d' }
    )
} elseif ($Mode -eq 'crosschain') {
    $items = @(
        @{ chain='Sepolia source / RiskAlert receipt 2'; rpc=$sepolia; hash='0xed54f19864303d97f5d4693f1896e9728e292530708591af35904c9f40e1acdf' },
        @{ chain='Lasna reaction / AlertObserved receipt 2'; rpc=$lasna; hash='0x84a8845d27e84d4c81c522e779090f496b729d94350732c1dcaea75bfe7fcab7' },
        @{ chain='Sepolia callback / DispositionExecuted receipt 2'; rpc=$sepolia; hash='0x2b06737bdbc1fe40a1c00a295afee165b2c76510964819b9e1474d28a218db12' }
    )
} elseif ($Mode -eq 'reactive') {
    $items = @()
    for ($i=0; $i -lt 2; $i++) {
        $j = Get-Content $sets.reactive.files[$i] -Raw | ConvertFrom-Json
        $items += @{chain=$sets.reactive.names[$i];rpc=$lasna;hash=$j.transactions[0].hash}
    }
} else {
    $s = $sets[$Mode]
    $j = Get-Content $s.file -Raw | ConvertFrom-Json
    $items = @()
    $start = if ($Mode -eq 'orders2') { 4 } else { 0 }
    $end = if ($Mode -eq 'orders1') { 4 } else { $j.transactions.Count }
    for ($i=$start; $i -lt $end; $i++) {
        $nameIndex = if ($Mode -eq 'orders2') { $i - 4 } else { $i }
        $items += @{chain=$s.names[$nameIndex];rpc=$s.rpc;hash=$j.transactions[$i].hash}
    }
}

foreach ($item in $items) {
    Write-Host "`n$($item.chain)" -ForegroundColor Yellow
    Write-Host "> cast receipt $($item.hash) --json --rpc-url [chain RPC]"
    $raw = cast receipt $item.hash --json --rpc-url $item.rpc
    if ($LASTEXITCODE -ne 0) { throw "cast receipt failed: $($item.hash)" }
    $receipt = $raw | ConvertFrom-Json
    $block = [Convert]::ToInt64($receipt.blockNumber,16)
    $status = if ($receipt.status -eq '0x1') { 'SUCCESS' } else { 'FAILED' }
    Write-Host "status=$status  block=$block  gasUsed=$([Convert]::ToInt64($receipt.gasUsed,16))" -ForegroundColor $(if($status -eq 'SUCCESS'){'Green'}else{'Red'})
    if ($receipt.contractAddress) { Write-Host "contract=$($receipt.contractAddress)" }
}
Write-Host "`nAll $($items.Count) receipts checked." -ForegroundColor Cyan
