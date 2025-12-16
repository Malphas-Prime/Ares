param(
    [switch]$DevMode # optional: run from local folder for testing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework

# ---------------------------
# Config: where modules live
# ---------------------------
if ($DevMode) {
    $Global:ModuleBase = Split-Path -Parent $PSCommandPath
} else {
    $Global:ModuleBase = "https://raw.githubusercontent.com/Malphas-Prime/Ares/main/PrepUtility"
}

function Get-RemoteScript {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ($DevMode) {
        return Get-Content -Raw -Path (Join-Path $ModuleBase $RelativePath)
    } else {
        $url = "$ModuleBase/$RelativePath"
        Write-Host "Downloading: $url"
        return (Invoke-WebRequest -UseBasicParsing -Uri $url -ErrorAction Stop).Content
    }
}

# ---------------------------
# Data model – PSCustomObject
# ---------------------------
$Global:PrepTasks = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

function Add-PrepTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$ScriptPath
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

# ---------------------------
# Tasks (NO backticks — PS5.1 safe for iwr|iex)
# ---------------------------
Add-PrepTask -Name "Install Base Apps" -Description "Pick from top apps and install using winget." -ScriptPath "modules/01-Install-BaseApps.ps1"
Add-PrepTask -Name "Debloat / Privacy (WinUtil + O&O)" -Description "Debloat options + OO ShutUp10++ recommended config." -ScriptPath "modules/02-Remove-Bloat.ps1"
Add-PrepTask -Name "Apply Windows Defaults" -Description "Set power settings, Explorer options, taskbar, etc." -ScriptPath "modules/03-Set-Defaults.ps1"
Add-PrepTask -Name "Tweaks (WinUtil)" -Description "Pick and apply WinUtil tweaks (registry + scripts)." -ScriptPath "modules/04-Tweaks.ps1"
Add-PrepTask -Name "Join Domain / Configure User" -Description "Rename PC, add user, add to admins, join domain." -ScriptPath "modules/10-Join-Domain.ps1"
Add-PrepTask -Name "Send System Info to CRM" -Description "Install your RMM agent and security tools." -ScriptPath "modules/20-Sent-to-CRM.ps1"

# ---------------------------
# Load XAML from external file
# ---------------------------
if ($DevMode) {
    $xamlPath    = Join-Path $ModuleBase "UI.xaml"
    $XamlContent = Get-Content -Raw -Path $xamlPath
} else {
    $xamlUrl     = "$ModuleBase/UI.xaml"
    $XamlContent = (Invoke-WebRequest -UseBasicParsing -Uri $xamlUrl -ErrorAction Stop).Content
}

$Window      = [Windows.Markup.XamlReader]::Parse($XamlContent)
$Global:AresMainWindow = $Window   # allow child windows to set Owner

$TaskList    = $Window.FindName("TaskList")
$RunButton   = $Window.FindName("RunButton")
$CloseButton = $Window.FindName("CloseButton")
$StatusText  = $Window.FindName("StatusText")

# Machine info fields (optional; only if UI.xaml contains them)
$HostNameText = $Window.FindName("HostNameText")
$ActiveIpText = $Window.FindName("ActiveIpText")
$ManagedAvText = $Window.FindName("ManagedAvText")
$RefreshInfoButton = $Window.FindName("RefreshInfoButton")

# Bind tasks to list
$TaskList.ItemsSource = $PrepTasks

function Get-ActiveIPv4 {
    try {
        if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
            $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
            if ($cfg -and $cfg.IPv4Address -and $cfg.IPv4Address.IPAddress) { return [string]$cfg.IPv4Address.IPAddress }
        }
    } catch { }

    # fallback (older systems)
    try {
        $ip = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true -and $_.DefaultIPGateway } | Select-Object -First 1).IPAddress
        if ($ip) {
            $v4 = $ip | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
            return [string]$v4
        }
    } catch { }

    return $null
}

function Test-NableManagedAVInstalled {
    # Best-effort detection. Adjust these as you confirm your environment.
    # Checks common product/service names for N-able / Managed Antivirus / Bitdefender used under N-able.
    $svcHits = @("ManagedAntivirus","Emsisoft","Bitdefender","BDAgent","bdredline","SolarWinds","N-able") # broad
    try {
        $svcs = Get-Service -ErrorAction SilentlyContinue
        foreach ($h in $svcHits) {
            if ($svcs | Where-Object { $_.Name -like "*$h*" -or $_.DisplayName -like "*$h*" }) { return $true }
        }
    } catch { }

    try {
        $uninstallPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($p in $uninstallPaths) {
            $apps = Get-ItemProperty $p -ErrorAction SilentlyContinue
            if ($apps | Where-Object { $_.DisplayName -match "N-?able|Managed Antivirus|SolarWinds|Bitdefender|Emsisoft" }) {
                return $true
            }
        }
    } catch { }

    return $false
}

function Update-MachineInfoUI {
    try {
        $hn = $env:COMPUTERNAME
        $ip = Get-ActiveIPv4
        $av = Test-NableManagedAVInstalled

        if ($HostNameText) { $HostNameText.Text = $hn }
        if ($ActiveIpText) { $ActiveIpText.Text = ($(if ($ip) { $ip } else { "Not found" })) }
        if ($ManagedAvText) { $ManagedAvText.Text = ($(if ($av) { "Detected" } else { "Not detected" })) }
    } catch {
        if ($ManagedAvText) { $ManagedAvText.Text = "Error" }
    }
}

if ($RefreshInfoButton) {
    $RefreshInfoButton.Add_Click({ Update-MachineInfoUI })
}

# ---------------------------
# Logic to run selected tasks
# ---------------------------
$RunButton.Add_Click({
    $selected = @($PrepTasks | Where-Object { $_.IsSelected })

    if (-not $selected -or $selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No tasks selected.", "Info", 'OK', 'Information') | Out-Null
        return
    }

    $RunButton.IsEnabled = $false
    $StatusText.Text = "Running tasks..."

    foreach ($task in $selected) {
        $task.Status = "Running..."
        $TaskList.Items.Refresh()

        # Allow child dialogs to appear on top by disabling Topmost on the main window while the module runs
        $prevTop = $Window.Topmost
        $Window.Topmost = $false

        try {
            $scriptContent = Get-RemoteScript -RelativePath $task.ScriptPath
            & ([scriptblock]::Create($scriptContent))
            $task.Status = "Completed"
        }
        catch {
            $task.Status = "Failed"
            Write-Warning "Task '$($task.Name)' failed: $($_.Exception.Message)"
        }
        finally {
            $Window.Topmost = $prevTop
        }

        $TaskList.Items.Refresh()
    }

    $StatusText.Text = "All selected tasks finished."
    $RunButton.IsEnabled = $true
})

$CloseButton.Add_Click({ $Window.Close() })

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

# Do NOT keep the main window always-on-top; modules will own/topmost themselves.
$Window.Topmost = $false

# Initial machine info
Update-MachineInfoUI

$null = $Window.ShowDialog()
