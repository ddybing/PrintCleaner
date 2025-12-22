<#
.SYNOPSIS
    PrintCleaner - A Terminal Utility to clean up printers and print queues.

.DESCRIPTION
    This script provides a text-based interface to:
    1. Remove all printers and drivers (preserving Microsoft defaults).
    2. Clear the Windows Print Spooler queue.
    3. Uninstall bundled printer software.
    Requires Administrator privileges.

.NOTES
    File Name      : PrintCleaner.ps1
    Author         : Gemini CLI
    Prerequisite   : Run as Administrator
#>

# --- Configuration ---
$AppVersion = "0.0.0" # Replaced by build script
$Host.UI.RawUI.WindowTitle = "PrintCleaner v$AppVersion"
$global:running = $true
$menuOptions = @("List Installed Printers", "Clean Print Queue", "Remove All Printers & Drivers", "Uninstall Printer Software", "Exit")
$selectionIndex = 0

# --- Helper Functions ---

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$currentUser
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Header {
    Clear-Host
    Write-Host "  ____       _       _   ____ _                            " -ForegroundColor Cyan
    Write-Host " |  _ \ _ __(_)_ __ | |_/ ___| | ___  __ _ _ __   ___ _ __ " -ForegroundColor Cyan
    Write-Host " | |_) | '__| | '_ \| __| |   | |/ _ \/ _' | '_ \ / _ \ '__|" -ForegroundColor Cyan
    Write-Host " |  __/| |  | | | | | |_| |___| |  __/ (_| | | | |  __/ |   " -ForegroundColor Cyan
    Write-Host " |_|   |_|  |_|_| |_|\__|\____|_|\___|\__,_|_| |_|\___|_|   " -ForegroundColor Cyan
    Write-Host "                                              v$AppVersion          " -ForegroundColor DarkGray
    Write-Host "Use UP/DOWN arrows to navigate, ENTER to select." -ForegroundColor Gray
    Write-Host ""
}

function Show-Menu {
    param (
        [int]$SelectedIndex
    )
    Show-Header
    for ($i = 0; $i -lt $menuOptions.Count; $i++) {
        if ($i -eq $SelectedIndex) {
            Write-Host " > $($menuOptions[$i])" -ForegroundColor Green -BackgroundColor DarkGray
        } else {
            Write-Host "   $($menuOptions[$i])" -ForegroundColor White
        }
    }
}

function Wait-Key {
    Write-Host "`nPress ENTER to return to menu..." -ForegroundColor DarkGray
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) { break }
    }
}

function Get-InstalledSoftware {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    # Use array subexpression to safely collect output objects. 
    # This avoids the "Hash table" addition error because we aren't using += on potentially mixed types.
    $list = @(foreach ($path in $paths) {
        $items = Get-ItemProperty $path -ErrorAction SilentlyContinue 
        foreach ($item in $items) {
             # FORCE STRING CONVERSION IMMEDIATELY
             $name = [string]$item.DisplayName
             $cmd = [string]$item.UninstallString
             
             if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($cmd)) {
                 # Output object to pipeline (collected by @())
                 [PSCustomObject]@{
                     DisplayName = $name
                     UninstallString = $cmd
                 }
             }
        }
    })
    
    return $list
}

# --- Action Functions ---

function Invoke-ListPrinters {
    Show-Header
    Write-Host "INSTALLED PRINTERS" -ForegroundColor Cyan
    Write-Host "------------------" -ForegroundColor Cyan
    
    try {
        $printers = Get-Printer -ErrorAction SilentlyContinue | Sort-Object Name
        
        if ($printers) {
            $printers | Format-Table -Property Name, DriverName, PortName -AutoSize | Out-String | Write-Host -ForegroundColor White
        } else {
            Write-Host "No printers found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[ERROR] Could not list printers: $($_.Exception.Message)" -ForegroundColor Red
    }
    Wait-Key
}

function Invoke-CleanQueue {
    Show-Header
    Write-Host "Cleaning Print Queue..." -ForegroundColor Yellow
    
    try {
        Write-Host "[-] Stopping Print Spooler service..."
        Stop-Service -Name "Spooler" -Force -ErrorAction Stop
        
        $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS\*"
        Write-Host "[-] Deleting spool files in $spoolPath..."
        Remove-Item -Path $spoolPath -Force -Recurse -ErrorAction SilentlyContinue
        
        Write-Host "[-] Restarting Print Spooler service..."
        Start-Service -Name "Spooler" -ErrorAction Stop
        
        Write-Host "`n[SUCCESS] Print queue cleared successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "`n[ERROR] Failed to clean queue: $($_.Exception.Message)" -ForegroundColor Red
    }
    Wait-Key
}

function Invoke-RemovePrinters {
    Show-Header
    Write-Host "WARNING: This will remove ALL printers and drivers (except MS defaults)." -ForegroundColor Red
    Write-Host "Are you sure? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -notmatch "^[Yy]$") {
        return
    }

    Write-Host "`nStarting Cleanup..." -ForegroundColor Yellow
    
    $removedPrinters = @()
    $removedDrivers = @()

    # 1. Remove Printers
    try {
        $printers = Get-Printer -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -ne "Microsoft Print to PDF" -and 
            $_.Name -ne "Microsoft XPS Document Writer" -and 
            $_.Name -ne "OneNote for Windows 10" 
        }

        if ($printers) {
            foreach ($p in $printers) {
                Write-Host "[-] Removing Printer: $($p.Name)"
                try {
                    Remove-Printer -Name $p.Name -ErrorAction Stop
                    $removedPrinters += $p.Name
                } catch {
                    Write-Host "    [!] Failed to remove $($p.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "[-] No printers found to remove." -ForegroundColor Gray
        }
    } catch {
        Write-Host "[!] Error accessing printers: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 2. Remove Drivers
    # Note: Drivers can only be removed if not in use. 
    # Sometimes requires restarting spooler or system to fully release.
    Write-Host "`nAttempting to remove unused drivers..." -ForegroundColor Yellow
    try {
        $drivers = Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notmatch "Microsoft" -and 
            $_.Provider -ne "Microsoft"
        }

        if ($drivers) {
            foreach ($d in $drivers) {
                Write-Host "[-] Removing Driver: $($d.Name)"
                try {
                    Remove-PrinterDriver -Name $d.Name -ErrorAction Stop
                    $removedDrivers += $d.Name
                } catch {
                    Write-Host "    [!] Locked or in use (skipping): $($d.Name)" -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Host "[-] No third-party drivers found." -ForegroundColor Gray
        }
    } catch {
        Write-Host "[!] Error accessing drivers: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- Summary Report ---
    Show-Header
    Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
    Write-Host "--------------" -ForegroundColor Cyan
    
    if ($removedPrinters.Count -gt 0) {
        Write-Host "`nRemoved Printers:" -ForegroundColor Green
        foreach ($p in $removedPrinters) {
            Write-Host "  [+] $p" -ForegroundColor White
        }
    } else {
        Write-Host "`nNo printers were removed." -ForegroundColor Gray
    }

    if ($removedDrivers.Count -gt 0) {
        Write-Host "`nRemoved Drivers:" -ForegroundColor Green
        foreach ($d in $removedDrivers) {
            Write-Host "  [+] $d" -ForegroundColor White
        }
    } else {
        Write-Host "`nNo drivers were removed." -ForegroundColor Gray
    }

    Wait-Key
}

function Invoke-UninstallSoftware {
    Show-Header
    Write-Host "SEARCHING FOR PRINTER SOFTWARE..." -ForegroundColor Yellow
    Write-Host "Scanning registry for common printer brands..." -ForegroundColor DarkGray

    # Common printer brands/keywords
    $brands = @("HP", "Hewlett-Packard", "Canon", "Epson", "Brother", "Xerox", "Kyocera", "Ricoh", "Lexmark", "Konica", "Samsung", "Oki", "Zebra", "Dymo", "Dell")
    
    $allSoftware = Get-InstalledSoftware
    
    # Simple array, no ArrayList to avoid potential type issues
    $matches = @()

    # Filter software list
    foreach ($sw in $allSoftware) {
        foreach ($brand in $brands) {
            if ($sw.DisplayName -match "(?i)\b$brand\b") { # Case insensitive regex match
                $matches += $sw
                break
            }
        }
    }
    
    if ($matches.Count -eq 0) {
        Write-Host "`nNo printer-related software found." -ForegroundColor Green
        Wait-Key
        return
    }

    # Selection Loop
    while ($true) {
        Show-Header
        Write-Host "FOUND PRINTER SOFTWARE" -ForegroundColor Cyan
        Write-Host "----------------------" -ForegroundColor Cyan
        Write-Host "The following software matched printer keywords."
        Write-Host "Select an item to launch its uninstaller." -ForegroundColor DarkGray
        Write-Host ""
        
        for ($i = 0; $i -lt $matches.Count; $i++) {
            # DISPLAY COMMAND IN MENU FOR DEBUGGING
            $truncCmd = $matches[$i].UninstallString
            if ($truncCmd.Length -gt 50) { $truncCmd = $truncCmd.Substring(0, 47) + "..." }
            
            Write-Host " [$($i+1)] $($matches[$i].DisplayName)" -ForegroundColor White
            Write-Host "       Cmd: $truncCmd" -ForegroundColor DarkGray
        }
        
        Write-Host ""
        Write-Host " [A] Uninstall ALL Listed Software (Auto-Silent)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Enter selection (or 'q' to return): " -NoNewline -ForegroundColor Yellow
        $input = Read-Host
        
        if ($input -eq 'q') {
            return
        }
        
        if ($input -match '^[Aa]$') {
            Write-Host "`nWARNING: This will attempt to silently uninstall ALL listed software." -ForegroundColor Red
            Write-Host "Are you sure? (Y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host
            if ($confirm -match '^[Yy]$') {
                $count = 0
                $total = $matches.Count
                
                foreach ($app in $matches) {
                    $count++
                    $percent = [int](($count / $total) * 100)
                    Write-Progress -Activity "Uninstalling Software" -Status "Removing: $($app.DisplayName)" -PercentComplete $percent
                    
                    $rawCmd = $app.UninstallString
                    
                    if ([string]::IsNullOrWhiteSpace($rawCmd)) {
                         Write-Host "   [!] Skipping: Uninstall string is empty." -ForegroundColor DarkGray
                         continue
                    }
                    $finalCmd = "$rawCmd"

                    # Add silent flags
                    if ($rawCmd -match "msiexec") {
                        if ($rawCmd -notmatch "/qn" -and $rawCmd -notmatch "/quiet") {
                            $finalCmd = "$finalCmd /qn /norestart"
                        }
                    } elseif ($rawCmd -match "uninstall.exe" -or $rawCmd -match "setup.exe") {
                        if ($rawCmd -notmatch "/S" -and $rawCmd -notmatch "/silent") {
                             $finalCmd = "$finalCmd /S /silent /quiet /norestart"
                        }
                    }
                    
                    Write-Host "[$count/$total] $($app.DisplayName)" -ForegroundColor Yellow
                    Write-Host "   Cmd: $finalCmd" -ForegroundColor DarkGray
                    
                    try {
                        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "$finalCmd" -Wait -WindowStyle Hidden
                    } catch {
                         Write-Host "   [!] Error launching: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    Start-Sleep -Seconds 1
                }
                Write-Progress -Activity "Uninstalling Software" -Completed
                Write-Host "`nDone processing list." -ForegroundColor Green
                Wait-Key
                return
            }
        }
        elseif ($input -match '^\d+$' -and [int]$input -le $matches.Count -and [int]$input -gt 0) {
            $idx = [int]$input - 1
            $app = $matches[$idx]
            
            Write-Host "Launching uninstaller for: $($app.DisplayName)..." -ForegroundColor Yellow
            $cmdToRun = $app.UninstallString
            if ([string]::IsNullOrWhiteSpace($cmdToRun)) {
                 Write-Host "[ERROR] Uninstall string is empty. (Debug: '$cmdToRun')" -ForegroundColor Red
                 Start-Sleep -Seconds 2
                 continue
            }
            
            Write-Host "Cmd: $cmdToRun" -ForegroundColor DarkGray
            
            try {
                 Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "$cmdToRun" -PassThru
                 Start-Sleep -Seconds 2
            } catch {
                Write-Host "Error launching uninstaller: $($_.Exception.Message)" -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}

# --- Main Loop ---

if (-not (Test-Administrator)) {
    Write-Host "ERROR: This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "Please right-click and 'Run with PowerShell' as Administrator."
    Exit
}

try {
    # Hide cursor for cleaner look
    $originalCursorSize = $Host.UI.RawUI.CursorSize
    $Host.UI.RawUI.CursorSize = 0
} catch {
    # Ignore if console doesn't support cursor hiding
}

while ($global:running) {
    Show-Menu -SelectedIndex $selectionIndex
    
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    switch ($key.VirtualKeyCode) {
        38 { # Up Arrow
            if ($selectionIndex -gt 0) { $selectionIndex-- }
        }
        40 { # Down Arrow
            if ($selectionIndex -lt ($menuOptions.Count - 1)) { $selectionIndex++ }
        }
        13 { # Enter
            switch ($selectionIndex) {
                0 { Invoke-ListPrinters }
                1 { Invoke-CleanQueue }
                2 { Invoke-RemovePrinters }
                3 { Invoke-UninstallSoftware }
                4 { $global:running = $false }
            }
        }
        27 { # Escape
            $global:running = $false 
        }
    }
}

Clear-Host
try { $Host.UI.RawUI.CursorSize = 25 } catch {} # Restore cursor
Write-Host "Exiting PrintCleaner. Goodbye!" -ForegroundColor Cyan