<#
.SYNOPSIS
    Aktiverar fjärråtkomst (Dial-in / "Allow access") för alla användare i angivna grupper.

.DESCRIPTION
    Går igenom varje grupp (rekursivt, så nästlade grupper följer med) och
    sätter attributet msNPAllowDialin = TRUE på alla användare. Det motsvarar
    "Network Access Permission: Allow access" på fliken Dial-in i ADUC och
    behövs t.ex. för VPN-anslutning via RRAS/NPS.

.PARAMETER Groups
    En eller flera gruppnamn.

.EXAMPLE
    .\Aktivera-DialInForGrupper.ps1 -Groups "VPN-Anvandare","GG_IT"
#>

param(
    [Parameter(Mandatory)]
    [string[]]$Groups
)

Import-Module ActiveDirectory

foreach ($group in $Groups) {

    Write-Host "`nBearbetar grupp: $group" -ForegroundColor Cyan

    # Hämta användare i gruppen
    $users = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.ObjectClass -eq "user" }

    foreach ($user in $users) {
        try {
            Set-ADUser -Identity $user.DistinguishedName -Replace @{msNPAllowDialin=$true} -ErrorAction Stop
            Write-Host "✔ Dial-in aktiverat för: $($user.SamAccountName)" -ForegroundColor Green
        }
        catch {
            Write-Host "✖ Fel för: $($user.SamAccountName) – $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
