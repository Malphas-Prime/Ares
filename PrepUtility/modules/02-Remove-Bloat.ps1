#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-JsonFromUrl {
    param([Parameter(Mandatory=$true)][string]$Url)
    (Invoke-WebRequest -UseBasicParsing -Uri $Url -ErrorAction Stop).Content | ConvertFrom-Json
}

function Invoke-RegistryBatch {
    param([Parameter(Mandatory=$true)]$RegArray)

    foreach ($r in $RegArray) {
        $path = [string]$r.Path
        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }

        $name = [string]$r.Name
        $type = [string]$r.Type
        $value = $r.Value

        if ([string]::IsNullOrWhiteSpace($name)) {
            # Some entries are just "ensure key exists"
            continue
        }

        switch -Regex ($type) {
            "DWord"  { New-ItemProperty -Path $path -Name $name -Value ([int]$value) -PropertyType DWord  -Force | Out-Null }
            "QWord"  { New-ItemProperty -Path $path -Name $name -Value ([long]$value) -PropertyType QWord  -Force | Out-Null }
            "String" { New-ItemProperty -Path $path -Name $name -Value ([string]$value) -PropertyType String -Force | Out-Null }
            default  {
                # Fallback: try string
                New-ItemProperty -Path $path -Name $name -Value ([string]$value) -PropertyType String -Force | Out-Null
            }
        }
    }
}

function Invoke-ScriptArray {
    param([Parameter(Mandatory=$true)]$ScriptArray)

    foreach ($s in $ScriptArray) {
        $text = [string]$s
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $sb = [scriptblock]::Create($text)
        & $sb
    }
}

function Get-WinUtilTweaks {
    # Full WinUtil tweak catalog
    $url = "https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/config/tweaks.json"
    Get-JsonFromUrl -Url $url
}

function Get-DebloatCandidates {
    $tweaks = Get-WinUtilTweaks

    # Flatten object-properties into a list
    $items = @()
    foreach ($p in $tweaks.PSObject.Properties) {
        $name = $p.Name
        $t = $p.Value
        if ($null -eq $t) { continue }

        $cat = [string]$t.category
        $content = [string]$t.Content
        $desc = [string]$t.Description

        # Debloat-ish categories + common removals live in Advanced/CAUTION section in WinUtil docs
        $isDebloat =
            ($cat -match "De\s*Bloat") -or
            ($content -match "Remove\s") -or
            ($content -match "Debloat") -or
            ($content -match "Remove OneDrive") -or
            ($content -match "Remove Edge") -or
            ($content -match "Remove Copilot") -or
            ($content -match "Block Adobe") -or
            ($content -match "Debloat Adobe")

        if (-not $isDebloat) { continue }

        $items += [pscustomobject]@{
            Key         = $name
            IsSelected  = $false
            Category    = $cat
            Name        = $content
            Description = $desc
            Raw         = $t
            Status      = ""
        }
    }

    # Add our own "OO ShutUp" action row (implemented below)
    $items += [pscustomobject]@{
        Key         = "ARES_OOSU10_RECOMMENDED"
        IsSelected  = $false
        Category    = "Debloat / Privacy"
        Name        = "Apply OO ShutUp10++ (WinUtil recommended)"
        Description = "Downloads OOSU10.exe + WinUtil recommended cfg, applies silently."
        Raw         = $null
        Status      = ""
    }

    $items | Sort-Object Category, Name
}

function Invoke-OOSU10Recommended {
    $tempDir = Join-Path $env:TEMP "Ares_OOSU10"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

    $exePath = Join-Path $tempDir "OOSU10.exe"
    $cfgPath = Join-Path $tempDir "ooshutup10_recommended.cfg"

    # O&O binary download (CDN referenced by WinUtil issue thread)
    $exeUrl = "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe"
    Invoke-WebRequest -UseBasicParsing -Uri $exeUrl -OutFile $exePath -ErrorAction Stop

    # WinUtil recommended cfg
    $cfgUrl = "https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/config/ooshutup10_recommended.cfg"
    (Invoke-WebRequest -UseBasicParsing -Uri $cfgUrl -ErrorAction Stop).Content | Out-File -FilePath $cfgPath -Encoding ASCII -Force

    # Import silently (documented usage: OOSU10.exe cfg /quiet)
    & $exePath $cfgPath "/quiet" | Out-Null
}

function New-DebloatWindowXaml {
@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ares - Debloat"
        Height="560" Width="980"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResize"
        Background="#f6f6f6"
        FontFamily="Segoe UI"
        FontSize="12">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,8">
      <TextBlock Text="Debloat / Privacy" FontSize="18" FontWeight="Bold" Foreground="#202020"/>
      <TextBlock Text="Select items and click Apply. Uses WinUtil’s debloat-related actions + optional OO ShutUp10++ recommended config."
                 Foreground="#505050" Margin="0,2,0,0"/>
    </StackPanel>

    <DockPanel Grid.Row="1" Margin="0,0,0,8">
      <TextBlock Text="Category:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <ComboBox Name="CategoryBox" Width="360" Margin="0,0,10,0"/>
      <Button Name="SelectAllBtn" Content="Select All (filtered)" Width="160" Margin="0,0,8,0"/>
      <Button Name="ClearBtn" Content="Clear" Width="90"/>
      <TextBlock Name="CountText" DockPanel.Dock="Right" VerticalAlignment="Center" Foreground="#606060"/>
    </DockPanel>

    <Border Grid.Row="2" BorderBrush="#cfcfcf" BorderThickness="1" Background="White">
      <ListView Name="DebloatList" BorderThickness="0">
        <ListView.View>
          <GridView>
            <GridViewColumn Width="40">
              <GridViewColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding IsSelected}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </DataTemplate>
              </GridViewColumn.CellTemplate>
            </GridViewColumn>

            <GridViewColumn Header="Category" Width="210" DisplayMemberBinding="{Binding Category}"/>
            <GridViewColumn Header="Action" Width="260" DisplayMemberBinding="{Binding Name}"/>
            <GridViewColumn Header="Description" Width="380">
              <GridViewColumn.CellTemplate>
                <DataTemplate>
                  <TextBlock Text="{Binding Description}" TextWrapping="Wrap"/>
                </DataTemplate>
              </GridViewColumn.CellTemplate>
            </GridViewColumn>
            <GridViewColumn Header="Status" Width="80" DisplayMemberBinding="{Binding Status}"/>
          </GridView>
        </ListView.View>
      </ListView>
    </Border>

    <DockPanel Grid.Row="3" Margin="0,10,0,0">
      <TextBlock Name="StatusText" VerticalAlignment="Center" Foreground="#505050"/>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="ApplyBtn" Content="Apply Selected" Width="140" Margin="0,0,8,0" Padding="10,5"/>
        <Button Name="CloseBtn" Content="Close" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
}

# -----------------------
# UI + logic
# -----------------------
$items = Get-DebloatCandidates
$view  = New-Object System.Collections.ObjectModel.ObservableCollection[object]
foreach ($i in $items) { [void]$view.Add($i) }

$xaml = New-DebloatWindowXaml
$w = [Windows.Markup.XamlReader]::Parse($xaml)

$CategoryBox = $w.FindName("CategoryBox")
$DebloatList = $w.FindName("DebloatList")
$SelectAllBtn = $w.FindName("SelectAllBtn")
$ClearBtn = $w.FindName("ClearBtn")
$CountText = $w.FindName("CountText")
$StatusText = $w.FindName("StatusText")
$ApplyBtn = $w.FindName("ApplyBtn")
$CloseBtn = $w.FindName("CloseBtn")

$DebloatList.ItemsSource = $view

# Categories
$cats = @("All")
$cats += ($items | Select-Object -ExpandProperty Category -Unique | Where-Object { $_ } | Sort-Object)
$CategoryBox.ItemsSource = $cats
$CategoryBox.SelectedIndex = 0

function Refresh-Filter {
    $sel = [string]$CategoryBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($sel) -or $sel -eq "All") {
        $DebloatList.ItemsSource = $view
        $CountText.Text = ("Showing: {0}" -f $view.Count)
        return
    }

    $filtered = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($row in $view) {
        if ([string]$row.Category -eq $sel) { [void]$filtered.Add($row) }
    }
    $DebloatList.ItemsSource = $filtered
    $CountText.Text = ("Showing: {0}" -f $filtered.Count)
}

$CategoryBox.Add_SelectionChanged({ Refresh-Filter })

$SelectAllBtn.Add_Click({
    $src = $DebloatList.ItemsSource
    foreach ($row in $src) { $row.IsSelected = $true }
    $DebloatList.Items.Refresh()
})

$ClearBtn.Add_Click({
    foreach ($row in $view) { $row.IsSelected = $false; $row.Status = "" }
    $DebloatList.Items.Refresh()
    $StatusText.Text = ""
})

$ApplyBtn.Add_Click({
    $ApplyBtn.IsEnabled = $false
    $StatusText.Text = "Applying selected actions..."

    $selected = @()
    foreach ($row in $view) { if ($row.IsSelected) { $selected += $row } }

    if (-not $selected -or $selected.Count -lt 1) {
        [System.Windows.MessageBox]::Show("No actions selected.", "Ares - Debloat", "OK", "Information") | Out-Null
        $ApplyBtn.IsEnabled = $true
        $StatusText.Text = ""
        return
    }

    foreach ($row in $selected) {
        $row.Status = "Running"
        $DebloatList.Items.Refresh()

        try {
            if ($row.Key -eq "ARES_OOSU10_RECOMMENDED") {
                Invoke-OOSU10Recommended
            }
            else {
                $raw = $row.Raw

                if ($raw.registry)     { Invoke-RegistryBatch -RegArray $raw.registry }
                if ($raw.InvokeScript) { Invoke-ScriptArray -ScriptArray $raw.InvokeScript }
            }

            $row.Status = "Done"
        }
        catch {
            $row.Status = "Failed"
        }

        $DebloatList.Items.Refresh()
    }

    $StatusText.Text = "Done."
    $ApplyBtn.IsEnabled = $true
})

$CloseBtn.Add_Click({ $w.Close() })

# Show on top of owner (main window stays sane)
$w.Topmost = $true
$null = $w.ShowDialog()
