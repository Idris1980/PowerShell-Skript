<#
.SYNOPSIS
    Menybaserad installation av Exchange Server 2019 på Windows Server Core.

.DESCRIPTION
    1. Installerar IIS och alla Windows-funktioner som Exchange kräver
       (Core-varianten, utan grafiska managementverktyg).
    2. Installerar Visual C++ 2013 (från C:\Exchange) och startar UCMA-setup
       från Exchange-ISO:ns UCMARedist-mapp.
    3. Förbereder AD (/PrepareSchema, /PrepareAD, /PrepareAllDomains).
    4. Kör den fullständiga Exchange-installationen (Mailbox-roll).
    5. Startar om servern.
    Exchange-ISO:n ska vara monterad som DVD-enhet i VM:en.

.NOTES
    Kör som administratör på den domänanslutna Server Core-maskinen.
    Tips: Hyper-V\Kopiera-FilerTillVM.ps1 kopierar vcredist_x64.exe till C:\Exchange.
#>

function Show-Menu {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "   EXCHANGE 2019 SERVER CORE INSTALLER" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "1. Installera IIS & Windows Features"
    Write-Host "2. Starta UCMA Setup (Grafisk ruta)"
    Write-Host "3. Förbered AD (Schema, AD & Domains)"
    Write-Host "4. Starta Fullständig Exchange Installation"
    Write-Host "5. Starta om servern"
    Write-Host "Q. Avsluta"
    Write-Host "-----------------------------------------------"
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Välj ett alternativ"

    switch ($choice) {
        "1" {
            Write-Host "Installerar Windows Features..." -ForegroundColor Yellow
            $ExchangeRoles = @("Web-Server", "Web-Common-Http", "Web-Default-Doc", "Web-Dir-Browsing", "Web-Http-Errors", "Web-Static-Content", "Web-Http-Redirect", "Web-Http-Logging", "Web-Log-Libraries", "Web-Request-Monitor", "Web-Http-Tracing", "Web-Performance", "Web-Stat-Compression", "Web-Dyn-Compression", "Web-Security", "Web-Filtering", "Web-Basic-Auth", "Web-Client-Auth", "Web-Digest-Auth", "Web-Windows-Auth", "Web-App-Dev", "Web-Net-Ext45", "Web-Asp-Net45", "Web-ISAPI-Ext", "Web-ISAPI-Filter", "Web-Mgmt-Service", "Web-Metabase", "Web-WMI", "Server-Media-Foundation", "NET-Framework-45-Features", "RPC-over-HTTP-proxy", "RSAT-Clustering", "RSAT-Clustering-CmdInterface", "RSAT-Clustering-PowerShell", "WAS-Process-Model", "RSAT-ADDS")
            Install-WindowsFeature $ExchangeRoles -IncludeManagementTools
            Write-Host "KLART! Starta om servern (val 5) innan du kör UCMA." -ForegroundColor Red
            Pause
        }

        "2" {
            Write-Host "Startar Visual C++ 2013..." -ForegroundColor Yellow
            if (Test-Path "C:\Exchange\vcredist_x64.exe") { 
                Start-Process "C:\Exchange\vcredist_x64.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait 
            }

            Write-Host "Letar efter UCMA Setup..." -ForegroundColor Yellow
            $Drive = (Get-Volume | Where-Object { $_.DriveType -eq "CD-ROM" -or $_.FileSystemLabel -like "*Exchange*" }).DriveLetter | Select-Object -First 1
            $UcmaSetup = "$($Drive):\UCMARedist\Setup.exe"

            if (Test-Path $UcmaSetup) {
                Write-Host "Startar UCMA-rutan! Följ stegen i fönstret som dyker upp." -ForegroundColor Green
                # Här startar vi filen DU hittade utan "quiet"-flaggor så fönstret syns
                Start-Process $UcmaSetup -Wait
                Write-Host "UCMA-installationen avslutad." -ForegroundColor Cyan
            } else {
                Write-Host "FEL: Hittade inte $UcmaSetup" -ForegroundColor Red
            }
            Pause
        }

        "3" {
            $orgName = Read-Host "Ange Organisationsnamn"
            $Drive = (Get-Volume | Where-Object { $_.DriveType -eq "CD-ROM" }).DriveLetter | Select-Object -First 1
            if ($Drive) {
                Set-Location "$($Drive):\"
                Write-Host "Förbereder AD..." -ForegroundColor Cyan
                .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareSchema
                .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareAD /OrganizationName:"$orgName"
                .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareAllDomains
                Set-Location C:\
            }
            Pause
        }

        "4" {
            $Drive = (Get-Volume | Where-Object { $_.DriveType -eq "CD-ROM" }).DriveLetter | Select-Object -First 1
            if ($Drive) {
                Set-Location "$($Drive):\"
                Write-Host "Startar Exchange Installation..." -ForegroundColor Magenta
                .\Setup.exe /m:Install /roles:m /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /InstallWindowsComponents
            }
            Pause
        }

        "5" { Restart-Computer -Force }
        "Q" { exit }
    }
}
