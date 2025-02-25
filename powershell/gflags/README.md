# Get Set Clear and Import GFlags using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script gets, set,s clears and imports gflags.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'gflags'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components

* gflags.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place the files in a folder together and run the main script like so:

To get the current list of gflags from a cluster (and save the list to a file gflags-clustername.csv):

```powershell
./gflags.ps1 -vip mycluster `
             -username myusername `
             -domain mydomain.net `
```

To set a gflag:

```powershell
./gflags.ps1 -vip mycluster `
             -username myusername `
             -domain mydomain.net `
             -set `
             -servicename myservice `
             -flagname myflag `
             -flagvalue 1 `
             -reason 'tweaking something'
             -restart
```

To import a list of gflags (csv file must be in the format 'serviceName,flagName,flagValue,reason'):

```powershell
./gflags.ps1 -vip mycluster `
             -username myusername `
             -domain mydomain.net `
             -import gflags-anotherCluster.csv
             -restart
```

## Parameters

* -vip: Cohesity cluster to connect to
* -username: Cohesity username (e.g. admin)
* -domain: (optional) Active Directory domain (defaults to 'local')
* -import: (optional) CSV file to import
* -servicename: (optional) service name (required for -set)
* -flagname: (optional) flag name (required for -set)
* -flagvalue: (optional) flag value (required for -set)
* -reason: (optional) reason (required for -set)
* -effectiveNow: (optional) make gflag effective immediately on all nodes
* -restart (optional) restart services to make gflags effective immediately
* -clear (optional) clear a gflag
