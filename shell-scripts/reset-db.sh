#!/bin/bash

#
# Resets the database to the current DATA profile's migration base, then runs migrations
#
# Parameters:
#    --force-s3-sync    will fetch user generated data from S3 despite there being existing files
#

# Uncomment to see all variables used in this sciprt
#set -x;

script_path=`dirname $0`

if [ "$connectionID" == "" ]; then

    echo "The environment variable connectionID needs to be set"
    exit 1

fi

# fail on any error
set -o errexit

LOG=/tmp/reset-db.sh.log

echo "* Reset db started. Logging to $LOG" | tee -a $LOG

cd $script_path/..
dna_path=$(pwd)/../../../dna

# make app config available as shell variables
php $dna_path/../vendor/neam/php-app-config/export.php | tee /tmp/php-app-config.sh >> $LOG
source /tmp/php-app-config.sh

# to see which commands are executed
# set -x;

if [ "$DATA" != "clean-db" ]; then

    echo "* Fetching the user-generated data associated with this commit" | tee -a $LOG

    shell-scripts/fetch-user-generated-data.sh $1 >> $LOG

fi

# Clear current data
console/yii-dna-pre-release-testing-console databaseschema --connectionID=$connectionID dropAllTablesAndViews --verbose=0 >> $LOG
rm -rf $dna_path/db/data/p3media/*

if [ "$connectionID" == "dbTest" ]; then
    export DATABASE_HOST=$TEST_DB_HOST
    export DATABASE_PORT=$TEST_DB_PORT
    export DATABASE_USER=$TEST_DB_USER
    export DATABASE_PASSWORD=$TEST_DB_PASSWORD
    export DATABASE_NAME=$TEST_DB_NAME
fi

if [ "$DATA" != "clean-db" ]; then

    echo "* Loading the user-generated data associated with this commit" | tee -a $LOG

    # load mysql dumps
    mysql -A --host=$DATABASE_HOST --port=$DATABASE_PORT --user=$DATABASE_USER --password=$DATABASE_PASSWORD $DATABASE_NAME < $dna_path/db/migration-base/$DATA/schema.sql
    mysql -A --host=$DATABASE_HOST --port=$DATABASE_PORT --user=$DATABASE_USER --password=$DATABASE_PASSWORD $DATABASE_NAME < $dna_path/db/migration-base/$DATA/data.sql

    # copy the downloaded data to the p3media folder
    SOURCE_PATH=$dna_path/db/migration-base/$DATA/media
    if [ "$(ls -A $SOURCE_PATH/)" ]; then
        cp -r $SOURCE_PATH/* $dna_path/db/data/p3media/
    else
        echo "Warning: No media files found" | tee -a $LOG
    fi

    # make downloaded media directories owned and writable by the web server
    chown -R nobody: $dna_path/db/data/p3media/

fi

if [ "$DATA" == "clean-db" ]; then

    echo "* Loading the clean-db data associated with this commit" | tee -a $LOG

    # load mysql dumps
    mysql -A --host=$DATABASE_HOST --port=$DATABASE_PORT --user=$DATABASE_USER --password=$DATABASE_PASSWORD $DATABASE_NAME < $dna_path/db/migration-base/clean-db/schema.sql
    mysql -A --host=$DATABASE_HOST --port=$DATABASE_PORT --user=$DATABASE_USER --password=$DATABASE_PASSWORD $DATABASE_NAME < $dna_path/db/migration-base/clean-db/data.sql

fi

if [ "$DATA" == "" ]; then

    echo "The environment variable DATA needs to be set" | tee -a $LOG
    exit 1

fi

echo "* Loading fixtures" | tee -a $LOG
console/yii-dna-pre-release-testing-console fixture --connectionID=$connectionID load >> $LOG

echo "* Running migrations" | tee -a $LOG
console/yii-dna-pre-release-testing-console migrate --connectionID=$connectionID --interactive=0 >> $LOG

echo "* Generating database views" | tee -a $LOG
console/yii-dna-pre-release-testing-console databaseviewgenerator --connectionID=$connectionID item >> $LOG
console/yii-dna-pre-release-testing-console databaseviewgenerator --connectionID=$connectionID itemTable >> $LOG

if [ "$connectionID" != "dbTest" ]; then

    echo "* Updating current schema dumps" | tee -a $LOG
    shell-scripts/update-current-schema-dumps.sh >> $LOG

fi

echo "* Reset db finished. Log is found at $LOG"
echo
echo "    To view log:"
echo "    cat $LOG | less";
echo
#echo "To view errors in log:"
#echo "cat $LOG | grep rror | less";