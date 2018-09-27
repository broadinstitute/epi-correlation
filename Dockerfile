FROM alpine as base

ARG IGVTOOLS_VERSION='2.3.98'
ARG SAMTOOLS_VERSION='1.9'

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
      ncurses \
       ncurses-dev musl-dev g++ make zlib-dev \
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
    # Install samtools
    cd /tmp && \
    wget https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
    tar xjvf samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
    cd /tmp/samtools-${SAMTOOLS_VERSION} && \
    make && \
    mv /tmp/samtools-${SAMTOOLS_VERSION}/samtools /usr/bin && \
    # Clean up
    rm -rf /tmp/* && \
    apk del \
      build-base \
      curl \
      R-dev \
      ncurses \
      ncurses-dev musl-dev g++ make zlib-dev

ADD igv /home/user/igv

ADD reference /reference
ADD scripts /scripts

# Tester - copy everything from base; /reference /scripts /usr/lib/R/library /home/usr/igv
FROM base as tester
ADD test_data /test_data

RUN \
  # run the test command
  /scripts/testPipeline.sh

# Final - this is what the user should use
FROM base as final

ARG USER='user'

WORKDIR /scripts

RUN adduser -S ${USER} && \
    chown ${USER} . && \
    chown -R ${USER} /home/user/igv

USER ${USER}