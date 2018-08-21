FROM alpine

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

ADD reference /reference
ADD scripts /scripts
ADD igv /home/user/igv
ADD test_data /test_data

ARG USER='user'

WORKDIR /scripts

RUN adduser -S ${USER} && \
    chown ${USER} . && \
    chown -R ${USER} /home/user/igv

USER ${USER}
