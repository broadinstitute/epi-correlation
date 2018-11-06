ARG DIST=/opt

## Base Image
FROM google/cloud-sdk:alpine as base

RUN \
  apk add --no-cache \
    bash \
    openjdk8-jre \
    R

## Builder image
FROM base as build

ARG DIST

RUN \
  apk add --no-cache \
    build-base \
    curl \
    ncurses-dev \
    zlib-dev \
    jq \
    bzip2-dev \
    xz-dev \
    && \
  \
  mkdir -p ${DIST}

WORKDIR /tmp

## Install R packages image
FROM build as R-install

ARG DIST

ADD scripts/install.R /tmp/

RUN apk add --no-cache \
    R-dev \
    && \
    \
  mkdir -p /usr/share/doc/R/html && \
  /tmp/install.R

## Install IGVTools image
FROM build as IGV-install

ARG DIST

RUN version=$(curl -s 'https://api.github.com/repos/igvteam/igv/tags' | jq -r '.[0].name') && \
    version=${version#v} && \
    curl -s "https://data.broadinstitute.org/igv/projects/downloads/${version%.*}/igvtools_${version}.zip" | \
    unzip -q - && \
    cd IGVTools && \
    chmod +x igvtools && \
    #mv lib/genomes/sizes lib/genomes && \
    mv igvtools lib ${DIST}

## Install Samtools image
FROM build as SAM-install

ARG DIST
ARG SAMTOOLS_VERSION='1.9'

RUN \
  wget https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
  tar xjvf samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
  cd /tmp/samtools-${SAMTOOLS_VERSION} && \
  make && \
  mv /tmp/samtools-${SAMTOOLS_VERSION}/samtools ${DIST}

## midway Image
FROM base as midway

ARG DIST

ENV PATH=${PATH}:${DIST}

WORKDIR ${DIST}

COPY --from=IGV-install ${DIST} ./
COPY --from=SAM-install ${DIST} ./
COPY --from=R-install /usr/lib/R/library /usr/lib/R/library/

ADD reference /reference
ADD scripts /scripts


WORKDIR /data

## Tester image
FROM midway as tester

ADD test_data /test_data
ADD wdl /wdl

ARG WOMTOOL_VERSION='35'

RUN wget https://github.com/broadinstitute/cromwell/releases/download/${WOMTOOL_VERSION}/womtool-${WOMTOOL_VERSION}.jar -O /wdl/womtool.jar

RUN /scripts/testPipeline.sh

RUN java -jar /wdl/womtool.jar validate /wdl/pipeline.wdl -i /wdl/example_inputs.json

## Final image
FROM midway
ENV UMAS="ugo=rwx"