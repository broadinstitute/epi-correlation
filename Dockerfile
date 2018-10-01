FROM alpine as base

ARG IGVTOOLS_VERSION='2.3.98'

ADD scripts/install.R /tmp/

RUN \
    # Install system packages
    apk add --no-cache \
      bash \
      build-base \
      curl \
      openjdk8-jre \
      R \
      R-dev \
      && \
    \
    # Install R packages
    mkdir -p /usr/share/doc/R/html && \
    /tmp/install.R && \
    \
    # Install IGVTools
    cd /tmp && \
    curl https://data.broadinstitute.org/igv/projects/downloads/${IGVTOOLS_VERSION%.*}/igvtools_${IGVTOOLS_VERSION}.zip \
      -so- | unzip -q - && \
    cd IGVTools && \
    chmod +x igvtools && \
    cp -r igvtools igvtools.jar genomes /usr/local/bin/ && \
    \
    # Clean up
    rm -rf /tmp/* && \
    apk del \
      build-base \
      curl \
      R-dev

ADD igv /home/user/igv

ADD reference /reference
ADD scripts /scripts
WORKDIR /data

# Tester - copy everything from base; /reference /scripts /usr/lib/R/library /home/usr/igv
FROM base as tester
ADD test_data /test_data

RUN \
  # run the test command
  /scripts/testPipeline.sh

# Final - this is what the user should use
FROM base as final

ENV UMASK="ugo=rwx"