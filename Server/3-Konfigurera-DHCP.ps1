<#
.SYNOPSIS
    Steg 3 av 3: Auktoriserar DHCP i AD och skapar ett IPv4-scope.

.DESCRIPTION
    - Kör DHCP:s post-deployment (skapar DHCP-säkerhetsgrupperna).
    - Auktoriserar DHCP-servern i Active Directory.
    - Skapar ett scope med start/slut-IP och nätmask (inaktivt till att börja med).
    - Sätter options 003 (router), 006 (DNS) och 015 (DNS-domän).
    - Frågar om scopet ska aktiveras direkt.

.NOTES
    Kör som administratör på domänkontrollanten efter 2-Installera-ADForest.ps1.
#>

Import-Module DHCPServer

Write-Host "=== DHCP-konfiguration ===" -ForegroundColor Cyan

# ---- Post-deployment: skapa DHCP-säkerhetsgrupper ----
netsh dhcp add securitygroups | Out-Null
Restart-Service DHCPServer

# ---- Auktorisera DHCP ----
$serverName = $env:COMPUTERNAME
$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

Write-Host "Auktoriserar DHCP-server..." -ForegroundColor Yellow
Add-DhcpServerInDC -DnsName "$serverName.$((Get-ADDomain).DNSRoot)" -IPAddress $ipAddress

# ---- DHCP-scope ----
$scopeName   = Read-Host "Ange namn på DHCP-scope"
$scopeStart  = Read-Host "Start-IP"
$scopeEnd    = Read-Host "Slut-IP"
$scopeMask   = Read-Host "Subnätmask (ex: 255.255.255.0)"
$scopeGW     = Read-Host "Gateway (option 003)"
$scopeDNS    = Read-Host "DNS-server (option 006)"
$scopeDomain = (Get-ADDomain).DNSRoot

Write-Host "Skapar DHCP-scope..." -ForegroundColor Yellow

$scope = Add-DhcpServerv4Scope `
    -Name $scopeName `
    -StartRange $scopeStart `
    -EndRange $scopeEnd `
    -SubnetMask $scopeMask `
    -State Inactive `
    -PassThru

# ---- DHCP-options (ScopeId = nätverksadressen, t.ex. 192.168.1.0) ----
Set-DhcpServerv4OptionValue `
    -ScopeId $scope.ScopeId `
    -Router $scopeGW `
    -DnsServer $scopeDNS `
    -DnsDomain $scopeDomain

# ---- Aktivera scope? ----
$activate = Read-Host "Vill du aktivera scopet nu? (ja/nej)"

if ($activate -in @("ja","j","Ja","J")) {
    Set-DhcpServerv4Scope -ScopeId $scope.ScopeId -State Active
    Write-Host "DHCP-scope aktiverat." -ForegroundColor Green
} else {
    Write-Host "DHCP-scope skapades men är inaktivt." -ForegroundColor Yellow
}

Write-Host "DHCP-konfiguration klar!" -ForegroundColor Cyan
