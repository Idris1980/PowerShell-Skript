<#
.SYNOPSIS
    Skapar en L2TP/IPsec-VPN-anslutning med förutdelad nyckel (PSK) på en klient.

.DESCRIPTION
    Lägger till en VPN-anslutning i Windows med tunneltyp L2TP, autentisering
    MS-CHAPv2 och krypteringsnivå Required. Finns en anslutning med samma
    namn redan görs ingenting. Den förutdelade nyckeln frågas efter vid
    körning så att den inte sparas i skriptet.

.PARAMETER VpnName
    Namnet på anslutningen som visas i Windows.

.PARAMETER ServerAddress
    VPN-serverns DNS-namn eller IP-adress.

.EXAMPLE
    .\Lagg-TillVPNAnslutning.ps1 -VpnName "Företag VPN" -ServerAddress vpn.lab.local

.NOTES
    Kör på klientdatorn. Servern ska ha RRAS konfigurerat för L2TP med samma PSK.
    Användarna behöver ha Dial-in tillåtet (se ActiveDirectory\Aktivera-DialInForGrupper.ps1).
#>

param(
    [Parameter(Mandatory)]
    [string]$VpnName,

    [Parameter(Mandatory)]
    [string]$ServerAddress
)

# Kontrollera om VPN-anslutningen redan finns
$existingVpn = Get-VpnConnection -Name $VpnName -ErrorAction SilentlyContinue

if ($existingVpn) {
    Write-Output "VPN-anslutning '$VpnName' finns redan."
} else {
    $securePsk = Read-Host "Ange förutdelad nyckel (PSK)" -AsSecureString
    $psk = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePsk))

    Add-VpnConnection -Name $VpnName `
        -ServerAddress $ServerAddress `
        -TunnelType L2tp `
        -L2tpPsk $psk `
        -AuthenticationMethod MSChapv2 `
        -EncryptionLevel Required `
        -Force

    Write-Output "VPN-anslutning '$VpnName' skapad."
}
