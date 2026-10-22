<#
.SYNOPSIS
    Menybaserat verktyg för vanlig administration av Active Directory.

.DESCRIPTION
    Interaktiv meny som samlar de vanligaste AD-uppgifterna:
      1. Skapa OU i domänens rot
      2. Skapa under-OU (valfri nivå)
      3. Importera användare från CSV till en vald OU
      4. Skapa säkerhetsgrupp
      5. Lägga alla användare i en OU i en grupp
      6. Importera användare med en OU + GG_/LG_-grupper per avdelning (AGDLP)
      7. Bygga en standardstruktur (Computers/Groups) och importera användare

    Vid CSV-import får du själv välja vilka kolumner som motsvarar
    SamAccountName, förnamn, efternamn och avdelning, och en förhandsgranskning
    visas innan något skapas. CSV-filen ska vara semikolonseparerad.

.NOTES
    Kräver: ActiveDirectory-modulen (RSAT) och rättigheter att skapa objekt i AD.
    Out-GridView används för att välja OU/grupp, så skriptet behöver köras i
    ett fönster med grafiskt gränssnitt (inte Server Core).
#>

Import-Module ActiveDirectory

# ==============================================================================
# HJÄLPFUNKTIONER
# ==============================================================================

function Get-SelectedOU ($Title) {
    Get-ADOrganizationalUnit -Filter * |
        Select-Object Name, DistinguishedName |
        Out-GridView -Title $Title -PassThru
}

function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       AD ADMINISTRATION SYSTEM" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "1: Skapa OU i domänens rot"
    Write-Host "2: Skapa under-OU (valfri nivå)"
    Write-Host "3: Importera användare från CSV (manuell OU)"
    Write-Host "4: Skapa säkerhetsgrupp"
    Write-Host "5: Lägg användare i grupp"
    Write-Host "6: Importera användare (OU + GG/LG per Dept)"
    Write-Host "7: Skapa OU + bygg AD-struktur + importera användare"
    Write-Host "Q: Avsluta"
    Write-Host "========================================" -ForegroundColor Cyan
    Read-Host "Ange ditt val"
}

function Create-OU ($Path, $Name) {
    $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue
    if ($existing) {
        return $existing.DistinguishedName
    }
    try {
        $newOU = New-ADOrganizationalUnit -Name $Name -Path $Path -PassThru -ErrorAction Stop
        Write-Host "OU '$Name' skapad." -ForegroundColor Gray
        return $newOU.DistinguishedName
    } catch {
        Write-Host "Kunde inte skapa OU '$Name': $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Create-ADGroup ($Name, $Scope, $Path) {
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        try {
            New-ADGroup -Name $Name -GroupScope $Scope -GroupCategory Security -Path $Path -ErrorAction Stop
            Write-Host "Grupp '$Name' skapad." -ForegroundColor Green
        } catch {
            Write-Host "Kunde inte skapa grupp '$Name': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ==============================================================================
# IMPORTFUNKTION
# ==============================================================================

function Import-Users {
    param(
        [ValidateSet("Manual","Dept")]
        [string]$Mode = "Manual"
    )

    # 1. Läs in CSV
    $csvPath = Read-Host "Ange sökväg till CSV-fil"
    if (-not (Test-Path $csvPath)) {
        Write-Host "Filen hittades inte!" -ForegroundColor Red
        return
    }

    $users = @(Import-Csv $csvPath -Delimiter ";" -Encoding UTF8)

    if ($users.Count -eq 0) {
        Write-Host "CSV-filen är tom!" -ForegroundColor Yellow
        return
    }

    # 2. Visa kolumner och låt användaren mappa dem
    Write-Host "`nKolumner som hittades i CSV:" -ForegroundColor Cyan
    $users[0].PSObject.Properties.Name | ForEach-Object { Write-Host " - $_" }

    $colSam   = Read-Host "Vilken kolumn ska användas för SamAccountName"
    $colFirst = Read-Host "Vilken kolumn ska användas för Förnamn"
    $colLast  = Read-Host "Vilken kolumn ska användas för Efternamn"
    $colDept  = if ($Mode -eq "Dept") { Read-Host "Vilken kolumn ska användas för Avdelning" } else { "" }

    # 3. Välj bas-OU
    $selOU = Get-SelectedOU "Välj bas-OU för importen"
    if (-not $selOU) { return }
    $baseOUPath = $selOU.DistinguishedName

    # 4. Visa en snabb förhandsgranskning
    Write-Host "`nFörhandsgranskning av användare som ska importeras:" -ForegroundColor Cyan
    $users | Select-Object @{n='SamAccountName';e={$_.PSObject.Properties[$colSam].Value}},
                            @{n='Förnamn';e={$_.PSObject.Properties[$colFirst].Value}},
                            @{n='Efternamn';e={$_.PSObject.Properties[$colLast].Value}},
                            @{n='Avdelning';e={if ($colDept) {$_.PSObject.Properties[$colDept].Value} else {""}}} |
            Format-Table -AutoSize

    $confirm = Read-Host "`nVill du fortsätta importen? (Ja/Nej)"
    if ($confirm -notin @("Ja","ja","J","j")) {
        Write-Host "Import avbruten." -ForegroundColor Yellow
        return
    }

    # Startlösenordet anges vid körning - användarna måste byta vid första inloggning
    $password = Read-Host "Ange startlösenord för de nya användarna" -AsSecureString

    # 5. Importera användare
    foreach ($u in $users) {
        $sam   = $u.$colSam
        $fName = $u.$colFirst
        $lName = $u.$colLast
        $dept  = if ($colDept) { $u.$colDept } else { "" }

        if ([string]::IsNullOrWhiteSpace($sam)) { continue }

        $displayName = if ($fName -and $lName) { "$fName $lName" } else { $sam }

        $currentPath = $baseOUPath

        if ($Mode -eq "Dept" -and $dept) {
            $deptClean = $dept -replace '[^\w\s]', ''
            $currentPath = Create-OU $baseOUPath $deptClean
            if (-not $currentPath) { continue }

            Create-ADGroup "GG_$deptClean" "Global" $currentPath
            Create-ADGroup "LG_$deptClean" "DomainLocal" $currentPath
            Add-ADGroupMember -Identity "LG_$deptClean" -Members "GG_$deptClean" -ErrorAction SilentlyContinue
        }

        # Kontrollera om användare redan finns
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
            Write-Host "Skippar $sam – finns redan." -ForegroundColor Yellow
            continue
        }

        # Skapa användare
        try {
            New-ADUser `
                -SamAccountName $sam `
                -Name $displayName `
                -GivenName $fName `
                -Surname $lName `
                -Path $currentPath `
                -Enabled $true `
                -AccountPassword $password `
                -ChangePasswordAtLogon $true

            Write-Host "Användare '$sam' skapad." -ForegroundColor Green

            if ($Mode -eq "Dept" -and $dept) {
                Add-ADGroupMember -Identity "GG_$deptClean" -Members $sam -ErrorAction SilentlyContinue
            }

        } catch {
            Write-Host "Fel vid skapande av $sam : $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`nImporten klar!" -ForegroundColor Cyan
}


# ==============================================================================
# ALTERNATIV 7: SKAPA OU + STANDARDSTRUKTUR + IMPORT
# ==============================================================================

function Create-FullADStructure {

    $ouName = Read-Host "Ange namn på ny OU (bas för hela strukturen)"
    if ([string]::IsNullOrWhiteSpace($ouName)) { return }

    $rootDN = (Get-ADDomain).DistinguishedName
    $baseOUPath = Create-OU $rootDN $ouName
    if (-not $baseOUPath) { return }

    Write-Host "`nBygger standardstruktur..." -ForegroundColor Cyan

    $computersOU = Create-OU $baseOUPath "Computers"
    if ($computersOU) {
        Create-OU $computersOU "Servers"      | Out-Null
        Create-OU $computersOU "Workstations" | Out-Null
    }

    $groupsOU = Create-OU $baseOUPath "Groups"
    if ($groupsOU) {
        Create-OU $groupsOU "Global" | Out-Null
        Create-OU $groupsOU "Local"  | Out-Null
    }

    Write-Host "`nStruktur klar – startar användarimport..." -ForegroundColor Green
    Import-Users "Dept"
}

# ==============================================================================
# HUVUDLOOP
# ==============================================================================

while ($true) {

    $choice = Show-Menu

    switch ($choice.ToUpper()) {

        "1" {
            $name = Read-Host "Ange namn på ny OU i roten"
            Create-OU (Get-ADDomain).DistinguishedName $name | Out-Null
        }

        "2" {
            $parent = Get-SelectedOU "Välj förälder-OU"
            if ($parent) {
                $name = Read-Host "Ange namn på under-OU"
                Create-OU $parent.DistinguishedName $name | Out-Null
            }
        }

        "3" { Import-Users "Manual" }

        "4" {
            $p = Get-SelectedOU "Välj mål-OU för gruppen"
            if ($p) {
                $n = Read-Host "Ange gruppnamn"
                $s = Read-Host "Ange scope (Global/DomainLocal/Universal)"
                Create-ADGroup $n $s $p.DistinguishedName
            }
        }

        "5" {
            $grp = Get-ADGroup -Filter * | Out-GridView -Title "Välj målgrupp" -PassThru
            if ($grp) {
                $src = Get-SelectedOU "Välj OU att hämta användare från"
                if ($src) {
                    Get-ADUser -Filter * -SearchBase $src.DistinguishedName |
                        ForEach-Object {
                            try {
                                Add-ADGroupMember -Identity $grp -Members $_ -ErrorAction Stop
                                Write-Host "La till $($_.Name)"
                            } catch {
                                Write-Host "Kunde inte lägga till $($_.Name)" -ForegroundColor Yellow
                            }
                        }
                }
            }
        }

        "6" { Import-Users "Dept" }
        "7" { Create-FullADStructure }
        "Q" { return }
        default { Write-Host "Ogiltigt val!" -ForegroundColor Red }
    }

    Write-Host "`nKlar. Tryck ENTER för att återgå till menyn..."
    Read-Host
}
