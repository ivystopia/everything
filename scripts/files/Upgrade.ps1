# ===========================================
#       Pre-reboot Windows Update Script
# ===========================================

$ssdDrives = @("C", "E") # Windows sucks at detecting SSDs

# Function Definitions for Consistent Output
function Write-Info {
    param ([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param ([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-WarningMsg {
    param ([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param ([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

# Consistent Separator for Clear Section Divisions
function Write-Separator {
    Write-Host "=============================================" -ForegroundColor DarkGray
}

# ===========================================
#       Check for Administrative Privileges
# ===========================================
$currentUser = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-ErrorMsg "This script must be run as an administrator. Exiting..."
    exit 1
}

# ===========================================
#               Summary of Tasks
# ===========================================
Write-Separator
Write-Host "This script will perform the following tasks:" -ForegroundColor Yellow
Write-Host "
1. Check available disk space
2. Ensure essential services are running
3. Synchronize system time
4. Perform SSD TRIM operations
5. Install Windows updates
6. Schedule diagnostics and disk check
7. Clean up temporary files
8. Upgrade Chocolatey packages
" -ForegroundColor Cyan
Write-Host "Press 'Enter' to continue or 'Ctrl+C' to quit." -ForegroundColor Green
Write-Separator

# Force a pause by waiting for the Enter key
if (-not ($Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character -eq "`r")) {
    Write-ErrorMsg "Aborting script execution."
    exit
}

# ===========================================
#                   Preferences
# ===========================================
$VerbosePreference = 'SilentlyContinue'  # Suppress global verbose messages
$ErrorActionPreference = 'Stop'

# ===========================================
#           Start Script Execution
# ===========================================
Write-Separator
Write-Info "Starting Pre-reboot System Maintenance Script"
Write-Separator

# ===========================================
#        Report Available Disk Space
# ===========================================
Write-Info "Checking available disk space..."
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -and $_.Free }
foreach ($drive in $drives) {
    try {
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        Write-Info "Free disk space on $($drive.Name): $freeSpaceGB GB"
    }
    catch {
        Write-WarningMsg "Unable to retrieve free space for drive $($drive.Name)."
    }
}
Write-Separator

# ===========================================
#       Ensure Essential Services Are Running
# ===========================================
Write-Info "Ensuring essential services are running..."
$services = @("wuauserv", "bits", "cryptsvc", "msiserver")
foreach ($service in $services) {
    try {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq 'Stopped') {
                Write-Info "Starting service: $service"
                Start-Service -Name $service
                Write-Success "Service '$service' started."
            }
            else {
                Write-Info "Service '$service' is already running or in progress."
            }
        }
        else {
            Write-WarningMsg "Service '$service' not found."
        }
    }
    catch {
        Write-WarningMsg "Failed to start service '$service'."
    }
}
Write-Separator

# ===========================================
#             Synchronize System Time
# ===========================================
Write-Info "Starting time synchronization..."
try {
    net start w32time | Out-Null
    w32tm /resync /force | Out-Null
    Write-Success "Time synchronization completed."
}
catch {
    Write-WarningMsg "Failed to synchronize system time."
}
Write-Separator

# ===========================================
#                  Optimize SSD
# ===========================================
Write-Info "Starting SSD TRIM operation..."
foreach ($drive in $ssdDrives) {
    Write-Info "Starting TRIM operation on Drive $drive..."
    try {
        Optimize-Volume -DriveLetter $drive -ReTrim -Verbose:$false
        Write-Success "SSD TRIM operation completed on Drive $drive."
    }
    catch {
        Write-WarningMsg "SSD TRIM operation failed or is not supported on Drive $drive."
    }
}
Write-Separator

# ===========================================
#        Install Windows Updates
# ===========================================
Write-Info "Installing Windows Updates..."
try {
    Write-Info "Checking for PSWindowsUpdate module..."
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        if (-not (Get-InstalledModule -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
            Write-Info "Installing PSWindowsUpdate module..."
            Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
            Write-Success "PSWindowsUpdate module installed successfully."
        }
        else {
            Write-Info "PSWindowsUpdate module is already installed but not loaded."
        }
    }
    else {
        Write-Info "PSWindowsUpdate module is already available."
    }

    # Import the module
    Write-Info "Importing PSWindowsUpdate module..."
    Import-Module -Name PSWindowsUpdate -ErrorAction Stop
    Write-Success "PSWindowsUpdate module imported successfully."

    # Install updates
    Write-Info "Scanning for and installing Windows Updates..."
    $WindowsUpdatesInstalled = PSWindowsUpdate\Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Verbose:$false -ErrorAction Stop

    if ($WindowsUpdatesInstalled.Count -gt 0) {
        Write-Success "Windows Updates installed successfully."
    }
    else {
        Write-WarningMsg "No Windows updates were installed."
    }
}
catch {
    Write-WarningMsg "Failed to install Windows Updates."
    Write-WarningMsg "Error Details: $($_.Exception.Message)"
    Write-WarningMsg "Error StackTrace: $($_.Exception.StackTrace)"
    Write-WarningMsg "Inner Exception: $($_.Exception.InnerException)"
}
Write-Separator

# ===========================================
#          Schedule Disk Check
# ===========================================
Write-Info "Scheduling diagnostics and disk check..."
try {
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c chkdsk /R C:" -NoNewWindow -Wait
    Write-Success "Diagnostics scheduled and disk check initiated."
}
catch {
    Write-WarningMsg "Failed to schedule disk check."
}
Write-Separator

# ===========================================
#               Clean Up Temporary Files
# ===========================================
Write-Info "Cleaning up temporary files..."
try {
    # Get the temp directory path
    $tempDir = $env:TEMP

    # Check if the temp directory exists
    if (Test-Path -Path $tempDir) {
        # Remove all files and subdirectories in the temp directory
        Get-ChildItem -Path $tempDir -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

        Write-Success "Temporary files cleaned up successfully."
    }
    else {
        Write-WarningMsg "Temp directory does not exist: $tempDir"
    }
}
catch {
    Write-WarningMsg "An error occurred while cleaning up temporary files: $($_.Exception.Message)"
}

Write-Separator

# ===========================================
#          Upgrade Chocolatey Packages
# ===========================================
Write-Info "Upgrading Chocolatey packages..."
try {
    choco upgrade chocolatey -y | Out-Null
    Write-Success "Chocolatey updated successfully."

    choco upgrade all -y --no-progress
    Write-Success "All Chocolatey packages upgraded successfully."

    choco cache clean | Out-Null
    Write-Success "Chocolatey cache cleaned successfully."
}
catch {
    Write-WarningMsg "Failed to perform some Chocolatey operations."
}
Write-Separator

# ===========================================
#                Upgrade Report
# ===========================================
Write-Host "`n===========================================" -ForegroundColor Yellow
Write-Host "               Upgrade Report              " -ForegroundColor Yellow
Write-Host "===========================================" -ForegroundColor Yellow

if ($WindowsUpdatesInstalled -and $WindowsUpdatesInstalled.Count -gt 0) {
    Write-Success "`nThe following Windows updates were installed:"
    foreach ($update in $WindowsUpdatesInstalled) {
        Write-Host "  • $($update.Title)" -ForegroundColor Green
    }
}
else {
    Write-WarningMsg "`nNo Windows updates were installed."
}

Write-Success "`nAll Chocolatey packages have been upgraded."

if (choco list --local-only | Select-String "spicetify-cli") {
    $spicetifyVersion = choco list --local-only spicetify-cli | ForEach-Object { $_.Split('|')[1] }
    Write-WarningMsg "`nNote: 'spicetify-cli' was upgraded via Chocolatey to version $spicetifyVersion."
    Write-WarningMsg "`nRun 'spicetify update' from a user terminal."
}
Write-Separator

# ===========================================
#                 End of Script
# ===========================================
Write-Separator
Write-Success "Script execution finished."
Write-Separator
