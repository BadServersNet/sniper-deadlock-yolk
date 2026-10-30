FROM registry.gitlab.steamos.cloud/steamrt/sniper/platform
LABEL author="BuSheeZy"
LABEL maintainer="BuSheeZy@BadServers.net"
LABEL org.opencontainers.image.source="https://github.com/BadServersNet/sniper-deadlock-yolk"

ARG PROTON_VERSION=GE-Proton10-34
ARG PROTON_SHA512=9fd0b2cfbd501c0b5c892239c392c7283a029b5e5d5a77d3f85b0ce190d555456241a18eebca16b53f094b403499201c13550a3f0b9b365e1a5eb5737cbb7303

RUN sed -i 's|http://deb.debian.org/debian-security |https://snapshot.debian.org/archive/debian-security/20260831T000000Z/ |g' /etc/apt/sources.list \
  && apt-get -o Acquire::Check-Valid-Until=false update \
  && apt-get install -y ca-certificates curl iproute2 libvulkan1 mesa-vulkan-drivers python3 xvfb \
  && rm -rf /var/lib/apt/lists/* \
  && adduser --disabled-password --home /home/container container

RUN curl -fsSL -o /tmp/proton.tar.gz \
  "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${PROTON_VERSION}.tar.gz" \
  && echo "${PROTON_SHA512}  /tmp/proton.tar.gz" | sha512sum -c - \
  && mkdir -p /opt/proton \
  && tar -xzf /tmp/proton.tar.gz -C /opt/proton --strip-components=1 \
  && rm -f /tmp/proton.tar.gz \
  && test -x /opt/proton/proton \
  && mkdir -p /tmp/.X11-unix \
  && chmod 1777 /tmp/.X11-unix

USER container
ENV USER=container
ENV HOME=/home/container
WORKDIR /home/container

ENV DISPLAY=:99 \
  STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/.steam/steam \
  STEAM_COMPAT_DATA_PATH=/home/container/.proton \
  WINEDEBUG=-all \
  WINEDLLOVERRIDES=winedbg.exe=d \
  PROTON_LOG=0 \
  PROTON_USE_XALIA=0 \
  PROTON_NO_WRITE_WATCH=1 \
  DXVK_LOG_LEVEL=none \
  DXVK_STATE_CACHE=0 \
  MESA_NO_ERROR=1 \
  MESA_SHADER_CACHE_DISABLE=true \
  GALLIUM_DRIVER=llvmpipe \
  LP_NUM_THREADS=2

COPY ./entrypoint.sh /entrypoint.sh
COPY ./startup.py /startup.py
CMD [ "/bin/bash", "/entrypoint.sh" ]
