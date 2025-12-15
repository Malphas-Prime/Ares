# modules/02-Remove-Bloat.ps1
# Ares Prep Utility - Debloat / Tweaks (CTT-style selectable options)
# Windows PowerShell 5.1 compatible

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (-not $isAdmin) {
        [System.Windows.MessageBox]::Show(
            "This module must be run as Administrator.",
            "Administrator Required", 'OK', 'Error'
        ) | Out-Null
        throw "Not running elevated."
    }
}

function Init-ChildWindow {
    param([Parameter(Mandatory)]$Window)

    try {
        if ($Global:AresMainWindow) {
            $Window.Owner = $Global:AresMainWindow
            $Window.WindowStartupLocation = "CenterOwner"
        } else {
            $Window.WindowStartupLocation = "CenterScreen"
        }
    } catch { }

    try { $Window.Topmost = $true } catch { }
}

function Ensure-Key {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("DWord","String","QWord","Binary")][string]$Type,
        [Parameter(Mandatory)]$Value
    )

    Ensure-Key -Path $Path
    if ($Type -eq "DWord") { New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value ([int]$Value) -Force | Out-Null; return }
    if ($Type -eq "QWord") { New-ItemProperty -Path $Path -Name $Name -PropertyType QWord -Value ([long]$Value) -Force | Out-Null; return }
    if ($Type -eq "Binary") { New-ItemProperty -Path $Path -Name $Name -PropertyType Binary -Value ([byte[]]$Value) -Force | Out-Null; return }
    New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value ([string]$Value) -Force | Out-Null
}

function Remove-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Stop-ServiceSafe {
    param([Parameter(Mandatory)][string]$Name)
    try { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue } catch { }
}

function Disable-ServiceSafe {
    param([Parameter(Mandatory)][string]$Name)
    try { Set-Service -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
}

function Disable-ScheduledTaskSafe {
    param([Parameter(Mandatory)][string]$TaskPath)
    try {
        $parts = $TaskPath.Trim("\") -split "\\"
        $taskName = $parts[-1]
        $taskFolder = "\" + (($parts[0..($parts.Count-2)] -join "\") + "\")
        if ($parts.Count -eq 1) { $taskFolder = "\" }
        Disable-ScheduledTask -TaskName $taskName -TaskPath $taskFolder -ErrorAction SilentlyContinue | Out-Null
    } catch { }
}

function Remove-AppxSafe {
    param([Parameter(Mandatory)][string[]]$PackagePatterns)

    foreach ($pat in $PackagePatterns) {
        # Installed for users
        try {
            Get-AppxPackage -AllUsers | Where-Object { $_.Name -like $pat } | ForEach-Object {
                try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue } catch { }
            }
        } catch { }

        # Provisioned image packages
        try {
            Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $pat } | ForEach-Object {
                try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null } catch { }
            }
        } catch { }
    }
}

function Uninstall-OneDrive {
    # Best-effort OneDrive uninstall (varies per build)
    $od1 = Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"
    $od2 = Join-Path $env:SystemRoot "System32\OneDriveSetup.exe"

    try { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue } catch { }

    if (Test-Path $od1) {
        & $od1 /uninstall | Out-Null
        return
    }
    if (Test-Path $od2) {
        & $od2 /uninstall | Out-Null
        return
    }
}

function Restart-Explorer {
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch { }
    Start-Sleep -Milliseconds 400
    try { Start-Process explorer.exe | Out-Null } catch { }
}

# -----------------------------
# Build option model
# -----------------------------
$Global:DebloatOptions = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

function Add-Opt {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][ValidateSet("Minimal","Recommended","Aggressive","None")][string]$Preset
    )

    $Global:DebloatOptions.Add([pscustomobject]@{
        IsSelected  = $false
        Id          = $Id
        Name        = $Name
        Description = $Description
        Category    = $Category
        Preset      = $Preset
        Status      = ""
    }) | Out-Null
}

# App removals (common “bloat”)
Add-Opt "RM_Xbox"        "Remove Xbox apps" "Removes Xbox app family (best-effort)." "Remove Apps" "Recommended"
Add-Opt "RM_Skype"       "Remove Skype" "Removes built-in Skype / communications app (where present)." "Remove Apps" "Recommended"
Add-Opt "RM_TeamsConsumer" "Remove consumer Teams" "Removes Microsoft Teams (consumer) app if installed." "Remove Apps" "Recommended"
Add-Opt "RM_Clipchamp"   "Remove Clipchamp" "Removes Clipchamp if present." "Remove Apps" "Recommended"
Add-Opt "RM_News"        "Remove News/Widgets app" "Removes News/Widgets components where possible." "Remove Apps" "Recommended"
Add-Opt "RM_Weather"     "Remove Weather" "Removes Microsoft Weather app." "Remove Apps" "Recommended"
Add-Opt "RM_Solitaire"   "Remove Solitaire" "Removes Microsoft Solitaire Collection." "Remove Apps" "Recommended"
Add-Opt "RM_TiktokEtc"   "Remove sponsored apps" "Removes common sponsored AppX patterns (where present)." "Remove Apps" "Recommended"
Add-Opt "RM_3DViewer"    "Remove 3D Viewer / Print3D" "Removes legacy 3D/Print apps if present." "Remove Apps" "Recommended"
Add-Opt "RM_MixedReality" "Remove Mixed Reality" "Removes Mixed Reality Portal if present." "Remove Apps" "Recommended"
Add-Opt "RM_People"      "Remove People" "Removes People app if present." "Remove Apps" "Recommended"
Add-Opt "RM_OneNote"     "Remove OneNote app" "Removes OneNote for Windows (store app) if present." "Remove Apps" "Minimal"
Add-Opt "RM_Tips"        "Remove Tips/Get Started" "Removes Tips app." "Remove Apps" "Recommended"

# Privacy / telemetry style toggles
Add-Opt "PR_Telemetry0" "Disable Telemetry (Policy)" "Sets AllowTelemetry=0 where supported (Enterprise/Edu most effective)." "Privacy" "Recommended"
Add-Opt "PR_AdsID"      "Disable Advertising ID" "Disables Advertising ID usage." "Privacy" "Recommended"
Add-Opt "PR_Tailored"   "Disable Tailored Experiences" "Disables tailored experiences diagnostics." "Privacy" "Recommended"
Add-Opt "PR_Feedback"   "Reduce Feedback prompts" "Turns off feedback frequency prompts." "Privacy" "Recommended"
Add-Opt "PR_Activity"   "Disable Activity History" "Disables Timeline / activity history collection." "Privacy" "Recommended"
Add-Opt "PR_Location"   "Disable Location" "Disables location services at system policy level." "Privacy" "Aggressive"

# UI / annoyances
Add-Opt "UI_WidgetsOff" "Disable Widgets" "Disables Widgets (Windows 11 taskbar widgets)." "UI / Annoyances" "Recommended"
Add-Opt "UI_ChatOff"    "Disable Chat/Teams button" "Hides Chat/Teams button on taskbar." "UI / Annoyances" "Recommended"
Add-Opt "UI_CopilotOff" "Disable Copilot" "Disables Windows Copilot (policy where supported)." "UI / Annoyances" "Recommended"
Add-Opt "UI_TipsOff"    "Disable Tips & Suggestions" "Disables Windows tips, tricks, and suggestions." "UI / Annoyances" "Recommended"
Add-Opt "UI_ConsumerOff" "Disable Consumer Features" "Disables consumer features / content delivery." "UI / Annoyances" "Recommended"
Add-Opt "UI_LockscreenAdsOff" "Disable lock screen fun facts" "Reduces lock screen suggestions/ads." "UI / Annoyances" "Recommended"

# Xbox / gaming services
Add-Opt "SV_XboxServices" "Disable Xbox services" "Disables common Xbox services (best-effort)." "Services" "Recommended"
Add-Opt "SV_GameBarOff"   "Disable Game Bar" "Disables Game Bar capture features (policy/registry)." "Services" "Recommended"

# OneDrive
Add-Opt "OD_Uninstall" "Uninstall OneDrive" "Runs OneDriveSetup /uninstall (best-effort)." "OneDrive" "Aggressive"
Add-Opt "OD_Disable"   "Disable OneDrive integration" "Disables OneDrive via policy (prevents sync client running)." "OneDrive" "Recommended"

# Edge “debloat” lite (safe policy toggles)
Add-Opt "ED_NoDesktopShortcut" "Edge: no desktop shortcut" "Prevents Edge Update from creating desktop shortcuts." "Edge" "Minimal"
Add-Opt "ED_DisableTelemetry"  "Edge: reduce telemetry/popups" "Applies a small set of Edge policy tweaks." "Edge" "Recommended"

# Misc
Add-Opt "MX_RestartExplorer" "Restart Explorer after apply" "Restarts explorer.exe so taskbar/policies refresh." "Misc" "Recommended"

# -----------------------------
# UI
# -----------------------------
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ares Debloat / Tweaks"
        Height="640" Width="980"
        Background="#f0f0f0"
        FontFamily="Segoe UI" FontSize="12"
        ResizeMode="CanResize">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="Debloat / Tweaks (CTT-style)" FontSize="18" FontWeight="Bold" Foreground="#202020"/>
      <TextBlock Text="Select what to remove/disable. Some changes may require sign-out or reboot to fully apply."
                 Margin="0,4,0,0" Foreground="#505050"/>
    </StackPanel>

    <!-- Main -->
    <Border Grid.Row="1" Background="White" BorderBrush="#c0c0c0" BorderThickness="1" Padding="10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Presets -->
        <DockPanel Grid.Row="0" Margin="0,0,0,8">
          <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
            <Button x:Name="BtnMinimal" Content="Select Minimal" Width="120" Margin="0,0,8,0" Padding="10,5"/>
            <Button x:Name="BtnRecommended" Content="Select Recommended" Width="150" Margin="0,0,8,0" Padding="10,5"/>
            <Button x:Name="BtnAggressive" Content="Select Aggressive" Width="150" Margin="0,0,8,0" Padding="10,5"/>
            <Button x:Name="BtnClear" Content="Clear" Width="90" Padding="10,5"/>
          </StackPanel>

          <TextBox x:Name="SearchBox" Width="260" Height="26" VerticalContentAlignment="Center"
                   DockPanel.Dock="Right" Margin="8,0,0,0"
                   ToolTip="Filter by name/description/category" />
        </DockPanel>

        <!-- Options List -->
        <ListView x:Name="OptList" Grid.Row="1" BorderThickness="0">
          <ListView.View>
            <GridView>
              <GridViewColumn Width="40">
                <GridViewColumn.CellTemplate>
                  <DataTemplate>
                    <CheckBox IsChecked="{Binding IsSelected}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </DataTemplate>
                </GridViewColumn.CellTemplate>
              </GridViewColumn>

              <GridViewColumn Header="Category" Width="140" DisplayMemberBinding="{Binding Category}" />
              <GridViewColumn Header="Option" Width="240" DisplayMemberBinding="{Binding Name}" />
              <GridViewColumn Header="Description" Width="430">
                <GridViewColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding Description}" TextWrapping="Wrap"/>
                  </DataTemplate>
                </GridViewColumn.CellTemplate>
              </GridViewColumn>
              <GridViewColumn Header="Status" Width="90" DisplayMemberBinding="{Binding Status}" />
            </GridView>
          </ListView.View>
        </ListView>

      </Grid>
    </Border>

    <!-- Footer -->
    <DockPanel Grid.Row="2" Margin="0,10,0,0">
      <TextBlock x:Name="StatusText" Foreground="#505050" VerticalAlignment="Center" DockPanel.Dock="Left"/>
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
        <Button x:Name="BtnApply" Content="Apply Selected" Width="140" Margin="0,0,8,0" Padding="10,5"/>
        <Button x:Name="BtnClose" Content="Close" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

function Apply-Option {
    param([Parameter(Mandatory)][string]$Id)

    switch ($Id) {

        # -------- Remove Apps --------
        "RM_Xbox" {
            Remove-AppxSafe -PackagePatterns @(
                "Microsoft.XboxApp",
                "Microsoft.XboxGamingOverlay",
                "Microsoft.XboxGameOverlay",
                "Microsoft.Xbox.TCUI",
                "Microsoft.XboxSpeechToTextOverlay",
                "Microsoft.GamingApp"
            )
        }
        "RM_Skype" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.SkypeApp")
        }
        "RM_TeamsConsumer" {
            Remove-AppxSafe -PackagePatterns @("MicrosoftTeams", "MSTeams")
        }
        "RM_Clipchamp" {
            Remove-AppxSafe -PackagePatterns @("Clipchamp.Clipchamp")
        }
        "RM_News" {
            Remove-AppxSafe -PackagePatterns @("MicrosoftWindows.Client.WebExperience", "Microsoft.BingNews")
        }
        "RM_Weather" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.BingWeather")
        }
        "RM_Solitaire" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.MicrosoftSolitaireCollection")
        }
        "RM_TiktokEtc" {
            # Common sponsored patterns (best-effort; harmless if not present)
            Remove-AppxSafe -PackagePatterns @(
                "*TikTok*",
                "*Facebook*",
                "*Spotify*",
                "*Disney*",
                "*CandyCrush*",
                "*Dolby*",
                "*Twitter*"
            )
        }
        "RM_3DViewer" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.Microsoft3DViewer", "Microsoft.Print3D")
        }
        "RM_MixedReality" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.MixedReality.Portal")
        }
        "RM_People" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.People")
        }
        "RM_OneNote" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.Office.OneNote")
        }
        "RM_Tips" {
            Remove-AppxSafe -PackagePatterns @("Microsoft.Getstarted", "Microsoft.Tips")
        }

        # -------- Privacy --------
        "PR_Telemetry0" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 0
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "MaxTelemetryAllowed" -Type DWord -Value 0
        }
        "PR_AdsID" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Type DWord -Value 1
        }
        "PR_Tailored" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableTailoredExperiencesWithDiagnosticData" -Type DWord -Value 1
        }
        "PR_Feedback" {
            Set-RegValue -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0
            Set-RegValue -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" -Type QWord -Value 0
        }
        "PR_Activity" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Type DWord -Value 0
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Type DWord -Value 0
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Type DWord -Value 0
        }
        "PR_Location" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -Type DWord -Value 1
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableWindowsLocationProvider" -Type DWord -Value 1
        }

        # -------- UI / Annoyances --------
        "UI_WidgetsOff" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Type DWord -Value 0
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Type DWord -Value 0
        }
        "UI_ChatOff" {
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Type DWord -Value 0
        }
        "UI_CopilotOff" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Type DWord -Value 1
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Type DWord -Value 0
        }
        "UI_TipsOff" {
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Type DWord -Value 0
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type DWord -Value 0
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Type DWord -Value 0
        }
        "UI_ConsumerOff" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Type DWord -Value 1
        }
        "UI_LockscreenAdsOff" {
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -Type DWord -Value 0
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -Type DWord -Value 0
        }

        # -------- Services --------
        "SV_XboxServices" {
            foreach ($svc in @("XboxGipSvc","XblAuthManager","XblGameSave","XboxNetApiSvc")) {
                Stop-ServiceSafe -Name $svc
                Disable-ServiceSafe -Name $svc
            }
        }
        "SV_GameBarOff" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Type DWord -Value 0
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Type DWord -Value 0
        }

        # -------- OneDrive --------
        "OD_Uninstall" {
            Uninstall-OneDrive
        }
        "OD_Disable" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Type DWord -Value 1
        }

        # -------- Edge --------
        "ED_NoDesktopShortcut" {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" -Name "CreateDesktopShortcutDefault" -Type DWord -Value 0
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" -Name "CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Type DWord -Value 0
        }
        "ED_DisableTelemetry" {
            # “Lite” set of sane defaults (won't break Edge)
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "MetricsReportingEnabled" -Type DWord -Value 0
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "UserFeedbackAllowed" -Type DWord -Value 0
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "ShowRecommendationsEnabled" -Type DWord -Value 0
        }

        # -------- Misc --------
        "MX_RestartExplorer" {
            Restart-Explorer
        }

        default {
            # Unknown option id - ignore
        }
    }
}

# -----------------------------
# Show UI + execute
# -----------------------------
Assert-Admin

$w = [Windows.Markup.XamlReader]::Parse($xaml)
Init-ChildWindow -Window $w

$OptList   = $w.FindName("OptList")
$StatusText = $w.FindName("StatusText")
$BtnApply  = $w.FindName("BtnApply")
$BtnClose  = $w.FindName("BtnClose")

$BtnMinimal      = $w.FindName("BtnMinimal")
$BtnRecommended  = $w.FindName("BtnRecommended")
$BtnAggressive   = $w.FindName("BtnAggressive")
$BtnClear        = $w.FindName("BtnClear")
$SearchBox       = $w.FindName("SearchBox")

$OptList.ItemsSource = $Global:DebloatOptions

# Basic filtering (no fancy collection view required)
$Global:DebloatView = New-Object System.Collections.ObjectModel.ObservableCollection[object]
function Refresh-View {
    $Global:DebloatView.Clear()
    $q = ""
    if ($SearchBox -and $SearchBox.Text) { $q = $SearchBox.Text.Trim().ToLowerInvariant() }

    foreach ($o in $Global:DebloatOptions) {
        if ([string]::IsNullOrWhiteSpace($q)) {
            $Global:DebloatView.Add($o) | Out-Null
        } else {
            $hay = ($o.Name + " " + $o.Description + " " + $o.Category).ToLowerInvariant()
            if ($hay.Contains($q)) { $Global:DebloatView.Add($o) | Out-Null }
        }
    }
    $OptList.ItemsSource = $Global:DebloatView
    $OptList.Items.Refresh()
}
Refresh-View

if ($SearchBox) {
    $SearchBox.Add_TextChanged({ Refresh-View })
}

function Select-Preset {
    param([ValidateSet("Minimal","Recommended","Aggressive","None")][string]$Preset)

    foreach ($o in $Global:DebloatOptions) {
        if ($Preset -eq "None") {
            $o.IsSelected = $false
        } elseif ($Preset -eq "Minimal") {
            $o.IsSelected = ($o.Preset -eq "Minimal")
        } elseif ($Preset -eq "Recommended") {
            $o.IsSelected = ($o.Preset -eq "Minimal" -or $o.Preset -eq "Recommended")
        } else {
            $o.IsSelected = ($o.Preset -ne "None")
        }
        $o.Status = ""
    }
    $OptList.Items.Refresh()
}

$BtnMinimal.Add_Click({ Select-Preset -Preset "Minimal" })
$BtnRecommended.Add_Click({ Select-Preset -Preset "Recommended" })
$BtnAggressive.Add_Click({ Select-Preset -Preset "Aggressive" })
$BtnClear.Add_Click({ Select-Preset -Preset "None" })

$BtnClose.Add_Click({ $w.Close() })

$BtnApply.Add_Click({
    $selected = @($Global:DebloatOptions | Where-Object { $_.IsSelected })
    if (-not $selected -or $selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No options selected.", "Info", 'OK', 'Information') | Out-Null
        return
    }

    $BtnApply.IsEnabled = $false
    if ($StatusText) { $StatusText.Text = "Applying selected options..." }

    $needsExplorerRestart = $false
    $maybeReboot = $false

    foreach ($opt in $selected) {
        $opt.Status = "Running..."
        $OptList.Items.Refresh()

        try {
            if ($opt.Id -eq "MX_RestartExplorer") { $needsExplorerRestart = $true }
            if ($opt.Id -in @("OD_Uninstall","PR_Telemetry0","UI_CopilotOff","OD_Disable")) { $maybeReboot = $true }

            Apply-Option -Id $opt.Id
            $opt.Status = "Done"
        }
        catch {
            $opt.Status = "Failed"
        }

        $OptList.Items.Refresh()
    }

    if ($StatusText) { $StatusText.Text = "Finished." }
    $BtnApply.IsEnabled = $true

    $msg = "Completed: " + $selected.Count + " option(s)."
    if ($needsExplorerRestart) { $msg += "`nExplorer was restarted (if selected)." }
    if ($maybeReboot) { $msg += "`nSome changes may require sign-out or reboot to fully apply." }

    [System.Windows.MessageBox]::Show($msg, "Done", 'OK', 'Information') | Out-Null
})

$null = $w.ShowDialog()
