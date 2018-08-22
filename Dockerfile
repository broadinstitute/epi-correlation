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

# Tester - copy everything from base; /reference /scripts /usr/lib/R/library /home/usr/igv
FROM alpine as tester
COPY --from=base /reference /reference
COPY --from=base /scripts /scripts
COPY --from=base /usr/lib/R/library /usr/lib/R/library
COPY --from=base /usr/local/bin /usr/local/bin
COPY --from=base /home/user/igv /home/user/igv

ADD test_data /test_data

RUN \
  apk add --no-cache \
    bash \
    openjdk8-jre \
    R \
    && \
  \
  # run the test command
  /scripts/testPipeline.sh

# Final - this is what the user should use
FROM alpine as final
COPY --from=base /reference /reference
COPY --from=base /scripts /scripts
COPY --from=base /usr/lib/R/library /usr/lib/R/library
COPY --from=base /usr/local/bin /usr/local/bin
COPY --from=base /home/user/igv /home/user/igv

ADD test_data /test_data

RUN \
  apk add --no-cache \
    bash \
    openjdk8-jre \
    R 

ARG USER='user'

WORKDIR /scripts

RUN adduser -S ${USER} && \
    chown ${USER} . && \
    chown -R ${USER} /home/user/igv

USER ${USER}
