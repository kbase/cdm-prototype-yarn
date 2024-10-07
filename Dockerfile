FROM apache/hadoop:3.4.0 as hadoop_image

FROM ubuntu:24.04

# The steps here were partially determined by looking at
# docker history --no-trunc apache/hadoop:3.3.6

ENV HADOOP_VER=3.3.6

###
# Install python, java & other necessary binaries
###

# ubuntu 24.04 LTS noble only has python3.12
# the autoremove step is to remove the many dependencies, including python3.12, of SPC
RUN apt update -y \
    && apt install -y software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt update -y \
    && apt install -y python3.11 openjdk-8-jre curl \
    && apt autoremove -y --purge software-properties-common python3.12 \
    && rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/python3.11 /usr/bin/python3

ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre/

###
# Copy startup scripts from the hadoop image
###

# No idea where the source for this stuff lives
COPY --from=hadoop_image /opt/envtoconf.py /opt/envtoconf.py
COPY --from=hadoop_image /opt/transformation.py /opt/transformation.py
COPY --from=hadoop_image /opt/starter.sh /opt/starter.sh

###
# Move sudo command from /opt/starter.sh here
###

# Comment from script: To avoid docker volume permission problems
RUN mkdir -p /data && chmod o+rwx /data

# remove the line from the script. There are other sudos in `if` blocks, cross that bridge later
RUN sed -i 's$sudo chmod o+rwx /data$# sudo chmod o+rwx /data$' /opt/starter.sh

###
# Set up hadoop user
###

RUN groupadd --gid 1001 hadoop \
    && useradd --uid 1001 hadoop --gid 1001 --home /opt/hadoop \
    && chown -R hadoop:hadoop /opt

USER hadoop

###
# Install hadoop
###

WORKDIR /opt

RUN curl -LSs -o hadoop.tgz https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VER/hadoop-$HADOOP_VER.tar.gz \
    && tar zxf hadoop.tgz \
    && rm hadoop.tgz \
    && mv hadoop* hadoop \
    && rm -r /opt/hadoop/share/doc  # 0.5GB of docs

USER root
RUN mkdir -p /var/log/hadoop && chmod 1777 /var/log/hadoop
USER hadoop

ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
ENV HADOOP_LOG_DIR=/var/log/hadoop
ENV PATH=$PATH:/opt/hadoop/bin

###
# Hack the environmental config system because it's annoying
###

# This is pretty fragile. If the configuration starts breaking this is one place to start debugging

# The reason for this line is that hadoop configuration by env var is the easiest way to handle the
# config, since it means you don't need configuration templates that need to be updated
# every time you want to add a new config var. However, the env var name has to include the
# file name, which contains a hyphen, and key name, which usually includes periods. Both are
# illegal in most shells, so `export` commands fail. Interestingly setting those same env vars
# in a Dockerfile or docker compose works and they end up in the environment, punctuation and all.

# This hack removes some code that blanks the raw configuration files when the script is run
# so that we can preload them with the environment we want.
RUN sed -i -z 's#if name not in self\.configurables\.keys.*myfile.write("")##' /opt/envtoconf.py

RUN sed -i 's#/usr/bin/python#/usr/bin/python3#' /opt/envtoconf.py

# This is a hack to get the hadoop environment configuration code to run on the raw configuration
# files regardless of whether there's a config var set that triggers that file
ENV YARN-SITE.XML_fakekey=hack_to_get_config_system_to_process_the_raw_config_file
ENV CORE-SITE.XML_fakekey=hack_to_get_config_system_to_process_the_raw_config_file
ENV HDFS-SITE.XML_fakekey=hack_to_get_config_system_to_process_the_raw_config_file

###
# Enable the fair scheduler
###

# There are lots of config options, see
# https://hadoop.apache.org/docs/stable/hadoop-yarn/hadoop-yarn-site/FairScheduler.html
ENV YARN-SITE.XML_yarn.resourcemanager.scheduler.class=org.apache.hadoop.yarn.server.resourcemanager.scheduler.fair.FairScheduler
ENV YARN-SITE.XML_yarn.scheduler.fair.allocation.file=/opt/hadoop/fair-scheduler.xml
COPY ./conf/yarn/fair-scheduler.xml /opt/hadoop/fair-scheduler.xml

###
# Enable s3
###

ENV HADOOP_OPTIONAL_TOOLS=hadoop-aws

###
# Enable hardware capability detection (memory, CPU)
###

ENV YARN-SITE.XML_yarn.nodemanager.resource.detect-hardware-capabilities=true
ENV YARN-SITE.XML_yarn.nodemanager.resource.count-logical-processors-as-cores=true

# Not sure if yarn.nodemanager.resource.pcores-vcores-multiplier needs to be set, seems like
# the yarn code should be able to figure it out

# Currently resource limits are used only to determine whether to add a job to a node based on the
# requested resources. Once the job is running it might take up more resources than requested.
# If we find this to be a problem we can look into YARN's ability to kill jobs overusing resources:
# https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/NodeManagerCGroupsMemory.html

###
# Finish the build
###

COPY ./scripts/ /opt/scripts/
USER root
RUN chmod a+x /opt/scripts/*.sh
USER hadoop

WORKDIR /opt/hadoop

ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
