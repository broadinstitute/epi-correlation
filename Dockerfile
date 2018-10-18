### Base image
FROM google/cloud-sdk:alpine as base

ARG IGVTOOLS_VERSION='2.3.98'
ARG SAMTOOLS_VERSION='1.9'

ADD scripts/install.R /tmp/

RUN \
    # Install system packages
    apk add --no-cache \
      bash \
      build-base \
      curl \
      ncurses-dev \
      openjdk8-jre \
      R \
      R-dev \
      zlib-dev \
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
      ncurses-dev \
      R-dev \
      zlib-dev

ADD igv /home/user/igv

ADD reference /reference
ADD scripts /scripts
WORKDIR /data



### Tester image - copy everything from base; /reference /scripts /usr/lib/R/library /home/usr/igv
FROM base as tester

ADD test_data /test_data
ADD wdl /wdl

ARG WOMTOOL_VERSION='35'

RUN wget https://github.com/broadinstitute/cromwell/releases/download/${WOMTOOL_VERSION}/womtool-${WOMTOOL_VERSION}.jar -O /wdl/womtool.jar

RUN /scripts/testPipeline.sh

RUN java -jar /wdl/womtool.jar validate /wdl/pipeline.wdl -i /wdl/example_inputs.json



### Final image - this is what the user should use
FROM base as final

ENV UMASK="ugo=rwx"
