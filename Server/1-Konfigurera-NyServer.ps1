<#
.SYNOPSIS
    Steg 1 av 3: Grundinstallation av en ny server som ska bli domänkontrollant.

.DESCRIPTION
    - Väljer första aktiva nätverkskortet.
    - Sätter statisk IPv4-adress, prefix och gateway (gamla adresser rensas).
    - Pekar DNS mot serverns egen IP (krävs för AD).
    - Behåller IPv6 men stänger av router discovery och tar bort IPv6-default
      route, och prioriterar IPv4 framför IPv6.
    - Byter datornamn och installerar rollerna AD DS, DNS och DHCP.
    - Startar om om datornamnet har ändrats.

    Fortsätt sedan med 2-Installera-ADForest.ps1.

.NOTES
    Kör som administratör direkt på servern.
#>

Write-Host "=== Steg 1: Grundinstallation av server ===" -ForegroundColor Cyan

# ------------------------------------------------------
# Hämta aktivt nätverkskort
# ------------------------------------------------------
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

if (-not $adapter) {
    Write-Error "Inget aktivt nätverkskort hittades."
    exit 1
}

$iface = $adapter.InterfaceAlias
Write-Host "Använder nätverkskort: $iface"

# ------------------------------------------------------
# Fråga efter IPv4-inställningar
# ------------------------------------------------------
$ipAddress  = Read-Host "Ange IPv4-adress (ex 192.168.1.10)"
$prefix     = Read-Host "Ange prefix (CIDR, ex 24 för 255.255.255.0)"
$gateway    = Read-Host "Ange IPv4 default gateway (ex 192.168.1.1)"

Write-Host "DNS kommer sättas till serverns egen IP ($ipAddress)"

# ------------------------------------------------------
# Rensa gamla IPv4-adresser och default route
# ------------------------------------------------------
Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

Get-NetRoute -InterfaceAlias $iface -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# ------------------------------------------------------
# Sätt statisk IPv4
# ------------------------------------------------------
New-NetIPAddress `
 -InterfaceAlias $iface `
 -IPAddress $ipAddress `
 -PrefixLength $prefix `
 -DefaultGateway $gateway

# DNS -> sig själv (VIKTIGT för AD)
Set-DnsClientServerAddress `
 -InterfaceAlias $iface `
 -ServerAddresses $ipAddress

Write-Host "IPv4-nätverk konfigurerat." -ForegroundColor Green

# ------------------------------------------------------
# IPv6 – behåll stacken men INGEN gateway
# ------------------------------------------------------
Write-Host "Konfigurerar IPv6-policy (AD-säker)..." -ForegroundColor Yellow

# Stäng av Router Discovery (hindrar IPv6 default gateway)
Set-NetIPInterface `
 -InterfaceAlias $iface `
 -AddressFamily IPv6 `
 -RouterDiscovery Disabled

# Ta bort ev. IPv6 default route direkt
Get-NetRoute -InterfaceAlias $iface -AddressFamily IPv6 -ErrorAction SilentlyContinue |
Where-Object { $_.DestinationPrefix -eq "::/0" } |
Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# Prioritera IPv4 framför IPv6
Set-NetIPInterface `
 -InterfaceAlias $iface `
 -AddressFamily IPv4 `
 -InterfaceMetric 10

Set-NetIPInterface `
 -InterfaceAlias $iface `
 -AddressFamily IPv6 `
 -InterfaceMetric 50

Write-Host "IPv6 korrekt begränsat (ingen IPv6 gateway)." -ForegroundColor Green

# ------------------------------------------------------
# Byt datornamn
# ------------------------------------------------------
$newName = Read-Host "Ange nytt datornamn"

$renameRequired = $false
if ($newName -and $env:COMPUTERNAME -ne $newName) {
    Rename-Computer -NewName $newName -Force
    $renameRequired = $true
    Write-Host "Datornamn ändrat till $newName" -ForegroundColor Yellow
}

# ------------------------------------------------------
# Installera roller
# ------------------------------------------------------
Write-Host "Installerar AD DS, DNS och DHCP..." -ForegroundColor Yellow

Install-WindowsFeature `
 AD-Domain-Services, `
 DNS, `
 DHCP `
 -IncludeManagementTools

Write-Host "Roller installerade." -ForegroundColor Green

# ------------------------------------------------------
# Sammanfattning
# ------------------------------------------------------
Write-Host ""
Write-Host "=== Steg 1 klart ===" -ForegroundColor Cyan
Write-Host "IP-adress : $ipAddress"
Write-Host "Gateway   : $gateway"
Write-Host "DNS       : $ipAddress (sig själv)"
Write-Host "IPv6      : Aktiv (ingen default gateway)"
Write-Host "Roller    : AD DS, DNS, DHCP"

# ------------------------------------------------------
# Omstart
# ------------------------------------------------------
if ($renameRequired) {
    Write-Host "Omstart krävs p.g.a. datornamnsbyte. Startar om..." -ForegroundColor Cyan
    Restart-Computer
} else {
    Write-Host "Ingen omstart krävs just nu." -ForegroundColor Green
    Write-Host "Redo för steg 2 (2-Installera-ADForest.ps1)." -ForegroundColor Cyan
}
