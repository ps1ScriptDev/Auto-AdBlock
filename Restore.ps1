<#
    Restore-DNS.ps1
    ------------------------------------------------------------
    DNS 설정을 원래대로(자동 할당) 되돌립니다.
    공유기 또는 통신사가 제공하는 DNS를 다시 사용하게 됩니다.

    실행 방법
      파일 우클릭 → "PowerShell에서 실행"

    ※ 저장 시 인코딩은 반드시 "UTF-8 (BOM 포함)"
    ------------------------------------------------------------
#>

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ── 1. 관리자 권한 확인 및 자동 상승 ────────────────────────────
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host "관리자 권한이 필요합니다. 권한 상승을 요청합니다..." -ForegroundColor Yellow

    $self = $PSCommandPath
    if ([string]::IsNullOrEmpty($self)) { $self = $MyInvocation.MyCommand.Definition }

    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', ('"' + $self + '"')
        )
    } catch {
        Write-Host "권한 상승이 거부되었습니다. 종료합니다." -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
    exit
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  DNS 설정 복구 (자동 할당으로 되돌리기)" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# ── 2. 변경 전 상태 기록 ────────────────────────────────────────
Write-Host ""
Write-Host "----- 변경 전 -----" -ForegroundColor DarkGray
Get-DnsClientServerAddress -AddressFamily IPv4 |
    Where-Object { $_.ServerAddresses.Count -gt 0 } |
    Select-Object InterfaceAlias, @{N='DNS'; E={$_.ServerAddresses -join ', '}} |
    Format-Table -AutoSize

# ── 3. 대상 어댑터 선택 ─────────────────────────────────────────
$adapters = Get-NetAdapter | Where-Object {
    $_.Virtual -eq $false -and
    $_.Status -notin @('Disabled', 'Not Present') -and
    $_.InterfaceDescription -notmatch 'Loopback|VirtualBox|VMware|Hyper-V|TAP-|WAN Miniport'
}

if (-not $adapters) {
    Write-Host "대상 네트워크 어댑터를 찾지 못했습니다." -ForegroundColor Red
    Read-Host "엔터를 누르면 종료합니다"
    exit 1
}

# ── 4. 복구 ─────────────────────────────────────────────────────
$okCount   = 0
$failCount = 0

foreach ($adapter in $adapters) {

    $name  = $adapter.Name
    $idx   = $adapter.ifIndex
    $state = if ($adapter.Status -eq 'Up') { '연결됨' } else { '미연결' }

    try {
        # IPv4 / IPv6 모두 자동 할당으로 초기화
        Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop
        Write-Host ("[복구] {0} ({1})" -f $name, $state) -ForegroundColor Green
        $okCount++
    }
    catch {
        Write-Host ("[실패] {0} : {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
        $failCount++
    }
}

# ── 5. 캐시 정리 및 IP 갱신 ─────────────────────────────────────
Write-Host ""
Write-Host "DNS 캐시를 비우고 설정을 갱신하는 중..." -ForegroundColor Yellow
Clear-DnsClientCache
ipconfig /renew | Out-Null

# ── 6. 결과 확인 ────────────────────────────────────────────────
Write-Host ""
Write-Host "----- 변경 후 -----" -ForegroundColor Cyan
Get-DnsClientServerAddress -AddressFamily IPv4 |
    Where-Object { $_.ServerAddresses.Count -gt 0 } |
    Select-Object InterfaceAlias, @{N='DNS'; E={$_.ServerAddresses -join ', '}} |
    Format-Table -AutoSize

Write-Host ("복구 {0}개, 실패 {1}개" -f $okCount, $failCount) -ForegroundColor Cyan
Write-Host ""
Write-Host "위 목록에 94.140.x.x 가 남아있지 않다면 정상입니다." -ForegroundColor DarkGray
Write-Host "목록이 비어 있어도 정상입니다(공유기에서 자동으로 받아옴)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "완료되었습니다." -ForegroundColor Green
Read-Host "엔터를 누르면 창을 닫습니다"
