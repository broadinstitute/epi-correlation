FROM alpine

ARG IGVTOOLS_VERSION='2.3.98'

ADD scripts/install.R /tmp/

RUN apk add --no-cache vim #for testing purposes

RUN apk add --no-cache openjdk8-jre \
      bash \
      g++ \
      R \
      R-dev && \
    # Install IGVTools
    cd /tmp && \
    wget -qO igvtools.zip \
      http://data.broadinstitute.org/igv/projects/downloads/${IGVTOOLS_VERSION%.*}/igvtools_${IGVTOOLS_VERSION}.zip && \
    unzip -q igvtools.zip && \
    cd IGVTools && \
    cp -r igvtools igvtools.jar genomes /usr/local/bin/ && \
    # Install R Packages
    cd /tmp && \
    mkdir -p /usr/share/doc/R/html && \
    ./install.R && \
    mkdir output

ADD scripts/ ./scripts/
ADD reference/ ./reference/
