#!/usr/bin/env bash
set -euo pipefail

# If the first argument is "prometheus-slurm-exporter", remove it
if [[ ${1} == "prometheus-slurm-exporter" ]]; then
    shift
fi

# add SLURM_INSTALL_PREFIX to PATH if it's not already there
if [[ ${PATH} != *"${SLURM_INSTALL_PREFIX}/bin"* ]]; then
    export PATH="${SLURM_INSTALL_PREFIX}/bin:${PATH}"
fi

# Set default values for SLURM_EXPORTER_PORT and SLURM_EXPORTER_LOG_LEVEL if they are not set
export SLURM_EXPORTER_PORT="${SLURM_EXPORTER_PORT-'9092'}"
export SLURM_EXPORTER_LOG_LEVEL="${SLURM_EXPORTER_LOG_LEVEL-'info'}"

# check for host's hosts file and copy it in, stripping any localhost entries
if [[ -f "/etc/node_hosts" ]]; then
    sed -E '/^127\./d; /^::1/d; /f[e-f]0[0,2]::[0-2]/d' /etc/node_hosts | tee -a /etc/hosts >/dev/null
fi

# if we have args, and $1 starts with a dash, assume we want to run the exporter and pass any args
# otherwise, run the command passed to the container
if [[ $# -eq 0 || ${1} == "-"* ]]; then
    exec prometheus-slurm-exporter \
        --web.listen-address ":${SLURM_EXPORTER_PORT}" \
        --web.log-level "${SLURM_EXPORTER_LOG_LEVEL}" \
        "$@"
else
    exec "$@"
fi
