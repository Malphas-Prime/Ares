param(
    [switch]$DevMode # optional: run from local folder for testing
)

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
# Data model – PSCustomObject
# ---------------------------
Add-Type -AssemblyName PresentationFramework

$Global:PrepTasks = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

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

# Define tasks (edit these to suit your environment)
Add-PrepTask -Name "Install Base Apps" `
             -Description "Install browser, 7-Zip, PDF reader, etc." `
             -ScriptPath "modules/01-Install-BaseApps.ps1"

Add-PrepTask -Name "Remove OEM Bloat" `
             -Description "Remove pre-installed OEM crapware and UWP junk." `
             -ScriptPath "modules/02-Remove-Bloat.ps1"

Add-PrepTask -Name "Apply Windows Defaults" `
             -Description "Set power settings, Explorer options, taskbar, etc." `
             -ScriptPath "modules/03-Set-Defaults.ps1"

Add-PrepTask -Name "Join Domain / Configure User" `
             -Description "Join domain, set local admin, rename PC." `
             -ScriptPath "modules/10-Join-Domain.ps1"

Add-PrepTask -Name "Install RMM / AV" `
             -Description "Install your RMM agent and security tools." `
             -ScriptPath "modules/20-Install-RMM.ps1"

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

# Bind tasks to list
$TaskList.ItemsSource = $PrepTasks

# ---------------------------
# Logic to run selected tasks
# ---------------------------
$RunButton.Add_Click({
    $selected = $PrepTasks | Where-Object { $_.IsSelected }

    if (-not $selected) {
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
            Write-Warning "Task '$($task.Name)' failed: $_"
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

$Window.Topmost = $true
$Window.ShowDialog() | Out-Null
