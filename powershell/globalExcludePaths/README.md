# Add Global Exclude Paths using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This PowerShell script adds global exclude paths to file-based protection groups.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'globalExcludePaths'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components

* globalExcludePaths.ps1: the main PowerShell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place all files in a folder together and run the main script like so:

```powershell
./globalExcludePaths.ps1 -vip mycluster `
                         -username myusername `
                         -domain mydomain.net `
                         -jobName 'File-based Linux Job' `
                         -exclusions /var/log, /home/cohesityagent
```

## Parameters

* -vip: name or IP of Cohesity cluster
* -username: name of user to connect to Cohesity
* -domain: (optional) your AD domain (defaults to local)
* -jobName: (optional) one or more protection jobs (comma separated)
* -jobList: (optional) text file of job names (one per line)
* -exclusions: (optional) one or more exclusion paths (comma separated)
* -exclusionList: (optional) a text file of exclusion paths (one per line)
* -replaceRules: if omitted, inclusions/exclusions are appended to existing server rules (if any)
