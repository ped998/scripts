# Restore a Files from Cohesity backups using Python

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This python script restores files from a Cohesity physical server backup.

## Components

* restoreFiles.py: the main python script
* pyhesity.py: the Cohesity REST API helper module

You can download the scripts using the following commands:

```bash
# download commands
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/restoreFiles/restoreFiles.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
chmod +x restoreFiles.py
# end download commands
```

Place both files in a folder together and run the main script like so:

```bash
# example
./restoreFiles.py -v mycluster \
                  -u myusername \
                  -d mydomain .net \
                  -s server1.mydomain.net \
                  -t server2.mydomain.net \
                  -n /home/myusername/file1 \
                  -n /home/myusername/file2 \
                  -p /tmp/restoretest/ \
                  -f '2020-04-18 18:00:00' \
                  -w
# end example
```

```text
Connected!
Restoring Files...
Restore finished with status kSuccess
```

## Parameters

* -v, --vip: (optional) DNS or IP of the Cohesity cluster to connect to (defaults to helios.cohesity.com)
* -u, --username: (optional) username to authenticate to Cohesity cluster (defaults to 'helios')
* -d, --domain: (optional) domain of username, defaults to local
* -i, --useApiKey: (optional) use API key for authentication
* -pwd, --password: (optional) password or API key (will prompt or use stored password if omitted)
* -c, --clustername: (optional) Helios connected cluster to connect to (when connected to Helios)
* -s, --sourceserver: name of source server (repeat for multiple)
* -t, --targetserver: (optional) name of target server (defaults to source server [0])
* -n, --filename: (optional) path of file to recover (repeat parameter for multiple files)
* -f, --filelist: (optional) text file containing multiple files to restore
* -p, --restorepath: (optional) path to restore files on target server (defaults to original location)
* -r, --runid: (optional) select backup version with this job run ID
* -b, --start: (optional) oldest backup date to restore files from (e.g. '2020-04-18 18:00:00')
* -e, --end: (optional) newest backup date to restore files from (e.g. '2020-04-20 18:00:00')
* -l, --latest: (optional) use latest backup date to restore files from
* -o, --newonly: (optional) only restore if there is a new point in time to restore
* -w, --wait: (optional) wait for completion and report status
* -k, --taskname: (optional) set name of recovery task

## Backup Versions

By default, the script will search for each file and restore it from the newest version available for that file. You can narrow the date range that will be searched by using the --start and --end parameters.

Using the --runid or --latest parameters will cause the script to try to restore all the requested files at once (in one recovery task), from one backup version.

## File Names and Paths

File names must be specified as absolute paths like:

* Linux: /home/myusername/file1
* Windows: c:\Users\MyUserName\Documents\File1 or C/Users/MyUserName/Documents/File1

## The Python Helper Module - pyhesity.py

Please find more info on the pyhesity module here: <https://github.com/bseltz-cohesity/scripts/tree/master/python>
