# version 2022.05.11
### usage: ./restoreFiles.ps1 -vip mycluster -username myuser -domain mydomain.net `
#                             -sourceServer server1.mydomain.net `
#                             -targetServer server2.mydomain.net `
#                             -fileNames /home/myuser/file1, /home/myuser/file2 `
#                             -restorePath /tmp/restoretest1/ `
#                             -fileDate '2020-04-18 18:00:00' `
#                             -wait

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, # the cluster to connect to (DNS name or IP)
    [Parameter()][string]$username='helios', # username (local or AD)
    [Parameter()][string]$domain = 'local', # local or AD domain
    [Parameter()][switch]$useApiKey, # use API key for authentication
    [Parameter()][string]$password = $null,
    [Parameter(Mandatory = $True)][string]$sourceServer, # source server
    [Parameter()][string]$targetServer = $sourceServer, # target server
    [Parameter()][string]$jobName, # narrow search by job name
    [Parameter()][array]$fileNames, # one or more file paths comma separated
    [Parameter()][string]$fileList, # text file with file paths
    [Parameter()][string]$restorePath, # target path
    [Parameter()][Int64]$runId, # restore from specific runid
    [Parameter()][datetime]$start,
    [Parameter()][datetime]$end,
    [Parameter()][switch]$latest,
    [Parameter()][switch]$wait,
    [Parameter()][switch]$showLog
)

### source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

### authenticate
if($useApiKey){
    apiauth -vip $vip -username $username -domain $domain -useApiKey -password $password
}else{
    apiauth -vip $vip -username $username -domain $domain -password $password
}

# gather file names
$files = @()
if($fileList -and (Test-Path $fileList -PathType Leaf)){
    $files += Get-Content $fileList | Where-Object {$_ -ne ''}
}elseif($fileList){
    Write-Host "File $fileList not found!" -ForegroundColor Yellow
    exit 1
}
if($fileNames){
    $files += $fileNames
}
if($files.Length -eq 0){
    Write-Host "No files selected for restore" -ForegroundColor Yellow
    exit 1
}

# convert to unix style file paths
if($restorePath){
    $restorePath = ("/" + $restorePath.Replace('\','/').replace(':','')).Replace('//','/')
}
$files = [string[]]$files | ForEach-Object {("/" + $_.Replace('\','/').replace(':','')).Replace('//','/')}

# find source and target server
$physicalEntities = api get "/entitiesOfType?environmentTypes=kPhysical&physicalEntityTypes=kHost"
$targetEntity = $physicalEntities | Where-Object displayName -eq $targetServer

if(!$targetEntity){
    Write-Host "$targetServer not found" -ForegroundColor Yellow
    exit 1
}

# find backups for source server
$searchResults = api get "/searchvms?entityTypes=kPhysical&vmName=$sourceServer"
$searchResults = $searchResults.vms | Where-Object {$_.vmDocument.objectName -eq $sourceServer}

# narrow search by job name
if($jobName){
    $altJobName = "Old Name: $jobName"
    $altJobName2 = "$jobName \(Old Name:"
    $searchResults = $searchResults | Where-Object {($_.vmDocument.jobName -eq $jobName) -or ($_.vmDocument.jobName -match $altJobName) -or ($_.vmDocument.jobName -match $altJobName2)}
}

if(!$searchResults){
    if($jobName){
        Write-Host "$sourceServer is not protected by $jobName" -ForegroundColor Yellow
    }else{
        Write-Host "$sourceServer is not protected" -ForegroundColor Yellow
    }
    exit 1
}

$searchResult = ($searchResults | sort-object -property @{Expression={$_.vmDocument.versions[0].snapshotTimestampUsecs}; Ascending = $False})[0]

$doc = $searchResult.vmDocument
$sourceEntity = $doc.objectId.entity

# find requested version
$independentRestores = $True
if($runId){
    $version = $doc.versions | Where-Object {$_.instanceId.jobInstanceId -eq $runId}
    $independentRestores = $False
    if(! $version){
        Write-Host "Run ID $runId not found" -ForegroundColor Yellow
        exit 1
    }
}else{
    if($start){
        $doc.versions = $doc.versions | Where-Object {$start -le (usecsToDate ($_.snapshotTimestampUsecs))}
    }
    if($end){
        $doc.versions = $doc.versions | Where-Object {$end -ge (usecsToDate ($_.snapshotTimestampUsecs))}
    }
    if($doc.versions){
        if($latest){
            $independentRestores = $False
        }
        $version = $doc.versions[0]
    }else{
        Write-Host "No versions available for $sourceServer" -ForegroundColor Yellow
        exit
    }
}

function restore($thesefiles, $doc, $version, $targetEntity, $singleFile){
    $restoreTaskName = "Recover-Files_$(get-date -UFormat '%b_%d_%Y_%H-%M%p')"
    if($singleFile){
        $fileParts = ($thesefiles -split '/' | Where-Object {$_ -ne '' -and $_ -ne $null})
        $shortfile = $fileParts[-1]
        $restoreTaskName = "Recover-Files_$(get-date -UFormat '%b_%d_%Y_%H-%M%p')_$shortfile"
    }
    $restoreParams = @{
        "filenames"        = [string[]]$thesefiles;
        "sourceObjectInfo" = @{
            "jobId"          = $doc.objectId.jobId;
            "jobInstanceId"  = $version.instanceId.jobInstanceId;
            "startTimeUsecs" = $version.instanceId.jobStartTimeUsecs;
            "entity"         = $doc.objectId.entity;
            "jobUid"         = $doc.objectId.jobUid
        };
        "params"           = @{
            "targetEntity"            = $targetEntity;
            "targetEntityCredentials" = @{
                "username" = "";
                "password" = ""
            };
            "restoreFilesPreferences" = @{
                "restoreToOriginalPaths"        = $true;
                "overrideOriginals"             = $true;
                "preserveTimestamps"            = $true;
                "preserveAcls"                  = $true;
                "preserveAttributes"            = $true;
                "continueOnError"               = $true;
            }
        };
        "name"             = $restoreTaskName
    }
    
    # set alternate restore path
    if($restorePath){
        $restoreParams.params.restoreFilesPreferences.restoreToOriginalPaths = $false
        $restoreParams.params.restoreFilesPreferences["alternateRestoreBaseDirectory"] = $restorePath
    }

    # select local or cloud archive copy
    if($version.replicaInfo.replicaVec[0].target.type -eq 3){
        $restoreParams.sourceObjectInfo['archivalTarget'] = $version.replicaInfo.replicaVec[0].target.archivalTarget
    }

    if($singleFile){
        Write-Host "Restoring $thesefiles"
    }else{
        Write-Host "Restoring Files"
    }
    
    $restoreTask = api post /restoreFiles $restoreParams
    if($restoreTask){
        $taskId = $restoreTask.restoreTask.performRestoreTaskState.base.taskId
        if($wait -or $showLog){
            $finishedStates = @('kCanceled', 'kSuccess', 'kFailure')
            $restoreTaskStatus = $restoreTask.restoreTask.performRestoreTaskState.base.publicStatus
            do {
                Start-Sleep 3
                $restoreTask = api get /restoretasks/$taskId
                $restoreTaskStatus = $restoreTask.restoreTask.performRestoreTaskState.base.publicStatus
            } until ($restoreTaskStatus -in $finishedStates)
            if($showLog){
                $progress = api get "/progressMonitors?taskPathVec=$($restoreTask.restoreTask.performRestoreTaskState.progressMonitorTaskPath)&excludeSubTasks=false&includeFinishedTasks=true"
                "`n-----------"
                "Log Output:"
                "-----------`n"
                $progress.resultGroupVec.taskVec.progress.eventVec | ForEach-Object{
                    "$(usecsToDate ($_.timestampSecs * 1000000))  $($_.eventMsg)" | Out-Host
                }
                ""
            }
            if($restoreTaskStatus -eq 'kSuccess'){
                Write-Host "Restore finished with status $($restoreTaskStatus.Substring(1))" -ForegroundColor Green
                if(! $singleFile){
                    exit 0
                }
            }else{
                $errorMsg = $restoreTask.restoreTask.performRestoreTaskState.base.error.errorMsg
                Write-Host "Restore finished with status $($restoreTaskStatus.Substring(1))" -ForegroundColor Yellow
                Write-Host "$errorMsg" -ForegroundColor Yellow
                if(! $singleFile){
                    exit 1
                }
            }
        }else{
            if(! $singleFile){
                exit 0
            }
        }
    }else{
        if(! $singleFile){
            exit 1
        }
    }
}

$volumeTypes = @(1, 6)

function listdir($searchPath, $dirPath, $instance, $volumeInfoCookie=$null, $volumeName=$null, $cookie=$null){
    $thisDirPath = [System.Web.HttpUtility]::UrlEncode($dirPath).Replace('%2f%2f','%2F')
    if($cookie){
        if($null -ne $volumeName){
            $dirList = api get "/vm/directoryList?$instance&useLibrarian=false&statFileEntries=false&volumeInfoCookie=$volumeInfoCookie&cookie=$cookie&volumeName=$volumeName&dirPath=$thisDirPath"
        }else{
            $dirList = api get "/vm/directoryList?$instance&useLibrarian=false&statFileEntries=false&cookie=$cookie&dirPath=$thisDirPath"
        }
    }else{
        if($null -ne $volumeName){
            $dirList = api get "/vm/directoryList?$instance&useLibrarian=false&statFileEntries=false&volumeInfoCookie=$volumeInfoCookie&volumeName=$volumeName&dirPath=$thisDirPath"
        }else{
            $dirList = api get "/vm/directoryList?$instance&useLibrarian=false&statFileEntries=false&dirPath=$thisDirPath"
        }
    }
    if($dirList.PSObject.Properties['entries'] -and $dirList.entries.Count -gt 0){
        foreach($entry in $dirList.entries | Sort-Object -Property name){
            if($entry.fullPath -eq $searchPath){
                $global:foundFile = $entry.fullPath
                break
            }
            if($entry.type -eq 'kDirectory' -and $searchPath -match $entry.fullPath -and $global:foundFile -eq $false){
                listdir "$searchPath" "$dirPath/$($entry.name)" $instance $volumeInfoCookie $volumeName
            }
        }
    }
    if($dirlist.PSObject.Properties['cookie'] -and $global:foundFile -eq $False){
        listdir "$searchPath" "$dirPath" $instance $volumeInfoCookie $volumeName $dirlist.cookie
    }
}

if($False -eq $independentRestores){
    # perform blind restore from selected version
    restore $files $doc $version $targetEntity $False
}else{
    # perform independent restores
    if($doc.versions | Where-Object numEntriesIndexed -eq 0){
        Write-Host "Crawling for files..."
    }
    foreach($file in $files){
        $fileRestored = $False
        $encodedFile = [System.Web.HttpUtility]::UrlEncode($file)
        if($doc.versions | Where-Object numEntriesIndexed -eq 0){
            # there are non indexed snapshots, try non indexed search
            $global:foundFile = $false
            foreach($version in $doc.versions){
                if($global:foundFile -eq $False){
                    $instance = "attemptNum={0}&clusterId={1}&clusterIncarnationId={2}&entityId={3}&jobId={4}&jobInstanceId={5}&jobStartTimeUsecs={6}&jobUidObjectId={7}" -f
                    $version.instanceId.attemptNum,
                    $doc.objectId.jobUid.clusterId,
                    $doc.objectId.jobUid.clusterIncarnationId,
                    $doc.objectId.entity.id,
                    $doc.objectId.jobId,
                    $version.instanceId.jobInstanceId,
                    $version.instanceId.jobStartTimeUsecs,
                    $doc.objectId.jobUid.objectId

                    # perform quick case sensitive exact match
                    $thisFile = api get "/vm/directoryList?$instance&statFileEntries=false&dirPath=$encodedFile" -quiet
                    if($thisFile){
                        $global:foundFile = $file
                    }
                    if($global:foundFile -eq $False){
                        # perform recursive directory walk (deep search)
                        $backupType = $doc.backupType
                        if($backupType -in $volumeTypes){
                            $volumeList = api get "/vm/volumeInfo?$instance&statFileEntries=false"
                            if($volumeList.PSObject.Properties['volumeInfos']){
                                $volumeInfoCookie = $volumeList.volumeInfoCookie
                                foreach($volume in $volumeList.volumeInfos | Sort-Object -Property name){
                                    $volumeName = [System.Web.HttpUtility]::UrlEncode($volume.name)
                                    listdir $file '/' $instance $volumeInfoCookie $volumeName
                                }
                            }
                        }else{
                            listdir $file '/' $instance
                        }
                    }

                }
                if($global:foundFile){
                    restore $global:foundFile $doc $version $targetEntity $True
                    $fileRestored = $True
                    break
                }
            }
            if($global:foundFile -eq $False){
                Write-Host "$file not found on server $sourceServer (or not available in the specified versions)" -ForegroundColor Yellow
            }
        }else{
            # all snapshots are indexed, use search
            if($fileRestored -eq $False){
                $fileSearch = api get "/searchfiles?entityIds=$($sourceEntity.id)&filename=$encodedFile"
                # narrow search to correct source server and file path
                if(! $fileSearch.files){
                    Write-Host "file $file not found on server $sourceServer or no versions available..." -ForegroundColor Yellow
                }else{
                    $fileSearch.files = $fileSearch.files | Where-Object {$_.fileDocument.objectId.entity.displayName -eq $sourceServer -and $_.fileDocument.fileName -eq $file}
                    # narrow by jobName
                    if($jobName){
                        $fileSearch.files = $fileSearch.files | Where-Object {$doc.objectId.jobId -eq $_.fileDocument.objectId.jobId}
                    }
                    if(! $fileSearch.files){
                        Write-Host "file $file not found on server $sourceServer protected by $jobName..." -ForegroundColor Yellow
                    }else{
                        $filedoc = $fileSearch.files[0].fileDocument
                        $encodedFile = [System.Web.HttpUtility]::UrlEncode($filedoc.filename)
                        $fileversions = api get "/file/versions?clusterId=$($doc.objectId.jobUid.clusterId)&clusterIncarnationId=$($doc.objectId.jobUid.clusterIncarnationId)&entityId=$($doc.objectId.entity.id)&filename=$encodedFile&fromObjectSnapshotsOnly=false&jobId=$($doc.objectId.jobUId.objectId)"
                        if($start){
                            $fileversions.versions = $fileversions.versions | Where-Object {$start -le (usecsToDate ($_.instanceId.jobStartTimeUsecs))}
                        }
                        if($end){
                            $fileversions.versions = $fileversions.versions | Where-Object {$end -ge (usecsToDate ($_.instanceId.jobStartTimeUsecs))}
                        }
                        if(! $fileversions.versions){
                            Write-Host "no versions available for $file" -ForegroundColor Yellow
                        }else{
                            $fileversion = $fileversions.versions[0]
                            restore $filedoc.filename $doc $fileversion $targetEntity $True
                        }
                    }
                }
            }
        }
    }
}
