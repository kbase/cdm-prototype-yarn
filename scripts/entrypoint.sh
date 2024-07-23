#!/bin/sh

# Setup S3 config and translate from the env var names we've chosen in the KBase spark
# cluster to Hadoop-ese
echo "fs.s3a.endpoint: $MINIO_URL" >> /opt/hadoop/etc/hadoop/core-site.xml.raw
export AWS_ACCESS_KEY_ID=$MINIO_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$MINIO_SECRET_KEY
echo "fs.s3a.path.style.access: true" >> /opt/hadoop/etc/hadoop/core-site.xml.raw

# Set up nodemanager

if [[ $YARN_MODE == "nodemanager" ]]; then
    echo "yarn.resourcemanager.hostname: $YARN_RESOURCEMANAGER_HOSTNAME" >> /opt/hadoop/etc/hadoop/yarn-site.xml.raw
fi

/opt/starter.sh yarn $YARN_MODE
