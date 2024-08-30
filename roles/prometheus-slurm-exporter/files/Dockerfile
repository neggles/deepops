# allows passing in the ubuntu release as a build arg
ARG UBUNTU_RELEASE=jammy

# settings for apt and pip (inheritable by all images)
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBIAN_PRIORITY="critical"

# load the same base image as the host
FROM ubuntu:${UBUNTU_RELEASE} AS base

# Set shell
SHELL ["/bin/bash", "-ceuxo", "pipefail"]

# Inherit args from global
ARG DEBIAN_FRONTEND
ARG DEBIAN_PRIORITY
ARG SLURM_EXPORTER_VERSION='1.6.4'

# install some basic deps
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
 && apt-get -y install --no-install-recommends \
    apt-transport-https \
    apt-utils \
    ca-certificates \
    python3-venv \
    python-is-python3 \
    python3-pip \
    curl \
    git \
    nano \
    libmunge2 \
 && apt-get clean

# get the exporter package
WORKDIR /app
RUN ARCH=$(uname -m); \
    [[ "${ARCH}" == "x86_64" ]] && ARCH="amd64" || true; \
    curl -fsSL "https://github.com/rivosinc/prometheus-slurm-exporter/releases/download/v${SLURM_EXPORTER_VERSION}/prometheus-slurm-exporter_${SLURM_EXPORTER_VERSION}_linux_$ARCH.tar.gz" \
    | tar -xzC /app

# add the slurm user so sinfo stops complaining
ARG SLURM_USER=slurm
ARG SLURM_UID=22078
ARG SLURM_GID=996
RUN addgroup --system \
    --gid ${SLURM_GID} \
    ${SLURM_USER} \
 && adduser --system \
    --disabled-password \
    --uid ${SLURM_UID} \
    --gid ${SLURM_GID} \
    ${SLURM_USER}

# add workdir to PATH
ENV PATH="/app:${PATH}"

# add entrypoint file
COPY ./entrypoint.sh /app/entrypoint.sh
RUN chmod a+x /app/entrypoint.sh

# some env vars the entrypoint will need
ENV SLURM_INSTALL_PREFIX="/usr/local"
ENV SLURM_EXPORTER_PORT="9092"
ENV SLURM_EXPORTER_LOG_LEVEL="info"

# run the entrypoint
ENTRYPOINT [ "/app/entrypoint.sh" ]
# default command is to run the exporter with no extra args
CMD [ "prometheus-slurm-exporter" ]
