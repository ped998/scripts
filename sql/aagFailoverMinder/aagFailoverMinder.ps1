# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][switch]$useApiKey,
    [Parameter()][string]$password = $null,
    [Parameter()][array]$jobName,
    [Parameter()][string]$jobList
)

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

# authenticate
if($useApiKey){
    apiauth -vip $vip -username $username -domain $domain -useApiKey -password $password
}else{
    apiauth -vip $vip -username $username -domain $domain -password $password
}

# outfile
$cluster = api get cluster
$outfileName = "log-aagFailoverMonitor-$($cluster.name).txt"
if(Test-Path -Path $outfileName){
    $log = Get-Content -Path $outfileName
    $logLength = $log.Length
    if($logLength -gt 200){
        $log[100..$logLength] | Out-File -Path $outfileName
    }
}

# gather list from command line params and file
function gatherList($Param=$null, $FilePath=$null, $Required=$True, $Name='items'){
    $items = @()
    if($Param){
        $Param | ForEach-Object {$items += $_}
    }
    if($FilePath){
        if(Test-Path -Path $FilePath -PathType Leaf){
            Get-Content $FilePath | ForEach-Object {$items += [string]$_}
        }else{
            Write-Host "Text file $FilePath not found!" -ForegroundColor Yellow
            exit
        }
    }
    if($Required -eq $True -and $items.Count -eq 0){
        Write-Host "No $Name specified" -ForegroundColor Yellow
        exit
    }
    return ($items | Sort-Object -Unique)
}

function waitForRefresh($id){
    $authStatus = ""
    while($authStatus -ne 'kFinished'){
        Start-Sleep 3
        $rootNode = (api get "protectionSources/registrationInfo?ids=$id").rootNodes[0]
        $authStatus = $rootNode.registrationInfo.authenticationStatus
    }
}

$jobNames = @(gatherList -Param $jobName -FilePath $jobList -Name 'jobs' -Required $false)
$jobs = api get protectionJobs?environments=kSQL | Where-object {$_.isActive -ne $false -and $_.isDeleted -ne $True}

if($jobNames.Count -gt 0){
    $notfoundJobs = $jobNames | Where-Object {$_ -notin $jobs.name}
    if($notfoundJobs){
        "Jobs not found $($notfoundJobs -join ', ')" | Tee-Object -FilePath $outfileName
    }
}

"Getting SQL protection run status..."
foreach($job in $jobs | Sort-Object -Property name){
    $endUsecs = dateToUsecs (Get-Date)
    if($jobNames.Count -eq 0 -or $job.name -in $jobNames){
        "    {0}" -f $job.name
        $needsRun = $false

        # check last run for aag state change
        $runs = api get "protectionRuns?jobId=$($job.id)&numRuns=1"
        $objectIds = @()
        foreach($run in $runs){
            $runStartTime = usecsToDate $run.backupRun.stats.startTimeUsecs
            $status = $run.backupRun.status
            $runType = $run.backupRun.runType
            if($status -eq 'kFailure'){
                if($run.backupRun.PSObject.Properties['error']){
                    $runNowParameters = @()
                    $message = $run.backupRun.error
                    if($message -match 'Detected AAG metadata changes on the host'){
                        $needsRun = $True
                    }
                    if($message -match 'No matching replica found for the backup preference'){
                        $needsRun = $True
                    }
                    if($message -match 'Discovered a break in the logchain'){
                        $needsRun = $True
                    }
                    if($needsRun){
                        "        ({0}): {1}" -f $runStartTime, $message
                        "{0} ({1}): {2}" -f $job.name, $runStartTime, $message | Out-File -FilePath $outfileName -Append    
                    }
                    foreach($source in $run.backupRun.sourceBackupStatus){
                        if($source.status -eq 'kFailure'){
                            $sourceId = $source.source.id

                            $runNowParameter = @{
                                "sourceId" = $sourceId;
                            }
                            $sourceName = $source.source.name
                            foreach($app in $source.appsBackupStatus){
                                if($app.PSObject.Properties['error']){
                                    if(! $runNowParameter.databaseIds){
                                        $runNowParameter.databaseIds = @()
                                    }
                                    $runNowParameter.databaseIds = @($runNowParameter.databaseIds + $app.appId)
                                }
                            }
                            $runNowParameters = @($runNowParameters + $runNowParameter)
                        }
                    }
                }
            }
        }

        # run incremental if needed
        if($needsRun){
            "        Refreshing sources..."
            foreach($sourceId in $job.sourceIds){
                $result = api post "protectionSources/refresh/$sourceId"
                waitForRefresh($sourceId)
            }
            $jobId = $job.id
            $policy = api get protectionPolicies | Where-Object {$_.id -eq $job.policyId}
            # local retention from policy
            $copyRunTargets = @(
                @{
                    "type" = "kLocal";
                    "daysToKeep" = $policy.daysToKeep
                }
            )
            # replicas from policy
            if($policy.PSObject.Properties['snapshotReplicationCopyPolicies']){
                foreach($replica in $policy.snapshotReplicationCopyPolicies){
                    if(!($copyRunTargets | Where-Object {$_.replicationTarget.clusterName -eq $replica.target.clusterName})){
                        $copyRunTargets = @($copyRunTargets + @{
                            "daysToKeep"        = $replica.daysToKeep;
                            "replicationTarget" = $replica.target;
                            "type"              = "kRemote"
                        })
                    }
                }
            }
            # archives from policy
            if($policy.PSObject.Properties['snapshotArchivalCopyPolicies']){
                foreach($archive in $policy.snapshotArchivalCopyPolicies){
                    if(!($copyRunTargets | Where-Object {$_.archivalTarget.vaultName -eq $archive.target.vaultName})){
                        $copyRunTargets = @($copyRunTargets + @{
                            "archivalTarget" = $archive.target;
                            "daysToKeep"     = $archive.daysToKeep;
                            "type"           = "kArchival"
                        })
                    }
                }
            }
            $runParams = @{
                "runType" = 'kRegular';
                "copyRunTargets" = @($copyRunTargets)
                "runNowParameters" = $runNowParameters
            }

            $newRun = api post "protectionJobs/run/$jobId" $runParams
            Write-Host "        Running job $($job.name) again..."
        }
    }
}
