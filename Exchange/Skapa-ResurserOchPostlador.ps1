<#
.SYNOPSIS
    Skapar delade postlådor, mötesrum och utrustningsresurser i Exchange utifrån listor.

.DESCRIPTION
    1. Delade postlådor – skapas och en grupp (t.ex. DL_Sales) får Full Access.
    2. Mötesrum – skapas med kapacitet och ort, och accepterar bokningar automatiskt.
    3. Utrustning – skapas med en beskrivning i CustomAttribute1 och
       accepterar bokningar automatiskt.

    Redigera listorna nedan efter din miljö. Grupperna i $shared måste finnas
    (t.ex. skapade med ActiveDirectory\Importera-AnvandareMedAvdelningar.ps1).

.NOTES
    Kör i Exchange Management Shell (Exchange 2016/2019 on-prem).
#>

Write-Host "=== Startar Exchange-konfiguration ===" -ForegroundColor Cyan

# 1. DELADE POSTLÅDOR (grupper från AD-importen får Full Access)
$shared = @(
    @{Name="Sales";   Alias="sales";   Group="DL_Sales"}
    @{Name="IT";      Alias="it";      Group="DL_IT"}
    @{Name="Finance"; Alias="finance"; Group="DL_Finance"}
    @{Name="Marknad"; Alias="marknad"; Group="DL_Marketing"}
    @{Name="Lager";   Alias="lager";   Group="DL_Warehouse"}
)

foreach ($mb in $shared) {
    if (-not (Get-Mailbox -Identity $mb.Alias -ErrorAction SilentlyContinue)) {
        New-Mailbox -Name $mb.Name -Alias $mb.Alias -Shared | Out-Null
    }
    Add-MailboxPermission -Identity $mb.Alias -User $mb.Group -AccessRights FullAccess -InheritanceType All -ErrorAction SilentlyContinue | Out-Null
    Write-Host "✔ Delad postlåda: $($mb.Name)" -ForegroundColor Green
}

# 2. MÖTESRUM (med kapacitet och ort)
$rooms = @(
    @{Name="Konferensrum A"; Cap=6;  Loc="Göteborg"}
    @{Name="Konferensrum B"; Cap=18; Loc="Stockholm"}
    @{Name="Grupprum 1";     Cap=4;  Loc="Stockholm"}
    @{Name="Hörsalen";       Cap=40; Loc="Göteborg"}
)

foreach ($r in $rooms) {
    if (-not (Get-Mailbox -Identity $r.Name -ErrorAction SilentlyContinue)) {
        New-Mailbox -Name $r.Name -Room | Out-Null
    }
    Set-Mailbox -Identity $r.Name -ResourceCapacity $r.Cap -Office $r.Loc
    Set-CalendarProcessing -Identity $r.Name -AutomateProcessing AutoAccept
    Write-Host "✔ Mötesrum: $($r.Name) ($($r.Loc), $($r.Cap) pers)" -ForegroundColor Green
}

# 3. UTRUSTNING (beskrivning i CustomAttribute1)
$equipment = @(
    @{Name="Projektor 1";   Note="Göteborg"}
    @{Name="Projektor 2";   Note="Stockholm"}
    @{Name="Firmabil 1";    Note="Göteborg - poolbil"}
    @{Name="Videokamera";   Note="Stockholm"}
)

foreach ($e in $equipment) {
    if (-not (Get-Mailbox -Identity $e.Name -ErrorAction SilentlyContinue)) {
        New-Mailbox -Name $e.Name -Equipment | Out-Null
    }
    Set-Mailbox -Identity $e.Name -CustomAttribute1 $e.Note
    Set-CalendarProcessing -Identity $e.Name -AutomateProcessing AutoAccept
    Write-Host "✔ Resurs: $($e.Name)" -ForegroundColor Green
}

Write-Host "=== Alla resurser och postlådor är klara! ===" -ForegroundColor Cyan
