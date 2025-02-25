#!/usr/bin/env python
"""backed up files list for python"""

# version 2022.05.11

# usage: ./backedUpFileList.py -v mycluster \
#                              -u myuser \
#                              -d mydomain.net \
#                              -s server1.mydomain.net \
#                              -j myjob \
#                              -f '2020-06-29 12:00:00'

# import pyhesity wrapper module
from pyhesity import *
from datetime import datetime
import codecs
import sys
import argparse
if sys.version_info.major >= 3 and sys.version_info.minor >= 5:
    from urllib.parse import quote_plus
else:
    from urllib import quote_plus

# command line arguments
parser = argparse.ArgumentParser()
parser.add_argument('-v', '--vip', type=str, required=True)           # cluster to connect to
parser.add_argument('-u', '--username', type=str, default='helios')   # username
parser.add_argument('-d', '--domain', type=str, default='local')      # domain - defaults to local
parser.add_argument('-i', '--useApiKey', action='store_true')         # use API key authentication
parser.add_argument('-pwd', '--password', type=str, default=None)     # optional password
parser.add_argument('-s', '--sourceserver', type=str, required=True)  # name of source server
parser.add_argument('-j', '--jobname', type=str, required=True)       # narrow search by job name
parser.add_argument('-l', '--showversions', action='store_true')      # show available snapshots
parser.add_argument('-k', '--listfiles', action='store_true')         # show available snapshots
parser.add_argument('-t', '--start', type=str, default=None)          # show snapshots after date
parser.add_argument('-e', '--end', type=str, default=None)            # show snapshots before date
parser.add_argument('-r', '--runid', type=int, default=None)          # choose specific job run id
parser.add_argument('-f', '--filedate', type=str, default=None)       # date to restore from
parser.add_argument('-p', '--startpath', type=str, default='/')       # date to restore from
parser.add_argument('-n', '--noindex', action='store_true')           # do not use librarian
parser.add_argument('-ss', '--showstats', action='store_true')           # do not use librarian

args = parser.parse_args()

vip = args.vip
username = args.username
domain = args.domain
password = args.password
useApiKey = args.useApiKey
sourceserver = args.sourceserver
jobname = args.jobname
showversions = args.showversions
start = args.start
end = args.end
runid = args.runid
filedate = args.filedate
listfiles = args.listfiles
startpath = args.startpath
noindex = args.noindex
showstats = args.showstats

if showstats is True:
    statfile = True
else:
    statfile = False

if noindex is True:
    useLibrarian = False
else:
    useLibrarian = True

# authenticate
apiauth(vip=vip, username=username, domain=domain, password=password, useApiKey=useApiKey)


def listdir(dirPath, instance, f, volumeInfoCookie=None, volumeName=None, cookie=None):
    thisDirPath = quote_plus(dirPath).replace('%2F%2F', '%2F')
    if cookie is not None:
        if volumeName is not None:
            dirList = api('get', '/vm/directoryList?%s&useLibrarian=%s&statFileEntries=%s&dirPath=%s&volumeInfoCookie=%s&volumeName=%s&cookie=%s' % (instance, useLibrarian, statfile, thisDirPath, volumeInfoCookie, volumeName, cookie))
        else:
            dirList = api('get', '/vm/directoryList?%s&useLibrarian=%s&statFileEntries=%s&dirPath=%s&cookie=%s' % (instance, useLibrarian, statfile, thisDirPath, cookie))
    else:
        if volumeName is not None:
            dirList = api('get', '/vm/directoryList?%s&useLibrarian=%s&statFileEntries=%s&dirPath=%s&volumeInfoCookie=%s&volumeName=%s' % (instance, useLibrarian, statfile, thisDirPath, volumeInfoCookie, volumeName))
        else:
            dirList = api('get', '/vm/directoryList?%s&useLibrarian=%s&statFileEntries=%s&dirPath=%s' % (instance, useLibrarian, statfile, thisDirPath))
    if dirList and 'entries' in dirList:
        for entry in sorted(dirList['entries'], key=lambda e: e['name']):
            if entry['type'] == 'kDirectory':
                listdir('%s/%s' % (dirPath, entry['name']), instance, f, volumeInfoCookie, volumeName)
            else:
                if statfile is True:
                    filesize = entry['fstatInfo']['size']
                    mtime = usecsToDate(entry['fstatInfo']['mtimeUsecs'])
                    print('%s (%s) [%s bytes]' % (entry['fullPath'], mtime, filesize))
                    f.write('%s (%s) [%s bytes]\n' % (entry['fullPath'], mtime, filesize))
                else:
                    print('%s' % entry['fullPath'])
                    f.write('%s\n' % entry['fullPath'])
    if dirList and 'cookie' in dirList:
        listdir('%s' % dirPath, instance, f, volumeInfoCookie, volumeName, dirList['cookie'])


def showFiles(doc, version):
    instance = ("attemptNum=%s&clusterId=%s&clusterIncarnationId=%s&entityId=%s&jobId=%s&jobInstanceId=%s&jobStartTimeUsecs=%s&jobUidObjectId=%s" %
                (version['instanceId']['attemptNum'],
                    doc['objectId']['jobUid']['clusterId'],
                    doc['objectId']['jobUid']['clusterIncarnationId'],
                    doc['objectId']['entity']['id'],
                    doc['objectId']['jobId'],
                    version['instanceId']['jobInstanceId'],
                    version['instanceId']['jobStartTimeUsecs'],
                    doc['objectId']['jobUid']['objectId']))

    fileDateString = datetime.strptime(usecsToDate(version['instanceId']['jobStartTimeUsecs']), '%Y-%m-%d %H:%M:%S').strftime('%Y-%m-%d_%H-%M-%S')

    f = codecs.open('backedUpFiles-%s-%s-%s.txt' % (sourceserver, version['instanceId']['jobInstanceId'], fileDateString), 'w', 'utf-8')

    volumeTypes = [1, 6]
    backupType = doc['backupType']
    if backupType in volumeTypes:
        volumeList = api('get', '/vm/volumeInfo?%s&statFileEntries=%s' % (instance, statfile))
        if 'volumeInfos' in volumeList:
            volumeInfoCookie = volumeList['volumeInfoCookie']
            for volume in sorted(volumeList['volumeInfos'], key=lambda v: v['name']):
                volumeName = quote_plus(volume['name'])
                listdir(startpath, instance, f, volumeInfoCookie, volumeName)
    else:
        listdir(startpath, instance, f)

    f.close()


search = api('get', '/searchvms?entityTypes=kView&entityTypes=kAcropolis&entityTypes=kAWS&entityTypes=kAWSNative&entityTypes=kAWSSnapshotManager&entityTypes=kAzure&entityTypes=kAzureNative&entityTypes=kFlashBlade&entityTypes=kGCP&entityTypes=kGenericNas&entityTypes=kHyperV&entityTypes=kHyperVVSS&entityTypes=kIsilon&entityTypes=kKVM&entityTypes=kNetapp&entityTypes=kPhysical&entityTypes=kVMware&vmName=%s' % sourceserver)

if 'vms' not in search:
    print('no backups found for %s' % sourceserver)
    exit(1)

searchResults = [vm for vm in search['vms'] if vm['vmDocument']['objectName'].lower() == sourceserver.lower()]

if len(searchResults) == 0:
    print('no backups found for %s' % sourceserver)
    exit(1)

altJobName = 'old name: %s' % jobname.lower()
altJobName2 = '%s (old name' % jobname.lower()
searchResults = [vm for vm in searchResults if vm['vmDocument']['jobName'].lower() == jobname.lower() or altJobName in vm['vmDocument']['jobName'].lower() or altJobName2 in vm['vmDocument']['jobName'].lower()]

if len(searchResults) == 0:
    print('%s not protected by %s' % (sourceserver, jobname))
    exit(1)

searchResults = [r for r in searchResults if 'versions' in r['vmDocument'] and len(r['vmDocument']['versions']) > 0]

if len(searchResults) == 0:
    print('No backups available for %s in %s' % (sourceserver, jobname))
    exit(1)

allVersions = []
for searchResult in searchResults:
    for version in searchResult['vmDocument']['versions']:
        version['doc'] = searchResult['vmDocument']
        allVersions.append(version)
allVersions = sorted(allVersions, key=lambda r: r['snapshotTimestampUsecs'], reverse=True)

# searchResult = sorted(searchResults, key=lambda result: result['vmDocument']['versions'][0]['snapshotTimestampUsecs'], reverse=True)[0]

# doc = searchResult['vmDocument']

if showversions or start is not None or end is not None or listfiles:
    if start is not None:
        startusecs = dateToUsecs(start)
        allVersions = [v for v in allVersions if startusecs <= v['snapshotTimestampUsecs']]
    if end is not None:
        endusecs = dateToUsecs(end)
        allVersions = [v for v in allVersions if endusecs >= v['snapshotTimestampUsecs']]
    if listfiles:
        for version in allVersions:
            print("\n==============================")
            print("   runId: %s" % version['instanceId']['jobInstanceId'])
            print(" runDate: %s" % usecsToDate(version['instanceId']['jobStartTimeUsecs']))
            print("==============================\n")
            showFiles(version['doc'], version)
    else:
        print('%10s  %s' % ('runId', 'runDate'))
        print('%10s  %s' % ('-----', '-------'))
        for version in allVersions:
            print('%10d  %s' % (version['instanceId']['jobInstanceId'], usecsToDate(version['instanceId']['jobStartTimeUsecs'])))
    exit(0)

# select version
if runid is not None:
    # select version with matching runId
    versions = [v for v in allVersions if runid == v['instanceId']['jobInstanceId']]
    if len(versions) == 0:
        print('Run ID not found')
        exit(1)
    else:
        version = versions[0]
        showFiles(version['doc'], version)
elif filedate is not None:
    # select version just after requested date
    filedateusecs = dateToUsecs(filedate)
    versions = [v for v in allVersions if filedateusecs <= v['snapshotTimestampUsecs']]
    if versions:
        version = versions[-1]
        showFiles(version['doc'], version)
    else:
        print('No backups from the specified date')
        exit(1)
else:
    # just use latest version
    version = allVersions[0]
    showFiles(version['doc'], version)
