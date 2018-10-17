<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2018 v5.5.150
	 Created on:   	10/16/2018 12:16 PM
	 Created by:   	Andy DeAngelis
	 Organization: 	
	 Filename: DiskSpdBatchNew.ps1    	
	===========================================================================
	.DESCRIPTION
			This script is based off of Heraflux's excellent DiskSpdBatch.ps1 
			script (https://www.heraflux.com/resources/utilities/diskspd-batch/).
			The original script is also bundled with this package.

			Some changes have been made to the logic and parameters. This version also
			comes packaged with the DiskSpd executables for x86, ARM and x64. The
			correct executable is then called based on whichever OS architecture
			is returned from the updated WMI query.

			The purpose of this script is to drive increasing load
    		to a storage device so a performance profile under varying
    		degrees of load can be created with a single portable PoSH script. 

	.PARAMETER Time
    Set your individual test duration in seconds - req minimum 30 seconds per test

	.PARAMETER DataFileDir
    Workload data file path and name.    

	.PARAMETER DataFile
    Workload data file name.

    .PARAMETER DataFileSize
    Workload data file size. Use M or G to specify file size (i.e. "1024M" or "1G").

    .PARAMETER BlockSize
    Change the test block size (in KB "K" or MB "M") according to your application workload profile.

    .PARAMETER OutPath
    Path to store output to.

    .PARAMETER SplitIO
    Test permutations of %R/%W in a single test

    .PARAMETER AllowIdle
    So as not to overrun SAN controller cache, do you want to have a 20 second
    pause between tests?

    .PARAMETER EntropySize
    Manual set entropy size.
#>

param (
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$time,
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$dataFileDir,
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$dataFiles,
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$dataFileSize,
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$outPath,
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$BlockSize,	
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$SplitIO,
	[parameter(Mandatory = $true, ValueFromPipeline = $true)]
	[string]$AllowIdle,
	[parameter(Mandatory = $false, ValueFromPipeline = $true)]
	[string]$EntropySize
)

if ($PSVersionTable.PSVersion.Major -lt 3)
{
	Write-host "Error: This script requires Powershell Version 3 and above to run correctly" -ForegroundColor Red
	return
}
else
{
	
	Clear-Host
	
	$sArgs = @()
	$outset = @()
	$buckets = @()
	
	# Determine OS Architecture and diskspd.exe version.
	
	$osArchitecture = Get-WmiObject -Class Win32_OperatingSystem
	if ($osArchitecture.OSArchitecture -eq "64-bit")
	{
		$diskspdExePath = ".\DiskSpd\amd64"
	}
	elseif ($osArchitecture.OSArchitecture -eq "64-bit")
	{
		$diskspdExePath = ".\DiskSpd\x86"
	}
	
	#Testing that directories for new data files exist
	foreach ($folder in $datafiledir)
	{
		if ((test-path $folder) -eq $false)
		{
			$noDir = $true
		}
	}
	
	#Building datafile args(this is to handle multiple data files in the future)
	foreach ($datafile in $dataFiles)
	{
		$sArgs += "$datafile"		
	}
	
	if (((test-path $outpath) -eq $true) -And (-Not ($noDir)))
	{
		
		# Variables
		
		# Set the date/time stamp
		$startDate = Get-Date
		
		# Get the source path of the executing script.
		$invocation = (Get-Variable MyInvocation).Value
		
		# Split the script name and path variables.
		$directorypath = Split-Path $invocation.MyCommand.Path
		
		# Set the random and sequential flags.
		$seqrandSet = @("r", "s") #random or sequential
		
		# Array containing values for maximum simultaneous iops for each test run.
		$opsSet = @(1, 2, 4, 8, 16, 32, 64, 128)
		
		
		# Get CPU cores to determine number of threads.
		$processors = get-wmiobject -computername localhost Win32_ComputerSystem
		$threads = 0
		if (@($processors).NumberOfLogicalProcessors)
		{
			$threads = @($processors).NumberOfLogicalProcessors			
		}
		else
		{
			$threads = @($processors).NumberOfProcessors
		}
		
		# Timestamp the output file.
		$filename = "diskspd_results_" + (Get-Date -format '_yyyyMMdd_HHmmss') + ".xml"
		$outfile = Join-Path -Path $outPath -childpath $filename
		$csvfile = $outfile -replace ".xml", ".csv"
		
		
		# If opt to perform R&W testing in a single test, set steppoints here
		if ($SplitIO -eq "Y")
		{
			# The percentages for write workloads set in the array if SplitIO is set to 'Y'.
			$writeperc = @(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100)
		}
		else
		{
			# If SplitIO is set to 'N', will run one full read and one full write test.
			$writeperc = @(0, 100)
		}
		
		# Determine the number of tests we will be performing
		$testCount = $seqrandSet.Count * $opsSet.Count * $writeperc.Count
		
		Write-Host Number of tests to be executed: $testCount
		Write-Host "Approximate time to complete test:" ([System.Math]::Ceiling($testCount * $time / 60)) "minute(s)"
		$currentDir = Split-Path $myinvocation.mycommand.path
		
		Write-Host ""
		Write-Host "DiskSpd test sweep - Now beginning"
		
		<# Copy DiskSpd into current folder 
		if (![System.IO.File]::Exists($diskspdExe + '\diskspd.exe'))
		{
			Write-Host "Copying diskspd to local directory - $diskspdexe\diskspd.exe"
			Copy-Item "$diskspd\diskspd.exe" "$currentDir"
		} /#>
		
		$p = New-Object System.Diagnostics.Process
		$diskspdExePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($diskspdExePath)
		$p.StartInfo.FileName = "$diskspdExePath\diskspd.exe"
		$p.StartInfo.RedirectStandardError = $true
		$p.StartInfo.RedirectStandardOutput = $true
		$p.StartInfo.UseShellExecute = $false
		
		Write-Output "DiskSpd testing started..."
		
		# DiskSpd does not write a proper XML root node
		"<DiskSpdTests>" | Out-File $outfile
		
		#Progress meter       
		$counter = 1
		
		# Execute tests in a loop from the array values above
		foreach ($seqrand in $seqrandSet)
		{
			foreach ($ops in $opsSet)
			{
				foreach ($writetest in $writeperc)
				{
					
					#sequential or random - ignore -r flag if sequential
					if ($seqrand -eq "s")
					{
						$rnd = ""
					}
					else
					{
						$rnd = "-r"
					}
					
					Write-Progress -Activity "Executing DiskSpd Tests..." -Status "Executing Test $counter of $testCount" `
								   -PercentComplete (($counter / ($testCount)) * 100)
					#$arguments = "-c$dataFileSize -w$writetest -t$threads -d$time -o$ops $rnd -b$BlockSize -C1 -Z$EntropySize -W1 -Rxml -L -h `"$dataFile`""
					$arguments = "-c$dataFileSize -w$writetest -t$threads -d$time -o$ops $rnd -b$BlockSize -C1 -Z$EntropySize -W1 -Rxml -L -h $sArgs"
					
					# DEBUG, breaks XML compliance
					Write-Output "diskspd.exe  $arguments" | Out-File "$outpath\Debug.log" -append
					
					$p.StartInfo.Arguments = $arguments
					$p.Start() | Out-Null
					$output = $p.StandardOutput.ReadToEnd()
					
					#Fix for MS bug that doesnt correctly label the Tag for Random from DiskSpd
					if ($seqrand -eq "r")
					{
						$output = $output.Replace('<RandomAccess>false</RandomAccess>', '<RandomAccess>true</RandomAccess>')
					}
					
					
					$output | Out-File $outfile -Append
					$p.WaitForExit()
					
					$counter = $counter + 1
					
					if ($AllowIdle -eq "Y")
					{
						# Pause for 20s to allow I/O idling
						Write-Host "Pausing briefly to allow I/O idling... . .   .     .         ."
						Start-Sleep -Seconds 20
					}
				}
			}
		}
		
		# Close the XML root node
		"</DiskSpdTests>" >> $outfile
		
		Write-Output "Done DiskSpd testing. Now creating CSV output file."
		
		#Export test results as .csv
		
		[xml]$xDoc = Get-Content $outfile
		
		$timespans = $xDoc.DiskSpdTests.Results.timespan
		
		$n = 0
		$resultobj = @()
		$cols_sum = @('BytesCount', 'IOCount', 'ReadBytes', 'ReadCount', 'WriteBytes', 'WriteCount')
		$cols_avg = @('AverageReadLatencyMilliseconds', 'ReadLatencyStdev', 'AverageWriteLatencyMilliseconds', 'WriteLatencyStdev', 'AverageLatencyMilliseconds', 'LatencyStdev')
		$cols_ntile = @('0', '25', '50', '75', '90', '95', '99', '99.9', '99.99'.'99.999', '99.9999', '99.99999'.'99.999999', '100')
		
		foreach ($ts in $timespans)
		{
			$threads = $ts.Thread.Target
			$buckets = $ts.Latency.Bucket
			
			#create custom PSObject for output
			$outset = New-Object -TypeName PSObject
			$outset | Add-Member -MemberType NoteProperty -Name TimeSpan -Value $n
			$outset | Add-Member -MemberType NoteProperty -Name TestTimeSeconds -Value $xDoc.DiskSpdTests.Results.timespan[$n].TestTimeSeconds
			$outset | Add-Member -MemberType NoteProperty -Name RequestCount -Value $xDoc.DiskSpdTests.Results[$n].Profile.TimeSpans.TimeSpan.Targets.Target.RequestCount
			$outset | Add-Member -MemberType NoteProperty -Name WriteRatio -Value $xDoc.DiskSpdTests.Results[$n].Profile.TimeSpans.TimeSpan.Targets.Target.WriteRatio
			$outset | Add-Member -MemberType NoteProperty -Name ThreadsPerFile -Value $xDoc.DiskSpdTests.Results[$n].Profile.TimeSpans.TimeSpan.Targets.Target.ThreadsPerFile
			$outset | Add-Member -MemberType NoteProperty -Name FileSize -Value $xDoc.DiskSpdTests.Results[$n].Profile.TimeSpans.TimeSpan.Targets.Target.FileSize
			$outset | Add-Member -MemberType NoteProperty -Name IsRandom -Value $xDoc.DiskSpdTests.Results[$n].Profile.TimeSpans.TimeSpan.Targets.Target.RandomAccess
			$outset | Add-Member -MemberType NoteProperty -Name BlockSize -Value $xDoc.DiskSpdTests.Results[$n].Profile.TimeSpans.TimeSpan.Targets.Target.BlockSize
			$outset | Add-Member -MemberType NoteProperty -Name TestFilePath -Value $xDoc.DiskSpdTests.Results[$n].Profile.TimeSpans.TimeSpan.Targets.Target.Path
			
			
			#loop through nodes that will be summed across threads
			foreach ($col in $cols_sum)
			{
				$outset | Add-Member -MemberType NoteProperty -Name $col -Value ($threads | Measure-Object $col -Sum).Sum
			}
			
			#generate MB/s and IOP values
			$outset | Add-Member -MemberType NoteProperty -Name MBps -Value (($outset.BytesCount / 1048576) / $outset.TestTimeSeconds)
			$outset | Add-Member -MemberType NoteProperty -Name IOps -Value ($outset.IOCount / $outset.TestTimeSeconds)
			$outset | Add-Member -MemberType NoteProperty -Name ReadMBps -Value (($outset.ReadBytes / 1048576) / $outset.TestTimeSeconds)
			$outset | Add-Member -MemberType NoteProperty -Name ReadIOps -Value ($outset.ReadCount / $outset.TestTimeSeconds)
			$outset | Add-Member -MemberType NoteProperty -Name WriteMBps -Value (($outset.WriteBytes / 1048576) / $outset.TestTimeSeconds)
			$outset | Add-Member -MemberType NoteProperty -Name WriteIOps -Value ($outset.WriteCount / $outset.TestTimeSeconds)
			
			#loop through nodes that will be averaged across threads
			foreach ($col in $cols_avg)
			{
				if ($threads.SelectNodes($col))
				{
					$outset | Add-Member -MemberType NoteProperty -Name $col -Value ($threads | Measure-Object $col -Average).Average
				}
				else
				{
					$outset | Add-Member -MemberType NoteProperty -Name $col -Value ""
				}
			}
			#loop through ntile buckets and extract values for the declared ntiles
			foreach ($bucket in $buckets)
			{
				if ($cols_ntile -contains $bucket.Percentile)
				{
					if ($bucket.SelectNodes('ReadMilliseconds'))
					{
						$outset | Add-Member -MemberType NoteProperty -Name ("ReadMS_" + $bucket.Percentile) -Value $bucket.ReadMilliseconds
					}
					else
					{
						$outset | Add-Member -MemberType NoteProperty -Name ("ReadMS_" + $bucket.Percentile) -Value ""
					}
					
					if ($bucket.SelectNodes('WriteMilliseconds'))
					{
						$outset | Add-Member -MemberType NoteProperty -Name ("WriteMS_" + $bucket.Percentile) -Value $bucket.WriteMilliseconds
					}
					else
					{
						$outset | Add-Member -MemberType NoteProperty -Name ("WriteMS_" + $bucket.Percentile) -Value ""
					}
					
					$outset | Add-Member -MemberType NoteProperty -Name ("TotalMS_" + $bucket.Percentile) -Value $bucket.TotalMilliseconds
				}
			}
			
			#Add some CPU Avg's to CSV file for analysis
			$outset | Add-Member -MemberType NoteProperty -Name AvgUsagePercent -Value $xDoc.DiskSpdTests.Results[$n].TimeSpan.CpuUtilization.Average.UsagePercent
			$outset | Add-Member -MemberType NoteProperty -Name AvgUserPercent -Value $xDoc.DiskSpdTests.Results[$n].TimeSpan.CpuUtilization.Average.UserPercent
			$outset | Add-Member -MemberType NoteProperty -Name AvgKernelPercent -Value $xDoc.DiskSpdTests.Results[$n].TimeSpan.CpuUtilization.Average.KernelPercent
			$outset | Add-Member -MemberType NoteProperty -Name AvgIdlePercent -Value $xDoc.DiskSpdTests.Results[$n].TimeSpan.CpuUtilization.Average.IdlePercent
			
			$resultobj += $outset
			$n++
			
		}
		$resultobj | Export-Csv -Path $csvfile -NoTypeInformation
		
	}
	else
	{
		if ((test-path $outpath) -eq $false)
		{
			Write-Host "$outPath doesnt exist and needs to be created..." -ForegroundColor red -BackgroundColor yellow
		}
		foreach ($folder in $datafiledir)
		{
			if ((test-path $folder) -eq $false)
			{
				Write-Host "$folder doesnt exist and needs to be created..." -ForegroundColor red -BackgroundColor yellow
			}
		}
	}
	
}
