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
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $type = [string]$r.Type
        $value = $r.Value

        switch -Regex ($type) {
            "DWord"  { New-ItemProperty -Path $path -Name $name -Value ([int]$value) -PropertyType DWord  -Force | Out-Null }
            "QWord"  { New-ItemProperty -Path $path -Name $name -Value ([long]$value) -PropertyType QWord  -Force | Out-Null }
            "String" { New-ItemProperty -Path $path -Name $name -Value ([string]$value) -PropertyType String -Force | Out-Null }
            default  { New-ItemProperty -Path $path -Name $name -Value ([string]$value) -PropertyType String -Force | Out-Null }
        }
    }
}

function Invoke-ScriptArray {
    param([Parameter(Mandatory=$true)]$ScriptArray)

    foreach ($s in $ScriptArray) {
        $text = [string]$s
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        & ([scriptblock]::Create($text))
    }
}

function Get-WinUtilTweaks {
    $url = "https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/config/tweaks.json"
    Get-JsonFromUrl -Url $url
}

function New-TweaksWindowXaml {
@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ares - Tweaks"
        Height="600" Width="1080"
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
      <TextBlock Text="Tweaks" FontSize="18" FontWeight="Bold" Foreground="#202020"/>
      <TextBlock Text="Pulled live from WinUtil tweaks.json. Select what you want and click Apply."
                 Foreground="#505050" Margin="0,2,0,0"/>
    </StackPanel>

    <DockPanel Grid.Row="1" Margin="0,0,0,8">
      <TextBlock Text="Category:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <ComboBox Name="CategoryBox" Width="420" Margin="0,0,10,0"/>
      <Button Name="SelectAllBtn" Content="Select All (filtered)" Width="160" Margin="0,0,8,0"/>
      <Button Name="ClearBtn" Content="Clear" Width="90"/>
      <TextBlock Name="CountText" DockPanel.Dock="Right" VerticalAlignment="Center" Foreground="#606060"/>
    </DockPanel>

    <Border Grid.Row="2" BorderBrush="#cfcfcf" BorderThickness="1" Background="White">
      <ListView Name="TweakList" BorderThickness="0">
        <ListView.View>
          <GridView>
            <GridViewColumn Width="40">
              <GridViewColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding IsSelected}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </DataTemplate>
              </GridViewColumn.CellTemplate>
            </GridViewColumn>

            <GridViewColumn Header="Category" Width="260" DisplayMemberBinding="{Binding Category}"/>
            <GridViewColumn Header="Tweak" Width="260" DisplayMemberBinding="{Binding Name}"/>
            <GridViewColumn Header="Description" Width="420">
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

# Load + flatten
$tweaks = Get-WinUtilTweaks

$rows = @()
foreach ($p in $tweaks.PSObject.Properties) {
    $k = $p.Name
    $t = $p.Value
    if ($null -eq $t) { continue }

    $rows += [pscustomobject]@{
        Key         = $k
        IsSelected  = $false
        Category    = [string]$t.category
        Name        = [string]$t.Content
        Description = [string]$t.Description
        Raw         = $t
        Status      = ""
    }
}

$rows = $rows | Where-Object { $_.Name } | Sort-Object Category, Name

$view = New-Object System.Collections.ObjectModel.ObservableCollection[object]
foreach ($r in $rows) { [void]$view.Add($r) }

$xaml = New-TweaksWindowXaml
$w = [Windows.Markup.XamlReader]::Parse($xaml)

$CategoryBox = $w.FindName("CategoryBox")
$TweakList = $w.FindName("TweakList")
$SelectAllBtn = $w.FindName("SelectAllBtn")
$ClearBtn = $w.FindName("ClearBtn")
$CountText = $w.FindName("CountText")
$StatusText = $w.FindName("StatusText")
$ApplyBtn = $w.FindName("ApplyBtn")
$CloseBtn = $w.FindName("CloseBtn")

$TweakList.ItemsSource = $view

# Categories
$cats = @("All")
$cats += ($rows | Select-Object -ExpandProperty Category -Unique | Where-Object { $_ } | Sort-Object)
$CategoryBox.ItemsSource = $cats
$CategoryBox.SelectedIndex = 0

function Refresh-Filter {
    $sel = [string]$CategoryBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($sel) -or $sel -eq "All") {
        $TweakList.ItemsSource = $view
        $CountText.Text = ("Showing: {0}" -f $view.Count)
        return
    }

    $filtered = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($row in $view) {
        if ([string]$row.Category -eq $sel) { [void]$filtered.Add($row) }
    }
    $TweakList.ItemsSource = $filtered
    $CountText.Text = ("Showing: {0}" -f $filtered.Count)
}

$CategoryBox.Add_SelectionChanged({ Refresh-Filter })

$SelectAllBtn.Add_Click({
    $src = $TweakList.ItemsSource
    foreach ($row in $src) { $row.IsSelected = $true }
    $TweakList.Items.Refresh()
})

$ClearBtn.Add_Click({
    foreach ($row in $view) { $row.IsSelected = $false; $row.Status = "" }
    $TweakList.Items.Refresh()
    $StatusText.Text = ""
})

$ApplyBtn.Add_Click({
    $ApplyBtn.IsEnabled = $false
    $StatusText.Text = "Applying selected tweaks..."

    $selected = @()
    foreach ($row in $view) { if ($row.IsSelected) { $selected += $row } }

    if (-not $selected -or $selected.Count -lt 1) {
        [System.Windows.MessageBox]::Show("No tweaks selected.", "Ares - Tweaks", "OK", "Information") | Out-Null
        $ApplyBtn.IsEnabled = $true
        $StatusText.Text = ""
        return
    }

    foreach ($row in $selected) {
        $row.Status = "Running"
        $TweakList.Items.Refresh()

        try {
            $raw = $row.Raw
            if ($raw.registry)     { Invoke-RegistryBatch -RegArray $raw.registry }
            if ($raw.InvokeScript) { Invoke-ScriptArray -ScriptArray $raw.InvokeScript }
            $row.Status = "Done"
        }
        catch {
            $row.Status = "Failed"
        }

        $TweakList.Items.Refresh()
    }

    $StatusText.Text = "Done."
    $ApplyBtn.IsEnabled = $true
})

$CloseBtn.Add_Click({ $w.Close() })

$w.Topmost = $true
$null = $w.ShowDialog()
