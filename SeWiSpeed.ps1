#requires -Version 3
param($Work)

# restart PowerShell with -noexit, the same script, and 1
if ((!$Work) -and ($host.name -eq 'ConsoleHost')) 
{
    powershell.exe -noexit -file $MyInvocation.MyCommand.Path 1 -windowstyle hidden
    return
}

# Set Variables
$SyncHash = [hashtable]::Synchronized(@{})
$SyncHash.Host = $host
$SyncHash.IperfFolder = $PSScriptRoot + '\Bin'

# UI Runspace
$UiRunspace = [runspacefactory]::CreateRunspace()
$UiRunspace.ApartmentState = 'STA'
$UiRunspace.ThreadOptions = 'ReuseThread'
$UiRunspace.Open()
$UiRunspace.SessionStateProxy.SetVariable('syncHash',$SyncHash)

# UI Script
$UiPowerShell = [PowerShell]::Create().AddScript(
    {
        
        function Write-Status
        {
        [CmdletBinding()]
            param
            (
                [Parameter(Mandatory=$true, Position=0)]
                [String]$Text,
                
                [Parameter(Mandatory=$true, Position=1)]
                [String]$Colore
            )
            $syncHash.Form.Dispatcher.invoke([action]{
                    if (![string]::IsNullOrWhitespace([System.Windows.Documents.TextRange]::new($SyncHash.IperfJobOutputTextBox.Document.ContentStart, $SyncHash.IperfJobOutputTextBox.Document.ContentEnd).Text))
                    {
                        $SyncHash.IperfJobOutputTextBox.AppendText("`r")
                    }
                    
                    $TextRange = [System.Windows.Documents.TextRange]::new($SyncHash.IperfJobOutputTextBox.Document.ContentEnd, $SyncHash.IperfJobOutputTextBox.Document.ContentEnd)
                    $TextRange.Text = $Text
                    $TextRange.ApplyPropertyValue([System.Windows.Documents.TextElement]::ForegroundProperty, [System.Windows.Media.Brushes]::$Colore)
                    $SyncHash.IperfJobOutputTextBox.ScrollToEnd()
            })
        }

        function Start-Iperf
        {
		Stop-Analyzer
		
            if ($SyncHash.IperfJobMonitorRunspace.RunspaceStateInfo.State -eq 'Opened')
            {
                Write-Status -Text 'SeWiSpeed ist bereits gestartet!' -Colore 'Orange'
            }
            else
            {
                # Iperf Job Monitor with Register-ObjectEvent in Runspace
                $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'Stop-Iperf', (Get-Content Function:\Stop-Iperf)))
                $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'Write-Status', (Get-Content Function:\Write-Status)))
                $SyncHash.IperfJobMonitorRunspace = [runspacefactory]::CreateRunspace($InitialSessionState)
                $SyncHash.IperfJobMonitorRunspace.ApartmentState = 'STA'
                $SyncHash.IperfJobMonitorRunspace.ThreadOptions = 'ReuseThread'
                $SyncHash.IperfJobMonitorRunspace.Open()
                $SyncHash.IperfJobMonitorRunspace.SessionStateProxy.SetVariable('syncHash',$SyncHash)
                $SyncHash.IperfJobMonitorRunspace.SessionStateProxy.SetVariable('CsvFilePath',$SyncHash.CsvFilePathTextBox.Text)
                $SyncHash.IperfJobMonitorRunspace.SessionStateProxy.SetVariable('Command',$SyncHash.CommandTextBox.Text)
                $SyncHash.IperfJobMonitorRunspace.SessionStateProxy.SetVariable('IperfVersion',$IperfVersion)
                $SyncHash.IperfJobMonitorRunspace.SessionStateProxy.SetVariable('IperfExe',$IperfExe)
				$SyncHash.IperfJobMonitorPowerShell = [PowerShell]::Create().AddScript(
                    {
                        Set-Location -Path $SyncHash.IperfFolder

					try
                        {
                            $ErrorActionPreferenceOrg = $ErrorActionPreference
                            if ($IperfVersion -eq 2)
                            {
                                'Time,localIp,localPort,RemoteIp,RemotePort,Id,Interval,Transfer,Bandwidth' | Out-File -FilePath $CsvFilePath
                                Write-Status -Text ((Invoke-Expression -Command "$IperfExe -v") 2>&1) -Colore 'Blue'
                                $ErrorActionPreference = 'stop'
                                Invoke-Expression -Command $Command | Out-File -FilePath $CsvFilePath -Append
                            }
                            else
                            {
                                Set-Content -Path $CsvFilePath -Value $null
                                
								Invoke-Expression -Command $Command

                                if ($ErrorOut = Get-Content -Tail 5 -Path $CsvFilePath | Select-String -Pattern 'iperf3: error')
                                {
                                    Write-Error -Message $ErrorOut -ErrorAction Stop
                                }
                            }
                        }
                        catch
                        {
                            Write-Status -Text $_ -Colore 'Red'
							Stop-Analyzer
                            Stop-Iperf
                        }
                        $ErrorActionPreference = $ErrorActionPreferenceOrg
                        Write-Status -Text 'SeWiSpeed erfolgreich beendet' -Colore 'Green'
						Stop-Analyzer
                        Stop-Iperf
                        
						})
					
			
            if (!(Test-Path -Path $SyncHash.CsvFilePathTextBox.Text))
            {
                Write-Status -Text 'CSV nicht gefunden. Bitte nochmal auf Start klicken' -Colore 'Red'
            }
            elseif ($SyncHash.AnalyzerRunspace.RunspaceStateInfo.State -eq 'Opened')
            {
            }
            else
            {
			Write-Status -Text 'SeWiSpeed gestartet' -Colore 'Green'
					# Analyzer Runspace
                $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'Stop-Analyzer', (Get-Content Function:\Stop-Analyzer)))
                $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'Write-Status', (Get-Content Function:\Write-Status)))
                $SyncHash.AnalyzerRunspace = [runspacefactory]::CreateRunspace($InitialSessionState)
                $SyncHash.AnalyzerRunspace.ApartmentState = 'STA'
                $SyncHash.AnalyzerRunspace.ThreadOptions = 'ReuseThread'
                $SyncHash.AnalyzerRunspace.Open()
                $SyncHash.AnalyzerRunspace.SessionStateProxy.SetVariable('syncHash',$SyncHash)
                $SyncHash.AnalyzerRunspace.SessionStateProxy.SetVariable('CsvFilePath',$SyncHash.CsvFilePathTextBox.Text)
                $SyncHash.AnalyzerRunspace.SessionStateProxy.SetVariable('LastX',$SyncHash.LastXTextBox.Text)
                $SyncHash.AnalyzerRunspace.SessionStateProxy.SetVariable('IperfVersion',$IperfVersion)
                $SyncHash.AnalyzerPowerShell = [powershell]::Create()
                $SyncHash.AnalyzerPowerShell.Runspace = $SyncHash.AnalyzerRunspace
                $null = $SyncHash.AnalyzerPowerShell.AddScript($AnalyzerScript)
                $SyncHash.AnalyzerHandle = $SyncHash.AnalyzerPowerShell.BeginInvoke()
			}		
					
                $SyncHash.IperfJobMonitorPowerShell.Runspace = $SyncHash.IperfJobMonitorRunspace
                $SyncHash.IperfJobMonitorHandle = $SyncHash.IperfJobMonitorPowerShell.BeginInvoke()
            }
        }

        function Stop-Iperf
        {
			Write-Status -Text 'SeWiSpeed gestoppt!' -Colore 'Red'
			Stop-Analyzer
			
			if ($SyncHash.AnalyzerRunspace.RunspaceStateInfo.State -eq 'Opened')
            {
                $SyncHash.AnalyzerRunspace.Close()
                $SyncHash.AnalyzerPowerShell.Dispose()
            }
			
            if ($SyncHash.IperfJobMonitorRunspace.RunspaceStateInfo.State -eq 'Opened')
            {
                $SyncHash.IperfJobMonitorRunspace.Close()
                $SyncHash.IperfJobMonitorPowerShell.Dispose()
            }			           
        }

		
        # Analyzer Runspace Script
        $AnalyzerScript = 
        {
            
            $First  = $true
            $Header = $null
            $AnalyzerDataLength = 0

            $ChartDataAction0 = [Action]{
                $SyncHash.Chart.Series['Bandbreite (Mbits/sek)'].Points.Clear()
                $SyncHash.Chart.Series['Transfer (MBytes)'].Points.Clear()
            }
            $SyncHash.Chart.Invoke($ChartDataAction0)

            Get-Content -Path $CsvFilePath -ReadCount 0 -Wait | ForEach-Object {
                trap {$SyncHash.host.ui.WriteErrorLine("$_`nError was in Line {0}`n{1}" -f ($_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line))}
                $AnalyzerData = New-Object -TypeName System.Collections.Generic.List[System.Object]

                if ($IperfVersion -eq 2)
                {
                    foreach ($Line in $_)
                    {
                        if ($Line -like '*Bandwidth*')
                        {
                            $Header = $Line -split ','
                        }
                        else
                        {
                            if ($First -and !$Header)
                            {
                                Write-Status -Text 'CSV Error' -Colore 'Red'
                                Stop-Analyzer
                            }
                            else
                            {
                                $First = $false
                            }

                            $CsvLine = $Line | ConvertFrom-Csv -Header $Header
                            $CsvLine.Bandwidth = $CsvLine.Bandwidth /1Mb
                            $CsvLine.Transfer = $CsvLine.Transfer /1Mb
                            if (!($CsvLine.Interval).StartsWith('0.0-') -or ($CsvLine.Interval -eq '0.0-1.0'))
                            {
                                $AnalyzerData.add($CsvLine)
                            }   
                            else  
                            {
                            }
                        }
                    }
                }
                else
                {
                    $Csv = $_ | Where-Object {$_ -match '\[...\]'}
					
                    foreach ($Line in $Csv)
                    {
                        $Line = $Line -replace '[][]'
                        if ($Line -like ' ID *')
                        {
                            $Header = ($Line = $Line -replace 'Total Datagram','Total-Datagram' -replace 'Lost/Total Datagrams','Lost/Total-Datagrams') -split '\s+' | Where-Object {$_}
                            $HeaderIndex = @()
                            foreach ($Head in $Header)
                            {
                                $HeaderIndex += $Line.IndexOf($Head)
                            }
                        }
                        elseif ($Header -and $Line -notlike '*connected to*' -and $Line -notlike '*sender*' -and $Line -notlike '*receiver*' -and $Line -cnotlike '*datagrams*')
                        {
                            $i=0
                            $CsvLine = New-Object System.Object
                            foreach ($Head in $Header)
                            {
                                if ($i -lt $HeaderIndex.Length-1)
                                {
                                    $Cell = $Line.Substring($HeaderIndex[$i],$HeaderIndex[$i + 1] - $HeaderIndex[$i])
                                }
                                else
                                {
                                    $Cell = $Line.Substring($HeaderIndex[$i])
                                }

                                if ($Head -eq 'Transfer')
                                {
                                    $TransferData = $Cell.Trim() -split '\s+'
                                    if ($TransferData[1] -eq 'KBytes')
                                    {
                                        $Cell = $TransferData[0] /1kb
                                    }
                                    elseif ($TransferData[1] -eq 'GBytes')
                                    {
                                        $Cell = $TransferData[0] *1kb
                                    }
                                }

                                $i++
                                Add-Member -InputObject $CsvLine -NotePropertyName $Head -NotePropertyValue ("$Cell".Trim() -split '\s+')[0]
                            }
                            $AnalyzerData.add($CsvLine)
                        }
                    }
                }

                if ($AnalyzerData.Count -gt $LastX -and $LastX -gt 0)
                {
                    $AnalyzerData = $AnalyzerData.GetRange($AnalyzerData.Count - $LastX, $LastX)
                }
                $SyncHash.host.ui.WriteVerboseLine('New Points: ' + $AnalyzerData.Count)

                if ($AnalyzerData.Count -gt 0)
                {
                    if ($AnalyzerDataLength -eq 0 -and $AnalyzerData.Count -gt 1)
                    {
                        $ChartDataAction1 = [Action]{
                            $SyncHash.Chart.Series['Bandbreite (MBit/s)'].Points.DataBindXY($AnalyzerData.Interval, $AnalyzerData.Bandwidth)
                            $SyncHash.Chart.Series['Transfer (MBytes)'].Points.DataBindXY($AnalyzerData.Interval, $AnalyzerData.Transfer)
                        }
                        $SyncHash.Chart.Invoke($ChartDataAction1)
                    }
                    else
                    {
                        $ChartDataAction2 = [Action]{
                            while ($AnalyzerDataLength + $AnalyzerData.Count -gt $LastX -and $LastX -gt 0)
                            {
                                $SyncHash.Chart.Series['Bandbreite (MBit/s)'].Points.RemoveAt(0)
                                $SyncHash.Chart.Series['Transfer (MBytes)'].Points.RemoveAt(0)
                                $Global:AnalyzerDataLength --
                            }
                            foreach ($Point in $AnalyzerData)
                            {
                                $SyncHash.Chart.Series['Bandbreite (MBit/s)'].Points.AddXY($Point.Interval, $Point.Bandwidth)
								$SyncHash.label1.Text = $Point.Bandwidth
                                $SyncHash.Chart.Series['Transfer (MBytes)'].Points.AddXY($Point.Interval, $Point.Transfer)
                            }
                        }
                        $SyncHash.Chart.Invoke($ChartDataAction2)
                    }
                    $AnalyzerDataLength += $AnalyzerData.Count
					 
					
                }
                else
                {
                }
            }
        }

        function Stop-Analyzer
        {
            if ($SyncHash.IperfJobMonitorRunspace.RunspaceStateInfo.State -eq 'Opened')
            {
                $SyncHash.IperfJobMonitorRunspace.Close()
                $SyncHash.IperfJobMonitorPowerShell.Dispose()
            }
        }

        function Set-IperfCommand
        {
            if ($SyncHash.ClientRadio.IsChecked)
            {
				if ($SyncHash.Server1Radio.IsChecked)
			{
			$SyncHash.IpTextBox.Text = '91.194.84.95'
			$IperfMode = ' -R -w 8192k -c ' + $SyncHash.IpTextBox.Text
                $SyncHash.IpTextBox.IsEnabled = $false
                $IperfTime = ' -t ' + $SyncHash.TimeTextBox.Text
                $SyncHash.TimeTextBox.IsEnabled = $true
			}
			else
			{
			$SyncHash.IpTextBox.Text = '89.163.131.173'
                $IperfMode = ' -R -w 8192k -c ' + $SyncHash.IpTextBox.Text
                $SyncHash.IpTextBox.IsEnabled = $false
                $IperfTime = ' -t ' + $SyncHash.TimeTextBox.Text
                $SyncHash.TimeTextBox.IsEnabled = $true
            }
			}
            else
            {
			
			
			if ($SyncHash.Server1Radio.IsChecked)
			{
			$SyncHash.IpTextBox.Text = '91.194.84.95'
			$IperfMode = ' -c ' + $SyncHash.IpTextBox.Text
                $SyncHash.IpTextBox.IsEnabled = $false
                $IperfTime = ' -t ' + $SyncHash.TimeTextBox.Text
                $SyncHash.TimeTextBox.IsEnabled = $true
			}
			else
			{
			$SyncHash.IpTextBox.Text = '89.163.131.173'
                $IperfMode = ' -c ' + $SyncHash.IpTextBox.Text
                $SyncHash.IpTextBox.IsEnabled = $false
                $IperfTime = ' -t ' + $SyncHash.TimeTextBox.Text
                $SyncHash.TimeTextBox.IsEnabled = $true
            }
			
            }
			
			
            if ($SyncHash.Version2Radio.IsChecked)
            {
                $IperfVersionParams = ' -y c'
                $Global:IperfVersion = 2
                $Global:IperfExe = '.\Bin\iperf.exe'
            }
            else
            {
                $IperfVersionParams = ' -b 1000M -f m --logfile ' + $SyncHash.CsvFilePathTextBox.Text
                $Global:IperfVersion = 3
                $Global:IperfExe = '.\Bin\iperf3.exe'
            }
			
			

            $SyncHash.CommandTextBox.Text = $IperfExe + $IperfMode + $IperfTime + $IperfVersionParams + ' -i 1'
        }

		
		
        # UI
        $InputXml = @"
<Window x:Class="SeWiSpeed.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:SeWiSpeed"
        xmlns:wf="clrnamespace:System.Windows.Forms;assembly=System.Windows.Forms"
        xmlns:wfi="clr-namespace:System.Windows.Forms;assembly=WindowsFormsIntegration"
        mc:Ignorable="d"
        Title="SeWiSpeed v2.2.0" Height="772" Width="670">
    <Grid>
        <GroupBox x:Name="CsvFileGroupBox" Header="CSV Datei" Height="65" Margin="10,10,10,0" VerticalAlignment="Top">
            <Grid Margin="0">
                <Button x:Name="CsvFilePathButton" Content="_Browse" HorizontalAlignment="Left" Margin="10,0,0,0" Width="75" Height="20" VerticalAlignment="Center" ToolTip="Geben Sie den Pfad zu einer .csv-Datei hier an."/>
                <TextBox x:Name="CsvFilePathTextBox" Margin="90,9,10,9" TextWrapping="Wrap" Text="CSV Datei" Height="20" VerticalAlignment="Center"/>
            </Grid>
        </GroupBox>
        <RichTextBox x:Name="IperfJobOutputTextBox" Margin="10,0,138,10" VerticalScrollBarVisibility="Auto" Height="52" VerticalAlignment="Bottom"/>
        <GroupBox x:Name="iPerfGroupBox" Header="iPerf" Height="145" Margin="10,80,10,0" VerticalAlignment="Top">
            <Grid Margin="0">
                <GroupBox x:Name="SRVGroupBox" Header="Server" Height="82" Margin="275,0,10,0" VerticalAlignment="Top" HorizontalAlignment="Left" Width="110">
                    <Grid Margin="0">
                        <RadioButton x:Name="Server1Radio" Content="Server 1" HorizontalAlignment="Left" Margin="10,10,0,0" VerticalAlignment="Top" IsChecked="True"/>
                        <RadioButton x:Name="Server2Radio" Content="Server 2" HorizontalAlignment="Left" Margin="10,40,0,0" VerticalAlignment="Top"/>
                    </Grid>
                </GroupBox>
                <GroupBox x:Name="ModeGroupBox" Header="Richtung" Height="82" Margin="0,0,10,0" VerticalAlignment="Top" HorizontalAlignment="Right" Width="110">
                    <Grid Margin="0">
                        <RadioButton x:Name="ClientRadio" Content="Download" HorizontalAlignment="Left" Margin="10,10,0,0" VerticalAlignment="Top" IsChecked="True"/>
                        <RadioButton x:Name="ServerRadio" Content="Upload" HorizontalAlignment="Left" Margin="10,40,0,0" VerticalAlignment="Top"/>
                    </Grid>
                </GroupBox>
                <Label x:Name="CommandLabel" Content="_Befehl" HorizontalAlignment="Left" Height="25" Margin="26,0,0,10" VerticalAlignment="Bottom" Width="68" Target="{Binding ElementName=CommandTextBox, Mode=OneWay}"/>
                <TextBox x:Name="CommandTextBox" Margin="83,0,10,10" TextWrapping="Wrap" Height="22" VerticalAlignment="Bottom" FontSize="10"/>
                <Button x:Name="StartIperfButton" Content="Start" HorizontalAlignment="Left" Margin="10,10,0,0" VerticalAlignment="Top" Width="75" Background="#FF48C700"/>
                <Button x:Name="StopIperfButton" Content="Stop" HorizontalAlignment="Left" Margin="10,35,0,0" VerticalAlignment="Top" Width="75" Background="#FFF35555"/>
                <Label x:Name="IpLabel" Content="IP" HorizontalAlignment="Left" Margin="100,8,0,0" Width="20" Target="{Binding ElementName=IpTextBox, Mode=OneWay}" Height="23" VerticalAlignment="Top"/>
                <TextBox x:Name="IpTextBox" HorizontalAlignment="Left" Margin="155,10,0,0" TextWrapping="Wrap" Width="97" Height="23" VerticalAlignment="Top"/>
                <Label x:Name="TimeLabel" Content="Dauer in Sekunden" HorizontalAlignment="Left" Margin="100,35,0,0" Width="113" Target="{Binding ElementName=TimeTextBox, Mode=OneWay}" Height="23" VerticalAlignment="Top" ToolTip="Gesamte Testdauer in Sekunden"/>
                <TextBox x:Name="TimeTextBox" HorizontalAlignment="Left" Margin="213,38,0,0" TextWrapping="Wrap" Width="39" Height="23" VerticalAlignment="Top"/>
                <GroupBox x:Name="VersionGroupBox" Header="Test-Version" Height="82" Margin="394,00,115,20" VerticalAlignment="Top" HorizontalAlignment="Left" Width="100">
                    <Grid Margin="0">
                        <RadioButton x:Name="Version3Radio" Content="Aktuell" HorizontalAlignment="Left" Margin="10,40,0,0" VerticalAlignment="Top" IsChecked="True" ToolTip="iPerf3 3.1.3"/>
                        <RadioButton x:Name="Version2Radio" Content="Vorherige" HorizontalAlignment="Left" Margin="10,10,0,0" VerticalAlignment="Top" ToolTip="iPerf 2.0.9"/>
                    </Grid>
                </GroupBox>
            </Grid>
        </GroupBox>
        <GroupBox x:Name="Data" Header="Daten" Height="60" Margin="0,660,10,0" VerticalAlignment="Top" HorizontalAlignment="Right" Width="102">
            <Grid Margin="2,22,-2,-22">
                <TextBox x:Name="label1" Height="29" Width="52" TextWrapping="Wrap" HorizontalAlignment="Left" Margin="3,-14,0,0" VerticalAlignment="Top" BorderThickness="0" Foreground="Red" FontSize="14" FontWeight="Bold" IsReadOnly="True" IsEnabled="False" />
                <Label x:Name="label" Content="MBit/s" HorizontalAlignment="Left" Margin="31,-19,-27,0" VerticalAlignment="Top" Height="27" Width="86" FontSize="14" FontWeight="Bold" ToolTip="Aktuelle Bandbreite"/>
            </Grid>
        </GroupBox>

<WindowsFormsHost x:Name="FormWfa" Margin="10,230,10,67"/>
    </Grid>
</Window>
"@

        $InputXml = $InputXml -replace 'mc:Ignorable="d"', '' -replace 'x:N', 'N' -replace '^<Win.*', '<Window'
                 
        [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
        [xml]$Xaml = $InputXml
        
        #Read XAML
        $XamlReader = (New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $Xaml)
        try
        {
            $SyncHash.Form = [Windows.Markup.XamlReader]::Load( $XamlReader )
        }
        catch
        {
        }
        
        # Load XAML Objects In PowerShell
        $Xaml.SelectNodes('//*[@Name]') | ForEach-Object -Process {
            $SyncHash.Add($_.Name,$SyncHash.Form.FindName($_.Name))
        }
        
        #Get-Variable WPF*
        
        # Actually make the objects work
        # Create chart
        [void][reflection.assembly]::LoadWithPartialName('System.Windows.Forms')
        [void][Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms.DataVisualization')
        $SyncHash.Chart = New-Object -TypeName System.Windows.Forms.DataVisualization.Charting.Chart

        # Add chart area to chart
        $SyncHash.ChartArea = New-Object -TypeName System.Windows.Forms.DataVisualization.Charting.ChartArea
        $SyncHash.Chart.ChartAreas.Add($SyncHash.ChartArea)

        [void]$SyncHash.Chart.Series.Add('Bandbreite (MBit/s)')
        [void]$SyncHash.Chart.Series.Add('Transfer (MBytes)')

        # Display the chart on a form
		$SyncHash.Chart.BackColor = [System.Drawing.Color]::Transparent
        $SyncHash.Chart.Series['Bandbreite (MBit/s)'].ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::'Line'
        $SyncHash.Chart.Series['Transfer (MBytes)'].ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::'Line'
        $SyncHash.Chart.Width = 798
        $SyncHash.ChartLegend = New-Object -TypeName System.Windows.Forms.DataVisualization.Charting.Legend
        [void]$SyncHash.Chart.Legends.Add($SyncHash.ChartLegend)

        $SyncHash.FormWfa.Child = $SyncHash.Chart

        $SyncHash.StartIperfButton.Add_Click({
                Start-Iperf
        })
        
        $SyncHash.StopIperfButton.Add_Click({
                Stop-Iperf
        })

        $SyncHash.TimeTextBox.Text = 15
		$SyncHash.label1.Text = 0

        $SyncHash.IpTextBox.add_TextChanged({
                Set-IperfCommand
        })

        $SyncHash.TimeTextBox.add_TextChanged({
                Set-IperfCommand
        })

        $SyncHash.ClientRadio.add_Checked({
                Set-IperfCommand
        })

        $SyncHash.ServerRadio.add_Checked({
                Set-IperfCommand
        })

        $SyncHash.Version3Radio.add_Checked({
                Set-IperfCommand
        })

		$SyncHash.Version2Radio.add_Checked({
                Set-IperfCommand
        })
		
		$SyncHash.Server1Radio.add_Checked({
		$SyncHash.IpTextBox.Text = '91.194.84.95'
                Set-IperfCommand
        })
		
		$SyncHash.Server2Radio.add_Checked({
		$SyncHash.IpTextBox.Text = '89.163.131.173'
                Set-IperfCommand
        })
		
        # Csv SaveFileDialog
        $CsvSaveFileDialog = New-Object -TypeName System.Windows.Forms.SaveFileDialog
        $CsvSaveFileDialog.Filter = 'Comma Separated|*.csv|All files|*.*'
        $CsvSaveFileDialog.FileName = ([Environment]::GetFolderPath('Desktop') + '\SeWiSpeed.csv')

        $SyncHash.CsvFilePathTextBox.Text = $CsvSaveFileDialog.FileName
        $SyncHash.CsvFilePathTextBox.add_TextChanged({
                Set-IperfCommand
        })

        $SyncHash.CsvFilePathButton.Add_Click({
                $CsvSaveFileDialog.ShowDialog()
                $SyncHash.CsvFilePathTextBox.Text = $CsvSaveFileDialog.FileName
        })

        Set-IperfCommand

        Write-Status -Text 'SeWiSpeed v2.2.0 - Copyright: Patrick Hachmeyer' -Colore 'Blue'

        # Shows the form
        $null = $SyncHash.Form.ShowDialog()

        Stop-Iperf
        Stop-Analyzer

    }
)

$UiPowerShell.Runspace = $UiRunspace
$UiHandle = $UiPowerShell.BeginInvoke()
