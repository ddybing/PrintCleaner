<#
.SYNOPSIS
    Lists installed software and their GUIDs/Registry Keys.

.DESCRIPTION
    This script scans the Windows Registry (HKLM and WOW6432Node) for installed applications
    and outputs their Display Name and Registry Key Name (which is often the MSI GUID).
    
    Useful for finding the GUID of software to target for uninstallation.

.PARAMETER Filter
    Optional string to filter the results by Display Name.

.EXAMPLE
    .\GetGUIDApp.ps1
    Lists all installed software in a grid view.

.EXAMPLE
    .\GetGUIDApp.ps1 -Filter "Printer"
    Lists only software with "Printer" in the name.
#>

param (
    [string]$Filter = ""
)

$paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

Write-Host "Scanning Registry for Installed Software..." -ForegroundColor Cyan

$results = @()

foreach ($path in $paths) {
    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($item.DisplayName)) {
            $results += [PSCustomObject]@{
                DisplayName     = $item.DisplayName
                RegistryKeyName = $item.PSChildName # This is the GUID for MSI apps
                UninstallString = $item.UninstallString
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($Filter)) {
    Write-Host "Filtering for: '$Filter'" -ForegroundColor Yellow
    $results = $results | Where-Object { $_.DisplayName -match "(?i)$Filter" }
}

$results | Sort-Object DisplayName | Out-GridView -Title "Installed Software (Select to see details)"

Write-Host "Done. Check the Grid View window." -ForegroundColor Green