# KBase Hadoop YARN Dockerfile

A very simplistic (for now) docker set up for YARN nodes. Configuration is minimal

## Notes on YARN vs. Spark standalone for resource management

* YARN requires a distributed file system for making jars accessible to the worker nodes
  from the Spark node, unlike Spark standalone
  * Current setup assumes we're not using HDFS but rather s3 for jar distribution
    * s3 has some drawbacks compared to HDFS
      * https://hadoop.apache.org/docs/stable/hadoop-aws/tools/hadoop-aws/index.html#Warnings
* The main reason for trying YARN is that it has a fair share scheduler
  * If we're mostly interacting with Spark via `SparkSession` in a notebook or in a spark shell
    it's not clear how much benefit fair share will give us
  * Will only come into play if enough people are using the cluster at the same time that their
    drivers have reserved all of a cluster's resources
  * If that's the case then when more people start drivers they'll be queued until one of the
    other users ends their session. Fair share will determine the order of the queue rather than
    FIFO for the Spark master
  * If only KBase staff are using the Spark cluster as has been discussed, fair share doesn't
    really seem necessary and a Slack message asking people to shut down unused sessions could
    suffice
  * If we're submitting jobs with `spark-submit` or its programmatic equivalent then fair
    share seems more worthwhile
* Using YARN means we have an additional container to maintain, whereas with the Bitnami Spark
  container, the Spark notebook nodes and master / worker nodes are based on the same image
  * We may want to separate them in the future?
* With the current setup, all job data in the YARN staging directory
  (transmitted files, temp files, etc) is writeable by all users since it's in the same bucket.
  If only KBase staff access the cluster this is probably ok, but not if KBase users do so.
  * Not sure how to implement a system with s3 where each user's files are protected
    * In KBase we do this with a service that abstracts s3 away from the user
* It seems to the author that the spark / hadoop ecosystem is designed for use by an interest's
  employees, not its users

## OS notes:

* The Hadoop containers don't seem to start correctly on Mac machines. Ubuntu linux works
  normally.

## Hadoop container notes:

* **namenode**: The HDFS metadata node, contains the filesystem metadata.
* **datanode**: The HDFS data node, contains the file data.
* **yarn-resourcemanager**: The YARN resource / job manager. Equivalent to the Spark master.
* **yarn-nodemanager**: The YARN node / application manager. Equivalent to a Spark worker.

## Testing

To test, `exec` into the spark container and run the commands for the setup you wish to test.

```
docker exec -it spark-container bash
```

### With HDFS

```
./bin/spark-submit --class org.apache.spark.examples.SparkPi --master yarn --conf spark.hadoop.yarn.resourcemanager.hostname=yarn-resourcemanager --conf spark.hadoop.yarn.resourcemanager.address=yarn-resourcemanager:8032 --deploy-mode client examples/jars/spark-examples_2.12-3.5.1.jar 10
```

### With S3

#### Java

```
./bin/spark-submit --class org.apache.spark.examples.SparkPi --master yarn --conf spark.hadoop.yarn.resourcemanager.hostname=yarn-resourcemanager --conf spark.hadoop.yarn.resourcemanager.address=yarn-resourcemanager:8032 --conf spark.hadoop.fs.s3a.endpoint=http://minio:9002 --conf spark.hadoop.fs.s3a.access.key=minio --conf spark.hadoop.fs.s3a.secret.key=minio123 --conf spark.hadoop.fs.s3a.path.style.access=true --conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem --conf spark.yarn.stagingDir=s3a://yarn --deploy-mode client examples/jars/spark-examples_2.12-3.5.1.jar 10
```

#### Python

```
./bin/spark-submit --master yarn --conf spark.hadoop.yarn.resourcemanager.hostname=yarn-resourcemanager --conf spark.hadoop.yarn.resourcemanager.address=yarn-resourcemanager:8032 --conf spark.hadoop.fs.s3a.endpoint=http://minio:9002 --conf spark.hadoop.fs.s3a.access.key=minio --conf spark.hadoop.fs.s3a.secret.key=minio123 --conf spark.hadoop.fs.s3a.path.style.access=true --conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem --conf spark.yarn.stagingDir=s3a://yarn --deploy-mode client examples/src/main/python/pi.py 10
```

## TODO

* install python on YARN nodes
* Switch to fair scheduler for YARN

