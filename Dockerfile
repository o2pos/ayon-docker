FROM python:3.11-slim AS build-ffmpeg
ENV FFMPEG_VERSION=7.1

ARG AYON_BACKEND_PATH
ARG AYON_FRONTEND_PATH

RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    libgnutls-openssl-dev \
    cmake \
    git \
    libtool \
    pkg-config \
    texinfo \
    wget \
    yasm \
    nasm \
    zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN \
  wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz \
  && tar -xzf ffmpeg-${FFMPEG_VERSION}.tar.gz \
  && rm ffmpeg-${FFMPEG_VERSION}.tar.gz \
  && mv ffmpeg-${FFMPEG_VERSION} ffmpeg

WORKDIR /src/ffmpeg
RUN ./configure \
    --prefix=/usr/local \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --enable-static \
    --disable-shared \
    --enable-gpl \
    --enable-gnutls \
    --enable-runtime-cpudetect \
    --extra-version=AYON && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && \
    rm -rf /tmp/ffmpeg

#
# Build frontend
#

FROM node:22 AS build-frontend

WORKDIR ${AYON_FRONTEND_PATH}

COPY \
  ${AYON_FRONTEND_PATH}/index.html \
  ${AYON_FRONTEND_PATH}/tsconfig.node.json \
  ${AYON_FRONTEND_PATH}/tsconfig.json \
  ${AYON_FRONTEND_PATH}/vite.config.ts \
  .
COPY .${AYON_FRONTEND_PATH}/package.json .${AYON_FRONTEND_PATH}/yarn.lock .

RUN yarn install

COPY ${AYON_FRONTEND_PATH}/public ${AYON_FRONTEND_PATH}/public
COPY ${AYON_FRONTEND_PATH}/share[d] ${AYON_FRONTEND_PATH}/shared
COPY ${AYON_FRONTEND_PATH}/src ${AYON_FRONTEND_PATH}/src

RUN yarn build

#
# Main container
#

FROM python:3.11-slim
ENV PYTHONBUFFERED=1

# Debian packages

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    curl \
    libgnutls-openssl27 \
    postgresql-client \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build-ffmpeg /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=build-ffmpeg /usr/local/bin/ffprobe /usr/local/bin/ffprobe

WORKDIR ${AYON_BACKEND_PATH}

COPY ${AYON_BACKEND_PATH}/pyproject.toml ${AYON_BACKEND_PATH}/uv.lock .
RUN --mount=from=ghcr.io/astral-sh/uv,source=/uv,target=/bin/uv \
    uv pip install -r pyproject.toml --system

COPY ${AYON_BACKEND_PATH}/static /backend/static
COPY ${AYON_BACKEND_PATH}/start.sh /backend/start.sh
COPY ${AYON_BACKEND_PATH}/reload.sh /backend/reload.sh
COPY ${AYON_BACKEND_PATH}/nxtool[s] /backend/nxtools
COPY ${AYON_BACKEND_PATH}/demogen /backend/demogen
COPY ${AYON_BACKEND_PATH}/linker /backend/linker
COPY ${AYON_BACKEND_PATH}/setup /backend/setup
COPY ${AYON_BACKEND_PATH}/aycli /usr/bin/ay
COPY ${AYON_BACKEND_PATH}/maintenance /backend/maintenance

COPY ${AYON_BACKEND_PATH}/schemas /backend/schemas
COPY ${AYON_BACKEND_PATH}/ayon_server /backend/ayon_server
COPY ${AYON_BACKEND_PATH}/api /backend/api
COPY ./RELEAS[E] /backend/RELEASE

COPY --from=build-frontend ${AYON_FRONTEND_PATH}/dist/ ${AYON_FRONTEND_PATH}

RUN sh -c 'date +%y%m%d%H%M > /backend/BUILD_DATE'

CMD ["/bin/bash", "/backend/start.sh"]

