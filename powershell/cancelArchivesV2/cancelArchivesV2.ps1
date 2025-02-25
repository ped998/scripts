### process commandline arguments
[CmdletBinding()]
param (
   [Parameter(Mandatory = $True)][string]$vip, #the cluster to connect to (DNS name or IP)
   [Parameter(Mandatory = $True)][string]$username, #username (local or AD)
   [Parameter()][string]$domain = 'local', #local or AD domain
   [Parameter()][string]$jobName,  #optional jobname filter
   [Parameter()][switch]$cancelOutdated,
   [Parameter()][switch]$cancelQueued,
   [Parameter()][switch]$cancelAll,
   [Parameter()][int]$cancelOlderThan = 0,
   [Parameter()][switch]$showFinished,
   [Parameter()][int]$numRuns = 1000,
   [Parameter()][ValidateSet('MiB','GiB','TiB')][string]$unit = 'MiB'
)

### source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

$conversion = @{'MiB' = 1024 * 1024; 'GiB' = 1024 * 1024 * 1024; 'TiB' = 1024 * 1024 * 1024 * 1024}
function toUnits($val){
    return "{0:n2}" -f ($val/($conversion[$unit]))
}

### authenticate
apiauth -vip $vip -username $username -domain $domain

$finishedStates = @('Succeeded', 'Canceled', 'Failed', 'Warning')

$cluster = api get cluster
$dateString = (get-date).ToString('yyyy-MM-dd')
$outfileName = "ArchiveQueue-$($cluster.name)-$dateString.csv"
"JobName,RunDate,Status,$unit Transferred" | Out-File -FilePath $outfileName

$nowUsecs = dateToUsecs (get-date)

$runningTasks = 0

$now = Get-Date
$nowUsecs = dateToUsecs $now

$jobs = (api get -v2 "data-protect/protection-groups?isDeleted=false&isActive=true&includeTenants=true").protectionGroups | Sort-Object -Property name
if($jobName){
    $jobs = $jobs | Where-Object name -eq $jobName
}

foreach($job in $jobs){
    $jobId = $job.id
    $thisJobName = $job.name
    "Getting tasks for $thisJobName"
    $endUsecs = $nowUsecs
    $runInfo = @()
    while($True){
        $runs = api get -v2 "data-protect/protection-groups/$jobId/runs?numRuns=$numRuns&endTimeUsecs=$endUsecs&includeTenants=true&includeObjectDetails=false"
        if($runs.runs.Count -gt 0){
            $endUsecs = $runs.runs[-1].localBackupInfo.startTimeUsecs - 1
        }else{
            break
        }
        foreach($run in $runs.runs){
            $runId = $run.id
            $startTimeUsecs = $run.localBackupInfo.startTimeUsecs
            foreach($archivalInfo in $run.archivalInfo.archivalTargetResults){
                $taskId = $archivalInfo.archivalTaskId
                $status = $archivalInfo.status
                $transferred = toUnits $archivalInfo.stats.logicalBytesTransferred
                $expiryTime = $archivalInfo.expiryTimeUsecs
                $isIncremental = $archivalInfo.isIncremental
                $runInfo = @($runInfo + @{
                    'runId' = $runId;
                    'taskId' = $taskId;
                    'status' = $status;
                    'transferred' = $transferred;
                    'expiryTime' = $expiryTime;
                    'isIncremental' = $isIncremental;
                    'startTimeUsecs' = $startTimeUsecs;
                })
            }
        }

        if($cancelQueued){
            $runInfo = @($runInfo | Where-Object {$_.status -notin $finishedStates})
            $runInfo = $runInfo[0..$($runInfo.Length-2)]
        }elseif($cancelOlderThan -gt 0){
            $daysBack = (Get-Date).AddDays(-$cancelOlderThan)
            $daysBackUsecs = dateToUsecs $daysBack
            $runInfo = @($runInfo | Where-Object {$_.status -notin $finishedStates -and $_.startTimeUsecs -lt $daysBackUsecs})
        }
        foreach($run in $runInfo){
            $referenceFull = ''
            if($run.isIncremental -eq $false){
                $referenceFull = '(Reference Full)'
            }
            if($run.status -notin $finishedStates){
                $cancelling = ''
                $reason = ''
                if($run.expiryTimeUsecs -and $nowUsecs -gt $run.expiryTimeUsecs){
                    $reason = '(Outdated)'
                    if($cancelOutdated){
                        $cancelling = '(Cancelling)'
                    }
                }
                if($cancelQueued){
                    $reason = '(Queued)'
                    $cancelling = '(Cancelling)'
                }
                if($cancelAll){
                    $cancelling = '(Cancelling)'
                }
                "    $($run.status)  $(usecsToDate $($run.startTimeUsecs))  ($($run.transferred))  $referenceFull  $reason  $cancelling"
                if($cancelling -ne ''){
                    $cancelParams = @{
                        "archivalTaskId" = @(
                                $run.taskId
                        )
                    }
                    $null = api post -v2 "data-protect/protection-groups/$jobId/runs/$($run.runId)/cancel" $cancelParams
                }
            }else{
                if($showFinished){
                    "    $($run.status)  $(usecsToDate $($run.startTimeUsecs))  ($($run.transferred))  $referenceFull"
                }
            }
        }
    }
}
