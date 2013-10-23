#!/bin/bash

# This script does the following
# - update project from repository
# - build the project (dev configuration)
# - create a snapshot
# - deploy this snapshot to integration
# - create script to deploy this snapshot to integration (for repeated task)
# - create script to deploy this snapshot to production

PRODFILE=`pwd`/geoadmin3prod.sh
INTWITHSNAPFILE=`pwd`/geoadmin3integrationwithsnapshot.sh
PROJECTPATH=/var/www/vhosts/mf-geoadmin3/private/geoadmin/
SNAPSHOTPATH=/var/www/vhosts/mf-geoadmin3/private/snapshots/`date '+%Y%m%d%H%M'`

#build latest version
cd $PROJECTPATH
git checkout master
git pull
source rc_dev
make cleanall all

#create snapshot
sudo -u deploy deploy -c deploy/deploy.cfg $SNAPSHOTPATH

#deploy this snapshot to integration
sudo -u deploy deploy -r deploy/deploy.cfg ab $SNAPSHOTPATH

#create integration deploy script with this snapshot
echo "#!/bin/bash" > $INTWITHSNAPFILE
echo "cd " $PROJECTPATH >> $INTWITHSNAPFILE
echo "sudo -u deploy deploy -r deploy/deploy.cfg ab "$SNAPSHOTPATH >> $INTWITHSNAPFILE
chmod 777 $INTWITHSNAPFILE
echo $INTWITHSNAPFILE " created."

#create production deploy script with this snapshot
echo "#!/bin/bash" > $PRODFILE
echo "cd " $PROJECTPATH >> $PRODFILE
echo "sudo -u deploy deploy -r deploy/deploy.cfg prod "$SNAPSHOTPATH >> $PRODFILE
chmod 777 $PRODFILE
echo $PRODFILE " created."
