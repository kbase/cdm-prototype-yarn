FROM apache/hadoop:3.3.6

USER root

# TODO install python

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

# enable s3
ENV HADOOP_OPTIONAL_TOOLS=hadoop-aws

COPY ./scripts/ /opt/scripts/
RUN chmod a+x /opt/scripts/*.sh

USER hadoop

# This is the entrypoint from the hadoop container, buried in the history:
# ENTRYPOINT ["/usr/local/bin/dumb-init" "--" "/opt/starter.sh"]
ENTRYPOINT ["/usr/local/bin/dumb-init", "--", "/opt/scripts/entrypoint.sh"]
