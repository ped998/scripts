# List Archive Tasks Using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This PowerShell script lists the currently active archive tasks and outputs to a CSV.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'archiveQueueV2'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components

* archiveQueueV2.ps1: the main python script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

```powershell
./archiveQueueV2.ps1 -vip mycluster -username myusername -domain mydomain.net
```

## Parameters

* -vip: the Cohesity cluster to connect to
* -username: the cohesity user to login with
* -domain: (optional) domain of the Cohesity user (defaults to local)
* -jobName: (optional) job name to include
* -jobList: (optional) text file of job names to include (one per line)
* -showFinished: (optional) show finished archive tasks
* -daysBack: (optional) only applicable when using -showFinished
* -cancelAll: (optional) cancel all archive tasks
* -cancelOutdated: (optional) cancel archive tasks that should be expired anyway
* -cancelQueued: (optional) cancel archive tasks that haven't moved any data yet
* -numRuns: (optional) number of runs to request per API call (defaults to 100)
* -unit: (optional) MiB, GiB or TiB (default is MiB)
