param(
    [switch]$DevMode # optional: run from local folder for testing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------
# Config: where modules live
# ---------------------------
if ($DevMode) {
    $Global:ModuleBase = Split-Path -Parent $PSCommandPath
}
else {
    # Raw GitHub URL pointing at this folder
    $Global:ModuleBase = "https://raw.githubusercontent.com/Malphas-Prime/Ares/main/PrepUtility"
}

function Get-RemoteScript {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ($DevMode) {
        return Get-Content -Raw -Path (Join-Path $ModuleBase $RelativePath)
    }
    else {
        $url = "$ModuleBase/$RelativePath"
        Write-Host "Downloading: $url"
        return (Invoke-WebRequest -UseBasicParsing -Uri $url -ErrorAction Stop).Content
    }
}

# ---------------------------
# UI + Types
# ---------------------------
Add-Type -AssemblyName PresentationFramework

# ---------------------------
# Machine info helpers (PS5.1 safe)
# ---------------------------
function Get-HostName {
    return $env:COMPUTERNAME
}

function Get-ActiveIPv4 {
    try {
        # Prefer adapter with default route
        $defaultIfIndex = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
            Sort-Object RouteMetric, ifMetric |
            Select-Object -First 1).InterfaceIndex

        if ($null -ne $defaultIfIndex) {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $defaultIfIndex -ErrorAction Stop
            $ip  = ($cfg.IPv4Address | Select-Object -First 1).IPv4Address
            if ($ip) { return $ip }
        }

        # Fallback: any UP adapter with a non-APIPA IPv4
        $cfg2 = Get-NetIPConfiguration |
            Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
            ForEach-Object {
                [pscustomobject]@{
                    IP = ($_.IPv4Address | Select-Object -First 1).IPv4Address
                }
            } |
            Where-Object { $_.IP -and $_.IP -notlike "169.254.*" } |
            Select-Object -First 1

        return $cfg2.IP
    }
    catch {
        return $null
    }
}

function Test-NableManagedAV {
    # Best-effort detection (common N-able Managed AV deployments are Bitdefender-based)
    $hit = [ordered]@{
        Detected = $false
        Evidence = @()
    }

    # Service hints (varies by version)
    $serviceHints = @(
        "bdservicehost",
        "bdredline",
        "EPIntegrationService",
        "Bitdefender*",
        "BD*"
    )

    foreach ($s in $serviceHints) {
        try {
            $svcs = Get-Service -Name $s -ErrorAction SilentlyContinue
            foreach ($svc in @($svcs)) {
                if ($svc) {
                    $hit.Detected = $true
                    $hit.Evidence += ("Service: {0} ({1})" -f $svc.Name, $svc.Status)
                }
            }
        } catch { }
    }

    # Uninstall registry (more reliable for product naming)
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $nameHints = @(
        "N-able Managed Antivirus",
        "Managed Antivirus",
        "N-able",
        "Bitdefender Endpoint Security Tools",
        "Bitdefender"
    )

    foreach ($path in $uninstallPaths) {
        try {
            $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            foreach ($a in @($apps)) {
                $dn = $a.DisplayName
                if (-not $dn) { continue }

                foreach ($hint in $nameHints) {
                    if ($dn -like "*$hint*") {
                        $hit.Detected = $true
                        $ver = $a.DisplayVersion
                        if ($ver) {
                            $hit.Evidence += ("App: {0} ({1})" -f $dn, $ver)
                        } else {
                            $hit.Evidence += ("App: {0}" -f $dn)
                        }
                        break
                    }
                }
            }
        } catch { }
    }

    return [pscustomobject]$hit
}

# ---------------------------
# Data model – PSCustomObject
# ---------------------------
$Global:PrepTasks = New-Object System.Collections.ObjectModel.ObservableCollection[object]

function Add-PrepTask {
    param(
        [string]$Name,
        [string]$Description,
        [string]$ScriptPath
    )

    $obj = [pscustomobject]@{
        IsSelected  = $false
        Name        = $Name
        Description = $Description
        ScriptPath  = $ScriptPath
        Status      = ""
    }

    [void]$Global:PrepTasks.Add($obj)
}

# Define tasks
Add-PrepTask -Name "Install Base Apps" `
             -Description "Pick from the standard app list and install via WinGet." `
             -ScriptPath "modules/01-Install-BaseApps.ps1"

Add-PrepTask -Name "Remove OEM Bloat" `
             -Description "Remove pre-installed OEM crapware and UWP junk." `
             -ScriptPath "modules/02-Remove-Bloat.ps1"

Add-PrepTask -Name "Apply Windows Defaults" `
             -Description "Set power settings, Explorer options, taskbar, etc." `
             -ScriptPath "modules/03-Set-Defaults.ps1"

Add-PrepTask -Name "Join Domain / Configure User" `
             -Description "Rename PC, add users, add admins, join domain." `
             -ScriptPath "modules/10-Join-Domain.ps1"

Add-PrepTask -Name "Send System Info to CRM" `
             -Description "Install your RMM agent and security tools." `
             -ScriptPath "modules/20-Sent-to-CRM.ps1"

# ---------------------------
# Load XAML from external file
# ---------------------------
if ($DevMode) {
    $xamlPath    = Join-Path $ModuleBase "UI.xaml"
    $XamlContent = Get-Content -Raw -Path $xamlPath
}
else {
    $xamlUrl     = "$ModuleBase/UI.xaml"
    $XamlContent = (Invoke-WebRequest -UseBasicParsing -Uri $xamlUrl -ErrorAction Stop).Content
}

$Window      = [Windows.Markup.XamlReader]::Parse($XamlContent)
$TaskList    = $Window.FindName("TaskList")
$RunButton   = $Window.FindName("RunButton")
$CloseButton = $Window.FindName("CloseButton")
$StatusText  = $Window.FindName("StatusText")

# Machine info UI elements (added in UI.xaml)
$HostNameText      = $Window.FindName("HostNameText")
$ActiveIpText      = $Window.FindName("ActiveIpText")
$ManagedAvText     = $Window.FindName("ManagedAvText")
$RefreshInfoButton = $Window.FindName("RefreshInfoButton")

# Bind tasks to list
$TaskList.ItemsSource = $PrepTasks

function Update-MachineInfoUI {
    $hn = Get-HostName
    $ip = Get-ActiveIPv4
    $av = Test-NableManagedAV

    if ($HostNameText) { $HostNameText.Text = $hn }

    if ($ActiveIpText) {
        if ([string]::IsNullOrWhiteSpace($ip)) {
            $ActiveIpText.Text = "Not found"
        } else {
            $ActiveIpText.Text = $ip
        }
    }

    if ($ManagedAvText) {
        if ($av.Detected) { $ManagedAvText.Text = "Detected" }
        else { $ManagedAvText.Text = "Not detected" }
    }

    # Keep footer helpful but short
    if ($av.Detected -and $av.Evidence -and $av.Evidence.Count -gt 0) {
        $StatusText.Text = $av.Evidence[0]
    } else {
        $StatusText.Text = ""
    }
}

# Populate on load
Update-MachineInfoUI

# Refresh button
if ($RefreshInfoButton) {
    $RefreshInfoButton.Add_Click({
        Update-MachineInfoUI
    })
}

# ---------------------------
# Logic to run selected tasks
# ---------------------------
$RunButton.Add_Click({
    $selected = @($PrepTasks | Where-Object { $_.IsSelected })

    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No tasks selected.", "Info", 'OK', 'Information') | Out-Null
        return
    }

    $RunButton.IsEnabled = $false
    $StatusText.Text = "Running tasks..."

    foreach ($task in $selected) {
        $task.Status = "Running..."
        $TaskList.Items.Refresh()

        try {
            $scriptContent = Get-RemoteScript -RelativePath $task.ScriptPath
            & ([scriptblock]::Create($scriptContent))
            $task.Status = "Completed"
        }
        catch {
            $task.Status = "Failed"
            Write-Warning ("Task '{0}' failed: {1}" -f $task.Name, $_.Exception.Message)
        }

        $TaskList.Items.Refresh()
    }

    $StatusText.Text = "All selected tasks finished."
    $RunButton.IsEnabled = $true
})

$CloseButton.Add_Click({
    $Window.Close()
})

# ---------------------------
# Admin check & show window
# ---------------------------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {

    [System.Windows.MessageBox]::Show(
        "Run PowerShell as Administrator for best results.",
        "Warning", 'OK', 'Warning'
    ) | Out-Null
}

$Window.Topmost = $false
$Window.ShowDialog() | Out-Null
