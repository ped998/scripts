# Add Whitelist Entries to a View using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script adds whitelist entries to a Cohesity view.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Begin download commands
$scriptName = 'viewAddWhiteListEntries'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End download commands
```

## Components

* viewAddWhiteListEntries.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

```powershell
#example
./viewAddWhiteListEntries.ps1 -vip mycluster `
                              -username myusername `
                              -domain mydomain.net `
                              -viewName myview `
                              -ips 192.168.1.7/32, 192.168.2.0/24 `
                              -readOnly
                              -rootSquash
#end example
```

## Parameters

* -vip: Cohesity cluster to connect to
* -username: Cohesity username
* -domain: (optional) Active Directory domain (defaults to 'local')
* -tenantId: (optional) tenant to impersonate
* -viewName: name of new view to create
* -ips: (optional) cidrs to add, examples: 192.168.1.3/32, 192.168.2.0/24 (comma separated)
* -ipList: (optional) text file of cidrs to add (one per line)
* -readOnly: (optional) readWrite if omitted
* -rootSquash: (optional) enable root squash
* -allSquash: (optional) enable all squash
