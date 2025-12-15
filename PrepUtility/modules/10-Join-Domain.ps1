# modules/10-Join-Domain.ps1
# Ares Prep Utility - Join Domain / Configure User (WPF guided)
# Features:
#   - Rename PC (validated) + reboot handling
#   - Add new local user
#   - Add local users / local groups / built-ins / DOMAIN\* to local Administrators
#   - Join domain (optional OU) + reboot handling
# Compatibility: Windows PowerShell 5.1

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

    # If main.ps1 sets $Global:AresMainWindow, this will keep dialogs on top of it.
    try {
        if ($Global:AresMainWindow) {
            $Window.Owner = $Global:AresMainWindow
            $Window.WindowStartupLocation = "CenterOwner"
        } else {
            $Window.WindowStartupLocation = "CenterScreen"
        }
    } catch { }

    # Ensure dialog appears above normal windows (but do NOT keep main always-topmost).
    try { $Window.Topmost = $true } catch { }
}

function Get-LocalUsers {
    $names = @()
    try {
        if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
            $names = @(Get-LocalUser | Select-Object -ExpandProperty Name)
        } else {
            $raw = & net user 2>$null
            if ($raw) {
                $start = $false
                foreach ($line in $raw) {
                    if ($line -match '---') { $start = $true; continue }
                    if (-not $start) { continue }
                    if ($line -match 'The command completed successfully') { break }
                    $parts = ($line -split '\s+') | Where-Object { $_ }
                    $names += $parts
                }
            }
        }
    } catch { }
    return @($names | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-LocalGroups {
    $names = @()
    try {
        if (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue) {
            $names = @(Get-LocalGroup | Select-Object -ExpandProperty Name)
        } else {
            $raw = & net localgroup 2>$null
            if ($raw) {
                $start = $false
                foreach ($line in $raw) {
                    if ($line -match '---') { $start = $true; continue }
                    if (-not $start) { continue }
                    if ($line -match 'The command completed successfully') { break }
                    $name = $line.Trim()
                    if ($name) { $names += $name }
                }
            }
        }
    } catch { }
    return @($names | Where-Object { $_ } | Sort-Object -Unique)
}

function Validate-ComputerName {
    param([Parameter(Mandatory)][string]$Name)

    $n = $Name.Trim()

    if ([string]::IsNullOrWhiteSpace($n)) { return "Computer name is required." }
    if ($n.Length -gt 15) { return "Computer name must be 15 characters or fewer." }
    if ($n -match '[^A-Za-z0-9-]') { return "Only letters, numbers, and hyphen are allowed." }
    if ($n.StartsWith("-") -or $n.EndsWith("-")) { return "Name cannot start or end with a hyphen." }
    if ($n -match '^\d+$') { return "Name cannot be all numbers." }

    return $null
}

function New-LocalUserSafe {
    param(
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][securestring]$Password,
        [string]$FullName = "",
        [switch]$PasswordNeverExpires
    )

    if (-not (Get-Command New-LocalUser -ErrorAction SilentlyContinue)) {
        throw "New-LocalUser cmdlet not available on this system."
    }

    $existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($existing) {
        throw "Local user '$UserName' already exists."
    }

    $params = @{
        Name     = $UserName
        Password = $Password
    }
    if ($FullName) { $params["FullName"] = $FullName }

    $u = New-LocalUser @params
    if ($PasswordNeverExpires) {
        try { Set-LocalUser -Name $UserName -PasswordNeverExpires $true | Out-Null } catch { }
    }
    return $u
}

function Add-ToLocalAdmins {
    param([Parameter(Mandatory)][string[]]$Members)

    foreach ($m in $Members) {
        if ([string]::IsNullOrWhiteSpace($m)) { continue }
        $mem = $m.Trim()
        try {
            Add-LocalGroupMember -Group "Administrators" -Member $mem -ErrorAction Stop
        } catch {
            # ignore duplicates / lookup oddities
        }
    }
}

function Join-DomainSafe {
    param(
        [Parameter(Mandatory)][string]$DomainName,
        [string]$OUPath = "",
        [Parameter(Mandatory)][pscredential]$Credential
    )

    $addParams = @{
        DomainName  = $DomainName
        Credential  = $Credential
        ErrorAction = "Stop"
        Force       = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($OUPath)) { $addParams["OUPath"] = $OUPath }

    Add-Computer @addParams
}

# ----------------------------
# UI windows (return values via $w.Tag)
# ----------------------------
function Show-SelectionWindow {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Join Domain / Configure User"
        Height="320" Width="460"
        Background="#f0f0f0"
        FontFamily="Segoe UI" FontSize="12"
        ResizeMode="NoResize">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="Select actions to perform" FontSize="16" FontWeight="Bold" Foreground="#202020"/>
      <TextBlock Text="You’ll be prompted for details on the next screens." Margin="0,4,0,0" Foreground="#505050"/>
    </StackPanel>

    <Border Grid.Row="1" Background="White" BorderBrush="#c0c0c0" BorderThickness="1" Padding="10">
      <StackPanel>
        <CheckBox x:Name="RenamePc" Content="Rename PC" Margin="0,0,0,6"/>
        <CheckBox x:Name="AddUser" Content="Add new user" Margin="0,0,0,6"/>
        <CheckBox x:Name="AddAdmin" Content="Add user/group to Administrators group" Margin="0,0,0,6"/>
        <CheckBox x:Name="JoinDomain" Content="Join domain" Margin="0,0,0,6"/>
      </StackPanel>
    </Border>

    <DockPanel Grid.Row="2" Margin="0,10,0,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
        <Button x:Name="NextBtn" Content="Next" Width="90" Padding="10,5" Margin="0,0,8,0"/>
        <Button x:Name="CancelBtn" Content="Cancel" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    Init-ChildWindow -Window $w

    $renamePc = $w.FindName("RenamePc")
    $addUser  = $w.FindName("AddUser")
    $addAdmin = $w.FindName("AddAdmin")
    $joinDom  = $w.FindName("JoinDomain")
    $next     = $w.FindName("NextBtn")
    $cancel   = $w.FindName("CancelBtn")

    $cancel.Add_Click({ $w.Tag = $null; $w.Close() })
    $next.Add_Click({
        $w.Tag = [pscustomobject]@{
            RenamePc = [bool]$renamePc.IsChecked
            AddUser  = [bool]$addUser.IsChecked
            AddAdmin = [bool]$addAdmin.IsChecked
            JoinDom  = [bool]$joinDom.IsChecked
        }
        $w.Close()
    })

    $null = $w.ShowDialog()
    return $w.Tag
}

function Show-RenamePcWindow {
    $current = $env:COMPUTERNAME

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Rename PC"
        Height="230" Width="520"
        Background="#f0f0f0"
        FontFamily="Segoe UI" FontSize="12"
        ResizeMode="NoResize">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="Rename this computer" FontSize="16" FontWeight="Bold" Foreground="#202020"/>
      <TextBlock x:Name="CurrentNameText" Text="Current: -" Margin="0,4,0,0" Foreground="#505050"/>
    </StackPanel>

    <Border Grid.Row="1" Background="White" BorderBrush="#c0c0c0" BorderThickness="1" Padding="10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="150"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="New computer name:" VerticalAlignment="Center"/>
        <TextBox  Grid.Row="0" Grid.Column="1" x:Name="NameBox" Margin="0,2,0,6"/>
        <TextBlock Grid.Row="1" Grid.Column="1"
                   Text="Rules: &lt;= 15 chars, letters/numbers/hyphen; not all numbers"
                   Foreground="#505050"/>
      </Grid>
    </Border>

    <DockPanel Grid.Row="2" Margin="0,10,0,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
        <Button x:Name="OkBtn" Content="Continue" Width="90" Padding="10,5" Margin="0,0,8,0"/>
        <Button x:Name="CancelBtn" Content="Cancel" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    Init-ChildWindow -Window $w

    $cur = $w.FindName("CurrentNameText")
    $box = $w.FindName("NameBox")
    $ok  = $w.FindName("OkBtn")
    $cancel = $w.FindName("CancelBtn")

    if (-not $cur -or -not $box -or -not $ok -or -not $cancel) {
        throw ("Rename PC UI is missing a named control. " +
               "CurrentNameText=" + [bool]$cur + ", NameBox=" + [bool]$box +
               ", OkBtn=" + [bool]$ok + ", CancelBtn=" + [bool]$cancel)
    }

    $cur.Text = ("Current: " + $current)
    $box.Text = $current

    $cancel.Add_Click({ $w.Tag = $null; $w.Close() })
    $ok.Add_Click({
        $err = Validate-ComputerName -Name $box.Text
        if ($err) {
            [System.Windows.MessageBox]::Show($err, "Validation", 'OK', 'Warning') | Out-Null
            return
        }

        $newName = $box.Text.Trim()
        if ($newName -ieq $current) {
            [System.Windows.MessageBox]::Show("New name is the same as current.", "Validation", 'OK', 'Information') | Out-Null
            return
        }

        $w.Tag = [pscustomobject]@{ NewName = $newName }
        $w.Close()
    })

    $null = $w.ShowDialog()
    return $w.Tag
}

function Show-AddUserWindow {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Add New Local User"
        Height="310" Width="520"
        Background="#f0f0f0"
        FontFamily="Segoe UI" FontSize="12"
        ResizeMode="NoResize">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Text="Create a local user"
               FontSize="16" FontWeight="Bold" Foreground="#202020" Margin="0,0,0,10"/>

    <Border Grid.Row="1" Background="White" BorderBrush="#c0c0c0" BorderThickness="1" Padding="10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="160"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Username:" VerticalAlignment="Center"/>
        <TextBox  Grid.Row="0" Grid.Column="1" x:Name="UserNameBox" Margin="0,2,0,8"/>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Full name (optional):" VerticalAlignment="Center"/>
        <TextBox  Grid.Row="1" Grid.Column="1" x:Name="FullNameBox" Margin="0,2,0,8"/>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Password:" VerticalAlignment="Center"/>
        <PasswordBox Grid.Row="2" Grid.Column="1" x:Name="PwdBox" Margin="0,2,0,8"/>

        <CheckBox Grid.Row="3" Grid.Column="1" x:Name="NeverExpire" Content="Password never expires"/>
      </Grid>
    </Border>

    <DockPanel Grid.Row="2" Margin="0,10,0,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
        <Button x:Name="OkBtn" Content="Create" Width="90" Padding="10,5" Margin="0,0,8,0"/>
        <Button x:Name="CancelBtn" Content="Cancel" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    Init-ChildWindow -Window $w

    $u = $w.FindName("UserNameBox")
    $f = $w.FindName("FullNameBox")
    $p = $w.FindName("PwdBox")
    $n = $w.FindName("NeverExpire")
    $ok = $w.FindName("OkBtn")
    $cancel = $w.FindName("CancelBtn")

    $cancel.Add_Click({ $w.Tag = $null; $w.Close() })
    $ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($u.Text)) {
            [System.Windows.MessageBox]::Show("Username is required.", "Validation", 'OK', 'Warning') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($p.Password)) {
            [System.Windows.MessageBox]::Show("Password is required.", "Validation", 'OK', 'Warning') | Out-Null
            return
        }

        $w.Tag = [pscustomobject]@{
            UserName     = $u.Text.Trim()
            FullName     = $f.Text
            Password     = (ConvertTo-SecureString $p.Password -AsPlainText -Force)
            NeverExpires = [bool]$n.IsChecked
        }
        $w.Close()
    })

    $null = $w.ShowDialog()
    return $w.Tag
}

function Show-AddAdminsWindow {
    $localUsers  = Get-LocalUsers
    $localGroups = Get-LocalGroups

    $listItems = New-Object System.Collections.ObjectModel.ObservableCollection[object]

    foreach ($b in @("Administrator", "Guest", "DefaultAccount")) {
        if ($localUsers -contains $b) {
            $listItems.Add([pscustomobject]@{ IsSelected=$false; Type="Built-in"; Name=$b }) | Out-Null
        }
    }

    foreach ($u in $localUsers) {
        if ($u -in @("Administrator","Guest","DefaultAccount")) { continue }
        $listItems.Add([pscustomobject]@{ IsSelected=$false; Type="User"; Name=$u }) | Out-Null
    }

    foreach ($g in $localGroups) {
        if ($g -eq "Administrators") { continue }
        $listItems.Add([pscustomobject]@{ IsSelected=$false; Type="Group"; Name=$g }) | Out-Null
    }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Add to Administrators"
        Height="520" Width="720"
        Background="#f0f0f0"
        FontFamily="Segoe UI" FontSize="12"
        ResizeMode="NoResize">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="Add users/groups to the local Administrators group" FontSize="16" FontWeight="Bold" Foreground="#202020"/>
      <TextBlock Text="Select local users, local groups, built-ins, and/or add DOMAIN\User or DOMAIN\Group." Margin="0,4,0,0" Foreground="#505050"/>
    </StackPanel>

    <Border Grid.Row="1" Background="White" BorderBrush="#c0c0c0" BorderThickness="1" Padding="10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <ListView x:Name="MemberList" Grid.Row="0" Margin="0,0,0,8">
          <ListView.View>
            <GridView>
              <GridViewColumn Width="40">
                <GridViewColumn.CellTemplate>
                  <DataTemplate>
                    <CheckBox IsChecked="{Binding IsSelected}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </DataTemplate>
                </GridViewColumn.CellTemplate>
              </GridViewColumn>
              <GridViewColumn Header="Type" Width="90" DisplayMemberBinding="{Binding Type}"/>
              <GridViewColumn Header="Local Principal" Width="520" DisplayMemberBinding="{Binding Name}"/>
            </GridView>
          </ListView.View>
        </ListView>

        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="Add DOMAIN\User or DOMAIN\Group:" VerticalAlignment="Center" Width="210"/>
          <TextBox x:Name="DomainMemberBox" Width="390" Margin="0,0,8,0"/>
          <Button x:Name="AddDomainMemberBtn" Content="Add" Width="60"/>
        </StackPanel>

        <ListBox Grid.Row="2" x:Name="ExtraMembers" Height="90"/>
      </Grid>
    </Border>

    <DockPanel Grid.Row="2" Margin="0,10,0,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
        <Button x:Name="OkBtn" Content="Submit" Width="90" Padding="10,5" Margin="0,0,8,0"/>
        <Button x:Name="CancelBtn" Content="Cancel" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    Init-ChildWindow -Window $w

    $list   = $w.FindName("MemberList")
    $box    = $w.FindName("DomainMemberBox")
    $add    = $w.FindName("AddDomainMemberBtn")
    $extra  = $w.FindName("ExtraMembers")
    $ok     = $w.FindName("OkBtn")
    $cancel = $w.FindName("CancelBtn")

    $list.ItemsSource = $listItems

    $extraMembers = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    $extra.ItemsSource = $extraMembers

    $add.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($box.Text)) {
            $extraMembers.Add($box.Text.Trim()) | Out-Null
            $box.Text = ""
        }
    })

    $cancel.Add_Click({ $w.Tag = $null; $w.Close() })
    $ok.Add_Click({
        $selectedLocal = @($listItems | Where-Object { $_.IsSelected } | Select-Object -ExpandProperty Name)
        $selectedExtra = @($extraMembers | ForEach-Object { $_.ToString() })

        if (($selectedLocal.Count + $selectedExtra.Count) -eq 0) {
            [System.Windows.MessageBox]::Show("Select at least one member to add.", "Validation", 'OK', 'Warning') | Out-Null
            return
        }

        $w.Tag = [pscustomobject]@{ Members = @($selectedLocal + $selectedExtra) }
        $w.Close()
    })

    $null = $w.ShowDialog()
    return $w.Tag
}

function Show-JoinDomainWindow {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Join Domain"
        Height="360" Width="560"
        Background="#f0f0f0"
        FontFamily="Segoe UI" FontSize="12"
        ResizeMode="NoResize">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Text="Join this computer to a domain" FontSize="16" FontWeight="Bold" Foreground="#202020" Margin="0,0,0,10"/>

    <Border Grid.Row="1" Background="White" BorderBrush="#c0c0c0" BorderThickness="1" Padding="10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="170"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Domain (FQDN):" VerticalAlignment="Center"/>
        <TextBox  Grid.Row="0" Grid.Column="1" x:Name="DomainBox" Margin="0,2,0,8"/>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="OU Path (optional):" VerticalAlignment="Center"/>
        <TextBox  Grid.Row="1" Grid.Column="1" x:Name="OUBox" Margin="0,2,0,8"/>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Domain username:" VerticalAlignment="Center"/>
        <TextBox  Grid.Row="2" Grid.Column="1" x:Name="UserBox" Margin="0,2,0,8" />

        <TextBlock Grid.Row="3" Grid.Column="0" Text="Domain password:" VerticalAlignment="Center"/>
        <PasswordBox Grid.Row="3" Grid.Column="1" x:Name="PwdBox" Margin="0,2,0,0"/>
      </Grid>
    </Border>

    <DockPanel Grid.Row="2" Margin="0,10,0,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
        <Button x:Name="OkBtn" Content="Join" Width="90" Padding="10,5" Margin="0,0,8,0"/>
        <Button x:Name="CancelBtn" Content="Cancel" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    Init-ChildWindow -Window $w

    $d = $w.FindName("DomainBox")
    $o = $w.FindName("OUBox")
    $u = $w.FindName("UserBox")
    $p = $w.FindName("PwdBox")
    $ok = $w.FindName("OkBtn")
    $cancel = $w.FindName("CancelBtn")

    $cancel.Add_Click({ $w.Tag = $null; $w.Close() })
    $ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($d.Text)) {
            [System.Windows.MessageBox]::Show("Domain is required.", "Validation", 'OK', 'Warning') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($u.Text)) {
            [System.Windows.MessageBox]::Show("Domain username is required.", "Validation", 'OK', 'Warning') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($p.Password)) {
            [System.Windows.MessageBox]::Show("Domain password is required.", "Validation", 'OK', 'Warning') | Out-Null
            return
        }

        $sec  = ConvertTo-SecureString $p.Password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($u.Text.Trim(), $sec)

        $w.Tag = [pscustomobject]@{
            Domain     = $d.Text.Trim()
            OUPath     = $o.Text
            Credential = $cred
        }
        $w.Close()
    })

    $null = $w.ShowDialog()
    return $w.Tag
}

# ----------------------------
# Main flow
# ----------------------------
Assert-Admin

$sel = Show-SelectionWindow
if (-not $sel) { return }

if ((-not $sel.RenamePc) -and (-not $sel.AddUser) -and (-not $sel.AddAdmin) -and (-not $sel.JoinDom)) {
    [System.Windows.MessageBox]::Show("No actions selected.", "Info", 'OK', 'Information') | Out-Null
    return
}

$renameInfo  = $null
$newUserInfo = $null
$adminInfo   = $null
$domainInfo  = $null

if ($sel.RenamePc) {
    $renameInfo = Show-RenamePcWindow
    if (-not $renameInfo) { return }
}

if ($sel.AddUser) {
    $newUserInfo = Show-AddUserWindow
    if (-not $newUserInfo) { return }
}

if ($sel.AddAdmin) {
    $adminInfo = Show-AddAdminsWindow
    if (-not $adminInfo) { return }
}

if ($sel.JoinDom) {
    $domainInfo = Show-JoinDomainWindow
    if (-not $domainInfo) { return }
}

$summary = New-Object System.Collections.Generic.List[string]
$needsReboot = $false

try {
    if ($renameInfo) {
        Rename-Computer -NewName $renameInfo.NewName -Force -ErrorAction Stop
        $summary.Add("Renamed computer to: $($renameInfo.NewName)")
        $needsReboot = $true
    }

    if ($newUserInfo) {
        $null = New-LocalUserSafe -UserName $newUserInfo.UserName -Password $newUserInfo.Password -FullName $newUserInfo.FullName -PasswordNeverExpires:($newUserInfo.NeverExpires)
        $summary.Add("Created local user: $($newUserInfo.UserName)")
    }

    if ($adminInfo) {
        Add-ToLocalAdmins -Members $adminInfo.Members
        $summary.Add("Added to Administrators: " + ($adminInfo.Members -join ", "))
    }

    if ($domainInfo) {
        Join-DomainSafe -DomainName $domainInfo.Domain -OUPath $domainInfo.OUPath -Credential $domainInfo.Credential
        $summary.Add("Domain join initiated: $($domainInfo.Domain)")
        $needsReboot = $true
    }

    $msg = "Completed:`n`n" + ($summary -join "`n")
    if ($needsReboot) { $msg += "`n`nA reboot is required to apply changes." }

    [System.Windows.MessageBox]::Show($msg, "Done", 'OK', 'Information') | Out-Null

    if ($needsReboot) {
        $r = [System.Windows.MessageBox]::Show("Reboot now?", "Restart Required", 'YesNo', 'Question')
        if ($r -eq 'Yes') { Restart-Computer -Force }
    }
}
catch {
    [System.Windows.MessageBox]::Show(("Failed:`n" + $_.Exception.Message), "Error", 'OK', 'Error') | Out-Null
    throw
}
