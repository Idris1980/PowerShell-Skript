<#
.SYNOPSIS
    Menybaserad installation av Exchange Server 2019 (Mailbox-roll) med alla förutsättningar.

.DESCRIPTION
    Alternativ 1 – Förberedelser (starta om servern efteråt):
      1. Visual C++ 2013 Redistributable (vcredist_x64.exe)
      2. Unified Communications Managed API 4.0 (UcmaRuntimeSetup.exe)
      3. Alla Windows-funktioner som Exchange 2019 kräver
      4. IIS URL Rewrite Module (rewrite_amd64_en-US.msi)
      5. .NET Framework 4.8 (NDP48-x86-x64-AllOS-ENU.exe)
    Installationsfilerna ska ligga i samma mapp som skriptet.

    Alternativ 2 – Installation:
      Frågar efter enhetsbokstav för monterad Exchange-ISO, installationsenhet och
      organisationsnamn, kör /PrepareSchema, /PrepareAD, /PrepareAllDomains och
      installerar sedan Mailbox-rollen.

.NOTES
    Kör som administratör på den domänanslutna Exchange-servern med ett konto
    som är medlem i Schema Admins och Enterprise Admins.
    Tips: Hyper-V\Kopiera-FilerTillVM.ps1 kopierar installationsfilerna in i VM:en.
#>

# Kontrollera att skriptet körs som administratör
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "FEL: Skriptet måste köras som Administratör!" -ForegroundColor Red; exit
}

# Sätt arbetskatalogen till mappen där skriptet körs ifrån
$toolsPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $toolsPath

# ======================================================================
# FUNKTION: FÖRBEREDELSER (STEG 1-5)
# ======================================================================
function Install-ExchangePrerequisites {
    Write-Host "--- PÅBÖRJAR INSTALLATION AV BEROENDEN ---" -ForegroundColor Yellow

    # 1. Microsoft Visual C++ 2013
    Write-Host "`n1. Installerar Microsoft Visual C++ 2013..." -ForegroundColor Cyan
    if (Test-Path "vcredist_x64.exe") {
        Start-Process -FilePath "vcredist_x64.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait
    } else { Write-Host "FIL SAKNAS: vcredist_x64.exe" -ForegroundColor Red }

    # 2. Microsoft UCMA Runtime
    Write-Host "2. Installerar UCMA Runtime Setup..." -ForegroundColor Cyan
    if (Test-Path "UcmaRuntimeSetup.exe") {
        Start-Process -FilePath "UcmaRuntimeSetup.exe" -ArgumentList "/quiet", "/norestart" -Wait
    } else { Write-Host "FIL SAKNAS: UcmaRuntimeSetup.exe" -ForegroundColor Red }

    # 3. Windows-funktioner
    Write-Host "3. Installerar Windows Moduler..." -ForegroundColor Cyan
    $Features = @(
        "Server-Media-Foundation","NET-Framework-45-Features","RPC-over-HTTP-proxy",
        "RSAT-Clustering","RSAT-Clustering-CmdInterface","RSAT-Clustering-Mgmt",
        "RSAT-Clustering-PowerShell","WAS-Process-Model","Web-Asp-Net45",
        "Web-Basic-Auth","Web-Client-Auth","Web-Digest-Auth","Web-Dir-Browsing",
        "Web-Dyn-Compression","Web-Http-Errors","Web-Http-Logging","Web-Http-Redirect",
        "Web-Http-Tracing","Web-ISAPI-Ext","Web-ISAPI-Filter","Web-Lgcy-Mgmt-Console",
        "Web-Metabase","Web-Mgmt-Console","Web-Mgmt-Service","Web-Net-Ext45",
        "Web-Request-Monitor","Web-Server","Web-Stat-Compression","Web-Static-Content",
        "Web-Windows-Auth","Web-WMI","Windows-Identity-Foundation","RSAT-ADDS"
    )
    Install-WindowsFeature $Features -IncludeManagementTools

    # 4. IIS URL Rewrite
    Write-Host "4. Installerar IIS URL Rewrite Module..." -ForegroundColor Cyan
    if (Test-Path "rewrite_amd64_en-US.msi") {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i rewrite_amd64_en-US.msi", "/qn", "/norestart" -Wait
    } else { Write-Host "FIL SAKNAS: rewrite_amd64_en-US.msi" -ForegroundColor Red }

    # 5. Microsoft .NET Framework 4.8
    Write-Host "5. Installerar Microsoft .NET Framework 4.8..." -ForegroundColor Cyan
    if (Test-Path "NDP48-x86-x64-AllOS-ENU.exe") {
        Start-Process -FilePath "NDP48-x86-x64-AllOS-ENU.exe" -ArgumentList "/q", "/norestart" -Wait
    } else { Write-Host "FIL SAKNAS: NDP48-x86-x64-AllOS-ENU.exe" -ForegroundColor Red }

    Write-Host "`n--- FÖRBEREDELSER KLARA ---" -ForegroundColor Green
    Write-Host "Viktigt: Starta om servern innan du går vidare till steg 6." -ForegroundColor Yellow
}

# ======================================================================
# FUNKTION: EXCHANGE INSTALLATION (STEG 6)
function Run-ExchangeSetup {
    Write-Host "--- STEG 6: INSTALLERA MICROSOFT EXCHANGE 2019 ---" -ForegroundColor Magenta
    
    # 1. Fråga efter var ISO-filen finns
    $isoDrive = Read-Host "Ange enhetsbokstav för Exchange ISO (t.ex. E:)"
    # Säkerställ att det slutar med ett kolon om användaren glömde det
    if ($isoDrive -notlike "*:") { $isoDrive = "${isoDrive}:" }
    
    # 2. Fråga efter var Exchange ska installeras
    $installDrive = Read-Host "Ange enhetsbokstav för INSTALLATION (t.ex. X:)"
    if ($installDrive -notlike "*:") { $installDrive = "${installDrive}:" }
    $installPath = "$($installDrive)\ExchangeServer"

    # Kontrollera att Setup.exe faktiskt finns på angiven ISO-enhet
    if (-not (Test-Path "$($isoDrive)\Setup.exe")) { 
        Write-Host "FEL: Hittade inte Setup.exe på enhet $isoDrive. Kontrollera att ISO:n är monterad." -ForegroundColor Red
        return 
    }

    # Ändra arbetskatalog till ISO-enheten 
    Set-Location "$($isoDrive)\"
    
    $orgName = Read-Host "Ange namnet på din Exchange-organisation (t.ex. Contoso)"

    Write-Host "`nSteg 0: Förbered Active Directory och schema..." -ForegroundColor Cyan

    # Kör AD-förberedelser
    Write-Host "Kör /PrepareSchema..."
    .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareSchema

    Write-Host "Kör /PrepareAD..."
    .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareAD /OrganizationName:"$orgName"

    Write-Host "Kör /PrepareAllDomains..."
    .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareAllDomains

    Write-Host "`nStartar Exchange Setup på $installPath..." -ForegroundColor Cyan

    # Slutlig installation med TargetDir
    .\Setup.exe `
        /Mode:Install `
        /Roles:Mailbox `
        /OrganizationName:"$orgName" `
        /TargetDir:"$installPath" `
        /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF
        
    # Återställ arbetskatalog till skriptmappen efteråt
    Set-Location $toolsPath
}
# ======================================================================
# HUVUDMENY
# ======================================================================
while ($true) {
    Clear-Host
    Write-Host "================================================" -ForegroundColor White
    Write-Host "      EXCHANGE 2019 DEPLOYMENT TOOLKIT" -ForegroundColor Magenta
    Write-Host "================================================" -ForegroundColor White
    Write-Host "1. Kör förberedande installationer (Steg 1-5)"
    Write-Host "2. Installera Exchange Server 2019 (Steg 6 + AD-förberedelser)"
    Write-Host "Q. Avsluta"
    Write-Host "------------------------------------------------"

    $val = Read-Host "Välj ett alternativ"

    switch ($val) {
        "1" { Install-ExchangePrerequisites; Read-Host "`nTryck Enter..." }
        "2" { Run-ExchangeSetup; Read-Host "`nTryck Enter..." }
        "Q" { exit }
        default { Write-Host "Ogiltigt val, försök igen." -ForegroundColor Red; Start-Sleep -s 1 }
    }
}
