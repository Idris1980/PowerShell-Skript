<#
.SYNOPSIS
    Återställer lösenordet för alla användare i en OU.

.DESCRIPTION
    Sätter ett nytt lösenord på samtliga användare i den valda OU:n (inklusive
    under-OU:er) och tvingar fram lösenordsbyte vid nästa inloggning.
    Det nya lösenordet frågas efter vid körning och skrivs aldrig i klartext.

.PARAMETER OU
    DistinguishedName för OU:n. Utelämnas den får du välja OU i en lista.

.EXAMPLE
    .\Aterstall-LosenordIOU.ps1 -OU "OU=Admins,OU=Users,OU=Foretaget,DC=lab,DC=local"
#>

param(
    [string]$OU
)

Import-Module ActiveDirectory

if (-not $OU) {
    $OU = (Get-ADOrganizationalUnit -Filter * |
        Select-Object Name, DistinguishedName |
        Out-GridView -Title "Välj OU vars användare ska få nytt lösenord" -PassThru).DistinguishedName
    if (-not $OU) { Write-Host "Ingen OU vald. Avbryter." -ForegroundColor Yellow; return }
}

$newPassword = Read-Host "Ange nytt lösenord" -AsSecureString

# Hämta användare
$users = Get-ADUser -Filter * -SearchBase $OU

Write-Host "$(@($users).Count) användare i $OU kommer att få nytt lösenord." -ForegroundColor Yellow
$confirm = Read-Host "Fortsätta? (J/N)"
if ($confirm -notin @("J","j","Ja","ja")) { Write-Host "Avbrutet." -ForegroundColor Yellow; return }

foreach ($user in $users) {
    try {
        Set-ADAccountPassword -Identity $user -Reset -NewPassword $newPassword -ErrorAction Stop
        Set-ADUser -Identity $user -ChangePasswordAtLogon $true

        Write-Host "✔ Lösenord ändrat för: $($user.SamAccountName)" -ForegroundColor Green
    }
    catch {
        Write-Host "✖ Fel vid ändring för: $($user.SamAccountName) – $($_.Exception.Message)" -ForegroundColor Red
    }
}
