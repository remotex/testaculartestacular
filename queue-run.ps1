param( 
	[parameter(mandatory=$true)]
	$testacularConfigPath, 
	$workspaceDir,
	$hostTimeout = (5 * 60)
)

$scriptdir = $MyInvocation.MyCommand.Path | Split-Path
if(!$workspaceDir) {
	$workspaceDir = $scriptdir
}
if( !(Test-Path $workspaceDir) ) {
	throw "Workspace directory specified does not exist: $workspaceDir"
}
$workspaceDir = Resolve-Path $workspaceDir

$runId = 1
$nextRunIdPath = Join-Path $workspaceDir "nextRunNumber"
if( Test-Path $nextRunIdPath ) {
	[int]$runId = gc $nextRunIdPath | select -First 1
}
($runId + 1) | sc $nextRunIdPath

$runDir = Join-Path $workspaceDir "runs\$runId"
if( Test-Path $runDir ) {
	rmdir -Recurse -Force $runDir 
}

mkdir $runDir | Out-Null
$runStatusPath = Join-Path $runDir "status"

$watcher = New-Object IO.FileSystemWatcher $runDir, "status" -Property @{IncludeSubdirectories = $false;NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite'} 
$watcherChangedId = "RunStatusWatcherChanged$runId"
$watcherCreatedId = "RunStatusWatcherCreated$runId"
Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier $watcherChangedId
Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier $watcherCreatedId
$watcher.EnableRaisingEvents = $true

Write-Host "Run $runId is waiting for available executor"
$testacularConfigPath | sc $runDir\runOptions
$createdEvent = Wait-Event -SourceIdentifier $watcherCreatedId -Timeout $hostTimeout
if( $createdEvent ) {
	$createdEvent | Remove-Event
} else {
	Write-Host "Run timed out: Host did not pick up before the timeout of $hostTimeout seconds occurred"
}

try {
	while($createdEvent) {
		$event = Wait-Event -SourceIdentifier $watcherChangedId
		$event | Remove-Event
		$status = gc $runStatusPath | select -First 1
		Write-Host "Run $runId status: $status"
		if( $status -match "FAILED|SUCCESS" ) {
			if( Test-Path $runDir\output ) {
				Write-Host "Output:"
				gc $runDir\output | %{ "    $_" } | Out-Host
				Write-Host "--EOF--"
			} else {
				Write-Host "No output from run"
			}
			break
		}
	}
} finally {
	Unregister-Event -SourceIdentifier $watcherChangedId
	Unregister-Event -SourceIdentifier $watcherCreatedId
	$watcher.Dispose()
}