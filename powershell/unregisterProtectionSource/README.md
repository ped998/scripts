# Unregister a Protection Source using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script unregisters a protection source.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'unregisterProtectionSource'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components

* unregisterProtectionSource.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

```powershell
./unregisterProtectionSource.ps1 -vip mycluster `
                                 -username myusername `
                                 -domain mydomain.net `
                                 -sourceName mysource.mydomain.net
```

Note: server names must exactly match what is shown in protection sources.

## Parameters

* -vip: Cohesity cluster to connect to
* -username: Cohesity username (e.g. admin)
* -domain: (optional) Active Directory domain (defaults to 'local')
* -useApiKey: (optional) use API Key for authentication
* -password: (optional) will use stored password by default
* -sourceName: (optional) comma separated list of source names to unregister
* -sourceList: (optional) text file containing source names to unregister
