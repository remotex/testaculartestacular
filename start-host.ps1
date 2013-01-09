param( $testacularDir = $(join-path -Resolve $env:APPDATA "npm\node_modules\testacular"), $port = 8080, $workspaceDir )

$scriptdir = $MyInvocation.MyCommand.Path | Split-Path
$hostConfigPath = join-path -Resolve $scriptdir "emptyhost.conf.js"
$outFilename = "testacular.out.log"
$errFilename = "testacular.err.log"
$hostOutputPath = join-path $scriptdir $outFilename
$hostErrorPath = join-path $scriptdir $errFilename
$nodePath = Get-Command node | select -ExpandProperty Definition

if(!$workspaceDir) {
	$workspaceDir = $scriptdir
}

function startTestacular( $configPath, $outputFilePath, $errorFilePath, [switch] $singleRun ) {
	$command = "$testacularDir\bin\testacular start $configPath --no-colors --port $port"
	if( $singleRun ) {
		$command += " --single-run"
	}
	Write-Host -NoNewline "Starting testacular: '$command'"
	$proc = Start-Process -FilePath $nodePath -ArgumentList $command -NoNewWindow -PassThru -RedirectStandardOutput $outputFilePath -RedirectStandardError $errorFilePath
	Write-Host " (PID $($proc.Id))"
	$proc
}

function startPlaceholderHost {
	Write-Host "Starting new placeholder host"
	startTestacular $hostConfigPath -outputFilePath $hostOutputPath -errorFilePath $hostErrorPath
}

function writeRunOutput( $runDir, $message ) {
	Write-Host $message
	$message | ac $runDir\output
}

function executeRun( $runOptionsFile, $hostProcess ) {
	$runDir = $runOptionsFile | Split-Path
	$runId = $runDir | Split-Path -Leaf
	"RUNNING" | sc $runDir\status
	writeRunOutput $runDir "Run $runId was created at $runDir"
	$runConfigPath = gc $runOptionsFile | select -First 1
	if( !(Test-Path $runConfigPath) ) {
		writeRunOutput $runDir "Cannot find config file '$runConfigPath'"
		"FAILED" | sc $runDir\status
		return
	}
		
	writeRunOutput $runDir "Killing default host (PID: $($hostProcess.Id))"
	$hostProcess.Kill()
	writeRunOutput $runDir "Waiting for default host to exit (PID: $($hostProcess.Id))"	
	$hostProcess.WaitForExit()
	
	writeRunOutput $runDir "Starting run with config $runConfigPath"
	$outputFilePath = Join-Path $runDir $outFilename
	$errorFilePath = Join-Path $runDir $errFilename
	$runProcess = startTestacular $runConfigPath -outputFilePath $outputFilePath -errorFilePath $errorFilePath -singleRun
	writeRunOutput $runDir "Waiting for run to complete (PID: $($runProcess.Id))"
	$status = "FAILED"
	if( $runProcess.WaitForExit( [TimeSpan]::FromMinutes(10).TotalMilliseconds ) ) {
		gc $outputFilePath | %{ writeRunOutput $runDir $_ }
		if( (gi $errorFilePath).Length -eq 0 -or $outputFilePath | Select-String "FAILED" ) {
			writeRunOutput $runDir "Run $runId completed successfully"
			$status = "SUCCESS"
		} else {
			writeRunOutput $runDir "Run $runId failed"
			gc $errorFilePath | %{ writeRunOutput $runDir $_ }
		}
	} else {
		writeRunOutput $runDir "Run $runId failed due to timeout"
	}		
	$status | sc $runDir\status
}

$runsDir = join-path $workspaceDir "runs"
if(!(test-path $runsDir)) {
	mkdir $runsDir | Out-Null
}
$hostProcess = startPlaceholderHost

$watcher = New-Object IO.FileSystemWatcher $runsDir, "runOptions" -Property @{IncludeSubdirectories = $true;NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite'} 
$watcherId = "NewRunWatcher"
Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier $watcherId
$watcher.EnableRaisingEvents = $true

try {
	while(1) {
		Write-Host "Waiting for new runs in $runsDir"
		$event = Wait-Event -SourceIdentifier $watcherId
		$event | Remove-Event
		$runDir = $event.SourceEventArgs.FullPath
		Write-Host "Executing run for $runDir"
		executeRun $runDir $hostProcess
		if( $hostProcess.HasExited ) {
			$hostProcess = startPlaceholderHost
		}
	}
} finally {
	Unregister-Event -SourceIdentifier $watcherId
	$watcher.Dispose()
}