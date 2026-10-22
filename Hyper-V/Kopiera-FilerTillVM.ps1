<#
.SYNOPSIS
    Kopierar filer från Hyper-V-värden in i en VM (t.ex. installationsfiler för Exchange).

.DESCRIPTION
    Använder Copy-VMFile (Guest Service Interface) för att kopiera alla filer
    i en mapp på värden till en mapp i gästen, utan nätverk eller delade mappar.
    Med -Extension kan du begränsa till vissa filtyper.

.PARAMETER VMName
    VM:en som filerna ska kopieras till.

.PARAMETER SourcePath
    Mapp på värden med filerna.

.PARAMETER DestinationPath
    Mapp i gästen. Standard: C:\Exchange

.PARAMETER Extension
    Valfritt filter, t.ex. ".exe",".msi".

.EXAMPLE
    .\Kopiera-FilerTillVM.ps1 -VMName EX01 -SourcePath D:\Nedladdningar\Exchange -Extension .exe,.msi

.NOTES
    Guest Service Interface måste vara aktiverat:
        Enable-VMIntegrationService -VMName <namn> -Name "Guest Service Interface"
#>

param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [string]$SourcePath,

    [string]$DestinationPath = "C:\Exchange",

    [string[]]$Extension
)

Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue

$Files = Get-ChildItem -Path $SourcePath -File
if ($Extension) {
    $Files = $Files | Where-Object { $_.Extension -in $Extension }
}

foreach ($File in $Files) {
    Write-Host "Kopierar $($File.Name)..." -ForegroundColor Cyan
    Copy-VMFile -Name $VMName `
        -SourcePath $File.FullName `
        -DestinationPath (Join-Path $DestinationPath $File.Name) `
        -CreateFullPath `
        -FileSource Host `
        -Force
}

Write-Host "Klart! $(@($Files).Count) fil(er) kopierade till ${VMName}: $DestinationPath" -ForegroundColor Green
