<#
.SYNOPSIS
    Steg 2 av 3: Skapar en ny Active Directory-skog (forest) med DNS.

.DESCRIPTION
    Frågar efter domännamn, NetBIOS-namn (förslag tas från domännamnet) och
    DSRM-lösenord och befordrar servern till första domänkontrollant i en ny
    skog. Servern startar om automatiskt när installationen är klar.

    Fortsätt sedan med 3-Konfigurera-DHCP.ps1.

.NOTES
    Kör som administratör efter 1-Konfigurera-NyServer.ps1.
#>

Import-Module ADDSDeployment

Write-Host "=== Steg 2: Skapa ny domän ===" -ForegroundColor Cyan

# ---- Domäninformation ----
$domainName = Read-Host "Ange domännamn (ex: contoso.local)"

$netbiosDefault = ($domainName.Split(".")[0]).ToUpper()
$netbiosName = Read-Host "Ange NetBIOS-namn [$netbiosDefault]"
if ([string]::IsNullOrWhiteSpace($netbiosName)) {
    $netbiosName = $netbiosDefault
}

$dsrmPassword = Read-Host "Ange DSRM-lösenord" -AsSecureString

# ---- Skapa forest & domän ----
Write-Host "Skapar ny AD Forest & Domain..." -ForegroundColor Yellow

Install-ADDSForest `
    -DomainName $domainName `
    -DomainNetbiosName $netbiosName `
    -SafeModeAdministratorPassword $dsrmPassword `
    -InstallDNS `
    -Force
