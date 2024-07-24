FROM apache/hadoop:3.3.6

USER root

# It might be worth making our own Dockerfile from scratch given the version of Centos is from
# Dec 2018. docker history --no-trunc apache/hadoop:3.3.6 might help

# Note that if the version of CentOS in the base image changes, this file may need updates to
# match the version, or ideally can be removed.
# https://serverfault.com/a/1161904
COPY ./conf/yum/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo

RUN mkdir -p /opt/temp
WORKDIR /opt/temp

# Installing openssl: https://gist.github.com/Bill-tran/5e2ab062a9028bf693c934146249e68c
# Python: https://computingforgeeks.com/install-python-3-on-centos-rhel-7/
# python version needs to match the version from https://github.com/kbase/cdm-jupyterhub/

# do this in one command to minimize layer sizes
RUN yum clean all \
    && yum makecache fast \
    && yum -y update \
    && yum -y install epel-release \
    && yum -y install wget make cmake gcc bzip2-devel libffi-devel zlib-devel perl-core pcre-devel \
    && yum -y groupinstall "Development Tools" \
    && wget https://openssl.org/source/openssl-3.3.1.tar.gz \
    && tar -xzvf openssl-3.3.1.tar.gz \
    && cd openssl-3.3.1 \
    && ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib no-shared zlib-dynamic \
    && make \
    && make install \
    && cd .. \
    && wget https://www.python.org/ftp/python/3.11.9/Python-3.11.9.tgz \
    && tar xvf Python-3.11.9.tgz \
    && cd Python-3.11.9 \
    && LDFLAGS="${LDFLAGS} -Wl,-rpath=/usr/local/openssl/lib" ./configure --with-openssl=/usr/local/openssl \
    && make \
    && make altinstall \
    && cd ../.. \
    && rm -R /opt/temp

# For openssl
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64

RUN cd /usr/local/bin/ && ln -s python3.11 python3 && ln -s pip3.11 pip3

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

# This is a hack to get the hadoop environment configuration code to run on the raw configuration
# files regardless of whether there's a config var set that triggers that file
ENV YARN-SITE.XML_fakekey=hack_to_get_config_system_to_process_the_raw_config_file
ENV CORE-SITE.XML_fakekey=hack_to_get_config_system_to_process_the_raw_config_file
ENV HDFS-SITE.XML_fakekey=hack_to_get_config_system_to_process_the_raw_config_file

# Enable the fair scheduler. There are lots of config options, see
# https://hadoop.apache.org/docs/stable/hadoop-yarn/hadoop-yarn-site/FairScheduler.html
ENV YARN-SITE.XML_yarn.resourcemanager.scheduler.class=org.apache.hadoop.yarn.server.resourcemanager.scheduler.fair.FairScheduler
ENV YARN-SITE.XML_yarn.scheduler.fair.allocation.file=/opt/hadoop/fair-scheduler.xml
COPY ./conf/yarn/fair-scheduler.xml /opt/hadoop/fair-scheduler.xml

# Enable s3
ENV HADOOP_OPTIONAL_TOOLS=hadoop-aws

COPY ./scripts/ /opt/scripts/
RUN chmod a+x /opt/scripts/*.sh

WORKDIR /opt/hadoop
USER hadoop

# This is the entrypoint from the hadoop container, buried in the history:
# ENTRYPOINT ["/usr/local/bin/dumb-init" "--" "/opt/starter.sh"]
ENTRYPOINT ["/usr/local/bin/dumb-init", "--", "/opt/scripts/entrypoint.sh"]
