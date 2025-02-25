### usage: ./new-PhysicalSource.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -server win2016.mydomain.com

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #Cohesity cluster to connect to
    [Parameter(Mandatory = $True)][string]$username, #Cohesity username
    [Parameter()][string]$domain = 'local', #Cohesity user domain name
    [Parameter()][array]$sourceName, #Server to add as physical source
    [Parameter()][string]$sourceList
)

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

$sourceNames = @(gatherList -Param $sourceName -FilePath $sourceList -Name 'sources' -Required $True)

### source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

### authenticate
apiauth -vip $vip -username $username -domain $domain -quiet

$registeredSources = api get "protectionSources/registrationInfo?includeEntityPermissionInfo=true&includeApplicationsTreeInfo=false"

foreach($source in $sourceNames){
    $registeredSource = $registeredSources.rootNodes | Where-Object { $_.rootNode.name -eq $source }
    if($registeredSource){
        "Unregistering $source..."
        $null = api delete protectionSources/$($registeredSource.rootNode.id)
    }else{
        "$source not registered"
    }
}
