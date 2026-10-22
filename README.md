# PowerShell-skript för Windows Server, Active Directory, Exchange & Hyper-V

En samling PowerShell-skript som jag har skrivit under min utbildning för att automatisera uppsättning och administration av en Windows Server-miljö: från att bygga virtuella maskiner i Hyper-V till att skapa en AD-domän, importera användare och sätta upp Exchange Server 2019.

Alla skript har hjälptext i början av filen. Visa den med:

```powershell
Get-Help .\ActiveDirectory\Importera-AnvandareFranCSV.ps1 -Full
```

> ⚠️ Skripten är byggda för **labb- och utbildningsmiljöer**. Läs igenom och testa dem i en testmiljö innan du kör dem mot en produktionsmiljö.

---

## Innehåll

### 🖥️ Hyper-V
| Skript | Beskrivning |
|---|---|
| [Skapa-VM-ZeroTouch.ps1](Hyper-V/Skapa-VM-ZeroTouch.ps1) | Bygger helt obevakade Windows Server-VM:ar direkt från ISO (unattend.xml). Kan skapa en ny AD-domän och ansluta övriga servrar automatiskt, installera roller och ger en slutrapport i HTML. |
| [Skapa-VM-Interaktivt.ps1](Hyper-V/Skapa-VM-Interaktivt.ps1) | Skapar en eller flera Gen 2-VM:ar som bootar från en vald ISO. |
| [Skapa-VM-FranGoldenImage.ps1](Hyper-V/Skapa-VM-FranGoldenImage.ps1) | Skapar VM:ar snabbt genom att kopiera en sysprepad mall-VHDX. |
| [Backup-VM.ps1](Hyper-V/Backup-VM.ps1) | Exporterar utvalda VM:ar till tidsstämplade mappar med loggfil. |
| [Exportera-AllaVM.ps1](Hyper-V/Exportera-AllaVM.ps1) | Exporterar alla VM:ar (t.ex. till extern disk) och startar om de som var igång. |
| [Ta-BortVM.ps1](Hyper-V/Ta-BortVM.ps1) | Tar bort en VM och dess diskar. |
| [Kopiera-FilerTillVM.ps1](Hyper-V/Kopiera-FilerTillVM.ps1) | Kopierar filer från värden in i en VM med `Copy-VMFile`. |

### 🏗️ Server (uppsättning av ny domän)
| Skript | Beskrivning |
|---|---|
| [Master-Lab-Toolkit.ps1](Server/Master-Lab-Toolkit.ps1) | Allt-i-ett-meny: skapa VM:ar, IP/roller, AD-skog, DHCP och AD-administration. |
| [1-Konfigurera-NyServer.ps1](Server/1-Konfigurera-NyServer.ps1) | Steg 1: statisk IP, DNS, IPv6-policy, datornamn och rollerna AD DS/DNS/DHCP. |
| [2-Installera-ADForest.ps1](Server/2-Installera-ADForest.ps1) | Steg 2: skapar en ny AD-skog. |
| [3-Konfigurera-DHCP.ps1](Server/3-Konfigurera-DHCP.ps1) | Steg 3: auktoriserar DHCP, skapar scope och options. |
| [Skapa-DeladeMapparMedGPO.ps1](Server/Skapa-DeladeMapparMedGPO.ps1) | Skapar och delar ut avdelningsmappar och länkar en GPO för mappade enheter. |
| [Lagg-TillVPNAnslutning.ps1](Server/Lagg-TillVPNAnslutning.ps1) | Skapar en L2TP/IPsec-VPN-anslutning på en klient. |

### 👥 Active Directory
| Skript | Beskrivning |
|---|---|
| [AD-Administrationsmeny.ps1](ActiveDirectory/AD-Administrationsmeny.ps1) | Meny för OU:er, grupper och CSV-import med kolumnmappning och förhandsgranskning. |
| [Importera-AnvandareFranCSV.ps1](ActiveDirectory/Importera-AnvandareFranCSV.ps1) | Enkel CSV-import till en vald OU (åäö hanteras i användarnamn). |
| [Importera-AnvandareMedAvdelningar.ps1](ActiveDirectory/Importera-AnvandareMedAvdelningar.ps1) | CSV-import som automatiskt skapar OU + GL_/DL_-grupper per avdelning (AGDLP). |
| [Skapa-AnvandareGUI.ps1](ActiveDirectory/Skapa-AnvandareGUI.ps1) | Grafiskt formulär för att skapa en användare. |
| [Skapa-AvdelningsOU.ps1](ActiveDirectory/Skapa-AvdelningsOU.ps1) | Skapar en Departments-OU med under-OU per avdelning. |
| [Skapa-Sakerhetsgrupper.ps1](ActiveDirectory/Skapa-Sakerhetsgrupper.ps1) | Skapar en uppsättning globala säkerhetsgrupper. |
| [Flytta-AnvandareTillAvdelningsOU.ps1](ActiveDirectory/Flytta-AnvandareTillAvdelningsOU.ps1) | Flyttar användare till rätt avdelnings-OU enligt CSV. |
| [Lagg-AnvandareIAvdelningsgrupper.ps1](ActiveDirectory/Lagg-AnvandareIAvdelningsgrupper.ps1) | Lägger användare i GG_<avdelning>-grupper enligt CSV. |
| [Aterstall-LosenordIOU.ps1](ActiveDirectory/Aterstall-LosenordIOU.ps1) | Återställer lösenordet för alla användare i en OU. |
| [Aktivera-DialInForGrupper.ps1](ActiveDirectory/Aktivera-DialInForGrupper.ps1) | Tillåter fjärråtkomst (Dial-in/VPN) för alla medlemmar i grupper. |
| [Ta-BortOU.ps1](ActiveDirectory/Ta-BortOU.ps1) | Tar bort en OU med allt innehåll (inkl. raderingsskydd). |

### 📧 Exchange Server 2019
| Skript | Beskrivning |
|---|---|
| [Installera-Exchange2019.ps1](Exchange/Installera-Exchange2019.ps1) | Installerar alla förutsättningar, förbereder AD och installerar Exchange (Desktop Experience). |
| [Installera-Exchange2019-Core.ps1](Exchange/Installera-Exchange2019-Core.ps1) | Samma flöde för Windows Server Core. |
| [Exchange-AdminVerktyg-GUI.ps1](Exchange/Exchange-AdminVerktyg-GUI.ps1) | GUI med flikar för användare, delade postlådor, grupper, rum, utrustning och domäner. |
| [Skapa-AnvandareMedMailbox.ps1](Exchange/Skapa-AnvandareMedMailbox.ps1) | Skapar en användare med mailbox, delad postlåda, distributionsgrupp och AD-grupper. |
| [Provisionera-ExchangeForOU.ps1](Exchange/Provisionera-ExchangeForOU.ps1) | Mailbox för hela OU:n, delad postlåda, grupp, mötesrum och accepterad domän. |
| [Skapa-ResurserOchPostlador.ps1](Exchange/Skapa-ResurserOchPostlador.ps1) | Skapar delade postlådor, mötesrum och utrustning från listor. |
| [Skapa-MailaktiveradGruppFranOU.ps1](Exchange/Skapa-MailaktiveradGruppFranOU.ps1) | Mail-aktiverad säkerhetsgrupp med alla aktiva användare i en OU. |
| [Konfigurera-VirtuellaKataloger.ps1](Exchange/Konfigurera-VirtuellaKataloger.ps1) | Sätter URL:er för OWA/ECP/EWS/MAPI/Autodiscover m.fl. och kan skapa SAN-certifikat. |

### 💾 Backup
| Skript | Beskrivning |
|---|---|
| [Arkivera-WSBBackup.ps1](Backup/Arkivera-WSBBackup.ps1) | Sparar den senaste Windows Server Backup-disken med tidsstämpel i en arkivmapp. |

### 📝 Fusklappar
- [AD-och-Server.md](Fusklappar/AD-och-Server.md) – nätverk, roller, domänanslutning, fjärrhantering, användare och OU:er
- [Exchange.md](Fusklappar/Exchange.md) – mailboxar, grupper, resurser, domäner, certifikat och felsökning

### 📄 Exempeldata
Fiktiva CSV-filer som visar formatet som importskripten förväntar sig, se [Exempeldata/](Exempeldata/). Spara egna CSV-filer som **UTF-8** (i Excel: *CSV UTF-8*) så att å, ä och ö blir rätt.

---

## Typiskt flöde för en ny labbmiljö

1. **Hyper-V-värden:** `Hyper-V\Skapa-VM-ZeroTouch.ps1` – bygger DC + medlemsservrar automatiskt
   *(eller `Skapa-VM-Interaktivt.ps1` och installera Windows manuellt)*
2. **Domänkontrollanten** (om du inte använde zero-touch):
   `Server\1-Konfigurera-NyServer.ps1` → `2-Installera-ADForest.ps1` → `3-Konfigurera-DHCP.ps1`
3. **AD-struktur och användare:** `ActiveDirectory\AD-Administrationsmeny.ps1` eller
   `Importera-AnvandareMedAvdelningar.ps1`
4. **Exchange:** `Hyper-V\Kopiera-FilerTillVM.ps1` → `Exchange\Installera-Exchange2019.ps1` →
   `Konfigurera-VirtuellaKataloger.ps1` → `Provisionera-ExchangeForOU.ps1`

## Krav

- Windows Server 2019/2022 och Windows PowerShell 5.1
- Kör skripten som administratör
- Moduler beroende på skript: `ActiveDirectory` (RSAT), `Hyper-V`, `DhcpServer`, `ADDSDeployment`, `GroupPolicy`
- Exchange-skripten körs i **Exchange Management Shell**

Om körning av skript är blockerat:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Säkerhet

Inga lösenord är hårdkodade i skripten – startlösenord, DSRM-lösenord och VPN-nycklar frågas efter när skriptet körs. Lägg aldrig in riktiga lösenord, kunddata eller riktiga användarlistor i repot.

## Licens

Släppt under [MIT-licensen](LICENSE) – fritt att använda, ändra och dela vidare.
