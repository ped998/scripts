#!/usr/bin/env python
"""expire old snapshots"""

# usage: ./expireOldSnapshots.py -v mycluster -u admin [ -d local ] -k 30 [ -e ] [ -r ]

# import pyhesity wrapper module
from pyhesity import *
from datetime import datetime

# command line arguments
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('-v', '--vip', type=str, required=True)         # cluster to connect to
parser.add_argument('-u', '--username', type=str, required=True)    # username
parser.add_argument('-d', '--domain', type=str, default='local')    # (optional) domain - defaults to local
parser.add_argument('-i', '--useApiKey', action='store_true')       # use API key authentication
parser.add_argument('-pwd', '--password', type=str, default=None)   # optional password
parser.add_argument('-j', '--jobname', action='append', type=str)
parser.add_argument('-l', '--joblist', type=str)
parser.add_argument('-k', '--daystokeep', type=int, required=True)  # number of days of snapshots to retain
parser.add_argument('-e', '--expire', action='store_true')          # (optional) expire snapshots older than k days
parser.add_argument('-r', '--confirmreplication', action='store_true')  # (optional) confirm replication before expiring
parser.add_argument('-a', '--confirmarchive', action='store_true')  # (optional) confirm archival before expiring
parser.add_argument('-n', '--numruns', type=int, default=1000)

args = parser.parse_args()

vip = args.vip
username = args.username
domain = args.domain
password = args.password
useApiKey = args.useApiKey
jobnames = args.jobname
joblist = args.joblist
daystokeep = args.daystokeep
expire = args.expire
confirmreplication = args.confirmreplication
confirmarchive = args.confirmarchive
numruns = args.numruns

# authenticate
apiauth(vip=vip, username=username, domain=domain, password=password, useApiKey=useApiKey, noretry=True)

# get cluster Id
clusterId = api('get', 'cluster')['id']


# gather server list
def gatherList(param=None, filename=None, name='items', required=True):
    items = []
    if param is not None:
        for item in param:
            items.append(item)
    if filename is not None:
        f = open(filename, 'r')
        items += [s.strip() for s in f.readlines() if s.strip() != '']
        f.close()
    if required is True and len(items) == 0:
        print('no %s specified' % name)
        exit()
    return items


jobnames = gatherList(jobnames, joblist, name='jobs', required=False)

jobs = api('get', 'protectionJobs')

# catch invalid job names
notfoundjobs = [n for n in jobnames if n.lower() not in [j['name'].lower() for j in jobs]]
if len(notfoundjobs) > 0:
    print('Jobs not found: %s' % ', '.join(notfoundjobs))
    exit(1)

now = datetime.now()
nowUsecs = dateToUsecs(now.strftime("%Y-%m-%d %H:%M:%S"))

print("Searching for old snapshots...")

for job in sorted(jobs, key=lambda job: job['name'].lower()):
    if len(jobnames) == 0 or job['name'].lower() in [j.lower() for j in jobnames]:
        print('\n%s' % job['name'])
        endUsecs = nowUsecs
        while(1):
            runs = api('get', 'protectionRuns?jobId=%s&numRuns=%s&endTimeUsecs=%s&excludeTasks=true' % (job['id'], numruns, endUsecs))
            if len(runs) > 0:
                endUsecs = runs[-1]['backupRun']['stats']['startTimeUsecs'] - 1
            else:
                break
            for run in runs:
                startdate = usecsToDate(run['copyRun'][0]['runStartTimeUsecs'])
                startdateusecs = run['copyRun'][0]['runStartTimeUsecs']

                # check for replication
                replicated = False
                for copyRun in run['copyRun']:
                    if copyRun['target']['type'] == 'kRemote':
                        if copyRun['status'] == 'kSuccess':
                            replicated = True

                # check for archive
                archived = False
                for copyRun in run['copyRun']:
                    if copyRun['target']['type'] == 'kArchival':
                        if copyRun['status'] == 'kSuccess':
                            archived = True

                if startdateusecs < timeAgo(daystokeep, 'days') and run['backupRun']['snapshotsDeleted'] is False:
                    skip = False
                    if replicated is False and confirmreplication is True:
                        skip = True
                        print("    Skipping %s (not replicated)" % startdate)
                    elif archived is False and confirmarchive is True:
                        skip = True
                        print("    Skipping %s (not archived)" % startdate)
                    if skip is False:
                        if expire:
                            exactRun = api('get', '/backupjobruns?exactMatchStartTimeUsecs=%s&id=%s' % (startdateusecs, job['id']))
                            jobUid = exactRun[0]['backupJobRuns']['protectionRuns'][0]['backupRun']['base']['jobUid']
                            expireRun = {
                                "jobRuns":
                                    [
                                        {
                                            "expiryTimeUsecs": 0,
                                            "jobUid": {
                                                "clusterId": jobUid['clusterId'],
                                                "clusterIncarnationId": jobUid['clusterIncarnationId'],
                                                "id": jobUid['objectId'],
                                            },
                                            "runStartTimeUsecs": startdateusecs,
                                            "copyRunTargets": [
                                                {
                                                    "daysToKeep": 0,
                                                    "type": "kLocal",
                                                }
                                            ]
                                        }
                                    ]
                            }
                            print("    Expiring %s" % startdate)
                            api('put', 'protectionRuns', expireRun)
                        else:
                            print("    %s" % startdate)
