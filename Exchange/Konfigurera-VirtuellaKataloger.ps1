<#
.SYNOPSIS
    Sätter interna/externa URL:er för alla Exchange-tjänster så att Outlook och OWA fungerar, samt valfritt ett SAN-certifikat.

.DESCRIPTION
    Konfigurerar ett gemensamt namespace (t.ex. mail.contoso.com) för:
      OWA, ECP, Outlook Anywhere, ActiveSync, EWS, OAB, MAPI och Autodiscover.
    Med -CreateCertificate skapas dessutom ett självsignerat SAN-certifikat
    för namespace + autodiscover + servernamnet, det aktiveras för IIS och
    SMTP och exporteras som .cer så att klienterna kan importera det som
    betrott rotcertifikat (t.ex. via GPO). Avslutas med iisreset.

    Använd -ShowOnly för att bara visa nuvarande konfiguration.

.PARAMETER Namespace
    Externt/internt värdnamn, t.ex. mail.contoso.com

.PARAMETER AutodiscoverHost
    Värdnamn för Autodiscover. Standard: autodiscover.<domänen i Namespace>

.PARAMETER CreateCertificate
    Skapa och aktivera ett självsignerat SAN-certifikat.

.PARAMETER CertExportPath
    Var .cer-filen sparas. Standard: C:\Temp\ExchangeSAN.cer

.PARAMETER ShowOnly
    Visa bara nuvarande URL:er, ändra ingenting.

.EXAMPLE
    .\Konfigurera-VirtuellaKataloger.ps1 -ShowOnly

.EXAMPLE
    .\Konfigurera-VirtuellaKataloger.ps1 -Namespace mail.contoso.com -CreateCertificate

.NOTES
    Kör i Exchange Management Shell på Exchange-servern.
    Skapa även DNS-poster (A/CNAME) för namespace och autodiscover som pekar på servern.
#>

param(
    [string]$Namespace,

    [string]$AutodiscoverHost,

    [switch]$CreateCertificate,

    [string]$CertExportPath = "C:\Temp\ExchangeSAN.cer",

    [switch]$ShowOnly
)

$TargetServer = $env:COMPUTERNAME

function Show-ExchangeUrls {
    Write-Host "`n--- OWA ---" -ForegroundColor Cyan
    Get-OwaVirtualDirectory -Server $TargetServer | Format-List Server, InternalUrl, ExternalUrl
    Write-Host "--- ECP ---" -ForegroundColor Cyan
    Get-EcpVirtualDirectory -Server $TargetServer | Format-List Server, InternalUrl, ExternalUrl
    Write-Host "--- Outlook Anywhere ---" -ForegroundColor Cyan
    Get-OutlookAnywhere -Server $TargetServer | Format-List Server, InternalHostname, ExternalHostname
    Write-Host "--- ActiveSync ---" -ForegroundColor Cyan
    Get-ActiveSyncVirtualDirectory -Server $TargetServer | Format-List Server, InternalUrl, ExternalUrl
    Write-Host "--- EWS ---" -ForegroundColor Cyan
    Get-WebServicesVirtualDirectory -Server $TargetServer | Format-List Server, InternalUrl, ExternalUrl
    Write-Host "--- OAB ---" -ForegroundColor Cyan
    Get-OabVirtualDirectory -Server $TargetServer | Format-List Server, InternalUrl, ExternalUrl
    Write-Host "--- MAPI ---" -ForegroundColor Cyan
    Get-MapiVirtualDirectory -Server $TargetServer | Format-List Server, InternalUrl, ExternalUrl
    Write-Host "--- Autodiscover ---" -ForegroundColor Cyan
    Get-ClientAccessService -Identity $TargetServer | Format-List Identity, AutoDiscoverServiceInternalUri
}

if ($ShowOnly) {
    Show-ExchangeUrls
    return
}

if (-not $Namespace) { throw "Ange -Namespace (t.ex. mail.contoso.com) eller använd -ShowOnly." }
if (-not $AutodiscoverHost) {
    $AutodiscoverHost = "autodiscover." + ($Namespace -replace '^[^.]+\.', '')
}

Write-Host "Namespace:    $Namespace"
Write-Host "Autodiscover: $AutodiscoverHost"

# Konfigurera OWA
Get-OwaVirtualDirectory -Server $TargetServer | Set-OwaVirtualDirectory `
    -ExternalUrl "https://$Namespace/owa" `
    -InternalUrl "https://$Namespace/owa"

# Konfigurera ECP
Get-EcpVirtualDirectory -Server $TargetServer | Set-EcpVirtualDirectory `
    -ExternalUrl "https://$Namespace/ecp" `
    -InternalUrl "https://$Namespace/ecp"

# Konfigurera Outlook Anywhere
Get-OutlookAnywhere -Server $TargetServer | Set-OutlookAnywhere `
    -ExternalHostname $Namespace `
    -InternalHostname $Namespace `
    -ExternalClientsRequireSsl $true `
    -InternalClientsRequireSsl $true `
    -DefaultAuthenticationMethod NTLM `
    -SSLOffloading $false

# Konfigurera ActiveSync
Get-ActiveSyncVirtualDirectory -Server $TargetServer | Set-ActiveSyncVirtualDirectory `
    -ExternalUrl "https://$Namespace/Microsoft-Server-ActiveSync" `
    -InternalUrl "https://$Namespace/Microsoft-Server-ActiveSync"

# Konfigurera EWS
Get-WebServicesVirtualDirectory -Server $TargetServer | Set-WebServicesVirtualDirectory `
    -ExternalUrl "https://$Namespace/EWS/Exchange.asmx" `
    -InternalUrl "https://$Namespace/EWS/Exchange.asmx"

# Konfigurera OAB
Get-OabVirtualDirectory -Server $TargetServer | Set-OabVirtualDirectory `
    -ExternalUrl "https://$Namespace/OAB" `
    -InternalUrl "https://$Namespace/OAB"

# Konfigurera MAPI
Get-MapiVirtualDirectory -Server $TargetServer | Set-MapiVirtualDirectory `
    -ExternalUrl "https://$Namespace/mapi" `
    -InternalUrl "https://$Namespace/mapi"

# Konfigurera Autodiscover
Set-ClientAccessService -Identity $TargetServer `
    -AutoDiscoverServiceInternalUri "https://$AutodiscoverHost/Autodiscover/Autodiscover.xml"

# ---------------------------------------------------------------
# Valfritt: självsignerat SAN-certifikat
# ---------------------------------------------------------------
if ($CreateCertificate) {
    Write-Host "`nSkapar självsignerat SAN-certifikat..." -ForegroundColor Yellow

    $fqdn = ([System.Net.Dns]::GetHostEntry($TargetServer)).HostName
    $cert = New-ExchangeCertificate -SubjectName "CN=$Namespace" `
        -FriendlyName "Exchange SAN $Namespace" `
        -DomainName $Namespace, $AutodiscoverHost, $TargetServer, $fqdn `
        -PrivateKeyExportable $true

    Enable-ExchangeCertificate -Thumbprint $cert.Thumbprint -Services IIS, SMTP -Force

    # Exportera publika delen så att klienterna kan lita på certifikatet
    $exportDir = Split-Path $CertExportPath -Parent
    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }
    $exported = Get-ExchangeCertificate -Thumbprint $cert.Thumbprint
    [System.IO.File]::WriteAllBytes($CertExportPath, $exported.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

    Write-Host "Certifikat $($cert.Thumbprint) aktiverat för IIS och SMTP." -ForegroundColor Green
    Write-Host "Publikt certifikat exporterat till $CertExportPath – distribuera till klienterna som betrott rotcertifikat." -ForegroundColor Green
}

# Starta om IIS för att tillämpa ändringar
Write-Host "`nStartar om IIS..." -ForegroundColor Yellow
iisreset

Show-ExchangeUrls
