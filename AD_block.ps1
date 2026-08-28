<#
    Set-AdGuardDNS.ps1
    ------------------------------------------------------------
    AdGuard 광고차단 DNS를 네트워크 어댑터에 적용합니다.
      기본 DNS : 94.140.14.14
      보조 DNS : 94.140.15.15

    실행 방법
      파일 우클릭 → "PowerShell에서 실행"

    옵션
      -Restore      원래대로(DHCP 자동 할당) 복구
      -IncludeIPv6  IPv6 DNS도 함께 적용
      -OnlyActive   지금 연결된 어댑터에만 적용
    ------------------------------------------------------------
#>

param(
    [switch]$Restore,
    [switch]$IncludeIPv6,
    [switch]$OnlyActive
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ── 1. 관리자 권한 확인 및 자동 상승 ────────────────────────────
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host "관리자 권한이 필요합니다. 권한 상승을 요청합니다..." -ForegroundColor Yellow

    # $PSCommandPath 가 비어 있는 경우(붙여넣기 실행 등) 대비
    $self = $PSCommandPath
    if ([string]::IsNullOrEmpty($self)) { $self = $MyInvocation.MyCommand.Definition }

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"' + $self + '"')
    )
    if ($Restore)     { $argList += '-Restore' }
    if ($IncludeIPv6) { $argList += '-IncludeIPv6' }
    if ($OnlyActive)  { $argList += '-OnlyActive' }

    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    } catch {
        Write-Host "관리자 권한이 없어 스크립트를 종료합니다." -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
    exit
}

# ── 2. 적용할 DNS ───────────────────────────────────────────────
$dnsIPv4 = @('94.140.14.14', '94.140.15.15')
$dnsIPv6 = @('2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff')

# ── 3. 대상 어댑터 선택 ─────────────────────────────────────────
$adapters = Get-NetAdapter | Where-Object {
    $_.Virtual -eq $false -and
    $_.Status -notin @('Disabled', 'Not Present') -and
    $_.InterfaceDescription -notmatch 'Loopback|VirtualBox|VMware|Hyper-V|TAP-|WAN Miniport'
}

if ($OnlyActive) {
    $adapters = $adapters | Where-Object { $_.Status -eq 'Up' }
}

if (-not $adapters) {
    Write-Host "대상 네트워크 어댑터를 찾지 못했습니다." -ForegroundColor Red
    Read-Host "엔터를 누르면 종료합니다"
    exit 1
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
if ($Restore) {
    Write-Host "  DNS 복구 (자동 할당으로 되돌리기)" -ForegroundColor Cyan
} else {
    Write-Host "  AdGuard 광고차단 DNS 적용" -ForegroundColor Cyan
}
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# ── 4. 적용 ─────────────────────────────────────────────────────
foreach ($adapter in $adapters) {

    $name  = $adapter.Name
    $idx   = $adapter.ifIndex
    $state = if ($adapter.Status -eq 'Up') { '연결됨' } else { '미연결' }

    try {
        if ($Restore) {
            Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop
            Write-Host ("[복구] {0} ({1})" -f $name, $state) -ForegroundColor Green
        }
        else {
            Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $dnsIPv4 -ErrorAction Stop
            Write-Host ("[IPv4] {0} ({1}) -> {2}" -f $name, $state, ($dnsIPv4 -join ', ')) -ForegroundColor Green

            if ($IncludeIPv6) {
                Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $dnsIPv6 -AddressFamily IPv6 -ErrorAction Stop
                Write-Host ("[IPv6] {0} -> {1}" -f $name, ($dnsIPv6 -join ', ')) -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host ("[실패] {0} : {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
    }
}

# ── 5. DNS 캐시 비우기 ──────────────────────────────────────────
Write-Host ""
Write-Host "DNS 캐시를 비우는 중..." -ForegroundColor Yellow
Clear-DnsClientCache

# ── 6. 결과 확인 ────────────────────────────────────────────────
Write-Host ""
Write-Host "----- 현재 DNS 설정 -----" -ForegroundColor Cyan
Get-DnsClientServerAddress -AddressFamily IPv4 |
    Where-Object { $_.ServerAddresses.Count -gt 0 } |
    Select-Object InterfaceAlias, @{N='DNS'; E={$_.ServerAddresses -join ', '}} |
    Format-Table -AutoSize

Write-Host "완료." -ForegroundColor Green
Read-Host "엔터를 누르면 창을 닫습니다"
