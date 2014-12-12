#!/bin/bash

set -x

# fail on any error
set -o errexit

script_path=`dirname $0`

# Note: this script is tailored to be run on dokku deployments through sshcommand

# cd to app root
cd $script_path/..
dna_path=$(pwd)/../../../dna

# configure s3cmd
bash ../yii-dna-deployment/configure-s3cmd.sh

# make php binaries available
export PATH="/app/vendor/php/bin/:$PATH"

DATETIME=$(date +"%Y-%m-%d_%H%M%S")
FOLDER=DATA-$DATA/ENV-$ENV

# dump and upload schema sql

FILEPATH=$FOLDER/$DATETIME/schema.sql

if [ -f $dna_path/db/schema.sql ] ; then
    rm $dna_path/db/schema.sql
fi
console/yii-dna-pre-release-testing-console mysqldump --dumpPath=dna/db --dumpFile=schema.sql --data=false
if [ ! -f $dna_path/db/schema.sql ] ; then
    echo "The mysql dump is not found at the expected location: db/schema.sql"
    exit 1
fi
s3cmd -v --config=/tmp/.user-generated-data.s3cfg put $dna_path/db/schema.sql "$USER_GENERATED_DATA_S3_BUCKET/$FILEPATH"

echo $FILEPATH > $dna_path/db/schema.filepath

# dump and upload data sql

FILEPATH=$FOLDER/$DATETIME/data.sql

if [ -f $dna_path/db/data.sql ] ; then
    rm $dna_path/db/data.sql
fi
console/yii-dna-pre-release-testing-console mysqldump --dumpPath=dna/db --dumpFile=data.sql --schema=false --compact=false
if [ ! -f $dna_path/db/data.sql ] ; then
    echo "The mysql dump is not found at the expected location: db/data.sql"
    exit 1
fi
s3cmd -v --config=/tmp/.user-generated-data.s3cfg put $dna_path/db/data.sql "$USER_GENERATED_DATA_S3_BUCKET/$FILEPATH"

echo $FILEPATH > $dna_path/db/data.filepath

# dump and upload user media

FOLDERPATH=$FOLDER/$DATETIME/media/

s3cmd -v --config=/tmp/.user-generated-data.s3cfg --recursive put $dna_path/db/data/p3media/ "$USER_GENERATED_DATA_S3_BUCKET/$FOLDERPATH"
echo $FOLDERPATH > $dna_path/db/media.folderpath

set +x

echo
echo "=== Upload finished ==="

DATA_FILEPATH=$(cat $dna_path/db/data.filepath)
echo "User generated db schema sql dump uploaded to $USER_GENERATED_DATA_S3_BUCKET/$DATA_FILEPATH"
echo "Set the contents of 'db/migration-base/$DATA/schema.filepath' to '$DATA_FILEPATH' in order to use this upload"

SCHEMA_FILEPATH=$(cat $dna_path/db/schema.filepath)
echo "User generated db data sql dump uploaded to $USER_GENERATED_DATA_S3_BUCKET/$SCHEMA_FILEPATH"
echo "Set the contents of 'db/migration-base/$DATA/data.filepath' to '$SCHEMA_FILEPATH' in order to use this upload"

FOLDERPATH=$(cat $dna_path/db/media.folderpath)
echo "User media uploaded to $USER_GENERATED_DATA_S3_BUCKET/$FOLDERPATH"
echo "Set the contents of 'db/migration-base/$DATA/media.folderpath' to '$FOLDERPATH' in order to use this upload"
echo
echo "# Commands to run locally in order to set the refs to point to this user data (optional - do this if your data set is meant to be the base of future production deployments)"
echo "echo '$SCHEMA_FILEPATH' > dna/db/migration-base/$DATA/schema.filepath"
echo "echo '$DATA_FILEPATH' > dna/db/migration-base/$DATA/data.filepath"
echo "echo '$FOLDERPATH' > dna/db/migration-base/$DATA/media.folderpath"

exit 0