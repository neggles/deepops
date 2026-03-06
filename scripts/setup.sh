#!/usr/bin/env bash
set -euo pipefail

# Determine current directory and root directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
ROOT_DIR=$(realpath "${SCRIPT_DIR}/../")

# Configuration
CONFIG_DIR="${CONFIG_DIR:-$ROOT_DIR/config}"  # Path to configuration directory
VIRTUAL_ENV="${VIRTUAL_ENV:-$ROOT_DIR/.venv}" # Path to python virtual environment to create

if ! command -v uv &>/dev/null; then
	echo "uv is required to manage this project's virtual environment. Please install uv to use this project. "
	echo "Installation instructions: https://docs.astral.sh/uv/getting-started/installation/"
	exit 1
fi

# Set distro-specific variables
. /etc/os-release
DEPS_DEB=(git python3.12-venv python3.12-pip sshpass wget curl)

# Disable interactive prompts from Apt
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

# Exit if run as root
if [[ $(id -u) -eq 0 ]]; then
	echo "This script/repository does not support running as root, please run as a normal user"
	exit 1
fi

# Install software dependencies
case "$ID" in
ubuntu*)
	sudo apt-get -q update
	sudo apt-get -yq install ${DEPS_DEB[@]}
	;;
*)
	echo "Unsupported Operating System $ID_LIKE"
	echo "Please install ${DEPS_DEB[@]} manually"
	;;
esac

# read .python-version file
py_version=$(<"${ROOT_DIR}/.python-version)")

# resolve venv path and create it if it doesn't exist
if [[ ! -d "${VIRTUAL_ENV}" ]]; then
	echo "Creating project virtual environment with uv"
	uv venv --seed --python "${py_version}" "${VIRTUAL_ENV}"
fi

# activate the virtual environment
source "${VIRTUAL_ENV}/bin/activate"
# configure uv
export UV_PROJECT="${ROOT_DIR}"
export UV_LINK_MODE="copy" # use copy mode so ansible doesn't get angy

# sync environment with pyproject.toml
echo "Ensuring venv packages are up to date"
uv sync --inexact --no-lock

# If the config directory doesn't exist, copy the example config there.
if [[ ! -d ${CONFIG_DIR} ]]; then
	echo "Configuration directory '${CONFIG_DIR}' does not exist, copying default configuration"
	cp -a "${ROOT_DIR}/config.example" "${CONFIG_DIR}"
fi

# Install Ansible Galaxy roles
if command -v ansible-galaxy &>/dev/null; then
	echo "Updating Ansible Galaxy roles..."
	roles_path="${ROOT_DIR}/roles/galaxy"
	collections_path="${ROOT_DIR}/collections"

	pushd "${ROOT_DIR}" >/dev/null
	ansible-galaxy collection install -p "${collections_path}" --force -r "roles/requirements.yml" >/dev/null
	ansible-galaxy role install -p "${roles_path}" --force -r "roles/requirements.yml" >/dev/null

	# Install any user-defined config requirements
	if [[ -d "${CONFIG_DIR}" && -f "${CONFIG_DIR}/requirements.yml" ]]; then
		cd "${CONFIG_DIR}"
		ansible-galaxy collection install -p "${collections_path}" --force -i -r "requirements.yml" >/dev/null
		ansible-galaxy role install -p "${roles_path}" --force -i -r "requirements.yml" >/dev/null
	fi
	popd >/dev/null
else
	echo "ERROR: Unable to install Ansible Galaxy roles, 'ansible-galaxy' command not found"
fi



echo
echo "*** Setup complete ***"
echo "To use Ansible, run: source ${VIRTUAL_ENV}/bin/activate"
echo
