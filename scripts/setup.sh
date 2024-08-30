#!/usr/bin/env bash
set -euo pipefail

# DeepOps setup/bootstrap script
#   This script installs required dependencies on a system so it can run Ansible
#   and initializes the DeepOps directory
#
# Can be run standalone with: curl -sL bit.ly/nvdeepops | bash
#                         or: curl -sL bit.ly/nvdeepops | bash -s -- 19.07

# Determine current directory and root directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
ROOT_DIR=$(realpath "${SCRIPT_DIR}/../")

# Configuration
ANSIBLE_VERSION="${ANSIBLE_VERSION:-4.8.0}" # Ansible version to install
ANSIBLE_TOO_NEW="${ANSIBLE_TOO_NEW:-5.0.0}" # Ansible version too new
ANSIBLE_LINT_VERSION="${ANSIBLE_LINT_VERSION:-5.4.0}"
CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/config}"    # Default configuration directory location
DEEPOPS_TAG="${1:-master}"                        # DeepOps branch to set up
JINJA2_VERSION="${JINJA2_VERSION:-2.11.3}"        # Jinja2 required version
JMESPATH_VERSION="${JMESPATH_VERSION:-0.10.0}"    # jmespath pegged version, actual version probably not that crucial
MARKUPSAFE_VERSION="${MARKUPSAFE_VERSION:-1.1.1}" # MarkupSafe version
PIP="${PIP:-pip3}"                                # Pip binary to use
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3.10}"   # Python3 path
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"           # Path to python virtual environment to create

###

# Set distro-specific variables
. /etc/os-release
DEPS_DEB=(git virtualenv python3-virtualenv sshpass wget)
DEPS_EL7=(git libselinux-python3 python-virtualenv python3-virtualenv sshpass wget)
DEPS_EL8=(git python3-libselinux python3-virtualenv sshpass wget)
EPEL_VERSION="$(echo ${VERSION_ID} | sed 's/^[^0-9]*//;s/[^0-9].*$//')"
EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${EPEL_VERSION}.noarch.rpm"

# Disable interactive prompts from Apt
export DEBIAN_FRONTEND=noninteractive

# Exit if run as root
if [[ $(id -u) -eq 0 ]]; then
    echo "Please run as a regular user"
    exit
fi

# Install software dependencies
case "$ID" in
    rhel* | centos*)
        sudo yum -y -q install ${EPEL_URL} |& grep -v 'Nothing to do' # Enable EPEL (required for sshpass package)
        case "$EPEL_VERSION" in
            7)
                sudo yum -y -q install ${DEPS_EL7[@]}
                ;;
            8)
                sudo yum -y -q install ${DEPS_EL8[@]}
                ;;
        esac
        ;;
    ubuntu*)
        sudo apt-get -q update
        sudo apt-get -yq install ${DEPS_DEB[@]}
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        echo "Please install ${DEPS_RPM[@]} manually"
        ;;
esac

if ! ${PYTHON_BIN} -m venv --help &>/dev/null; then
    echo "ERROR: Unable to create Python virtual environment, 'venv' module not found"
    exit 1
fi

# Create virtual environment and install python dependencies
if [[ ! -d ${VENV_DIR} || ! -f ${VENV_DIR}/bin/activate ]]; then
    echo "Creating Python virtual environment in ${VENV_DIR}"
    deactivate nondestructive &>/dev/null || true # Deactivate any existing virtualenv
    ${PYTHON_BIN} -m venv $(realpath "${VENV_DIR}")
    source "${VENV_DIR}/bin/activate"
    python -m pip install -q --upgrade pip setuptools wheel
fi
source "${VENV_DIR}/bin/activate"

# Check for any installed ansible pip package
if pip show ansible 2>&1 >/dev/null; then
    current_version=$(pip show ansible | grep Version | awk '{print $2}')
    echo "Current version of Ansible is ${current_version}"
    if python -c "from distutils.version import LooseVersion; print(LooseVersion('$current_version') >= LooseVersion('$ANSIBLE_TOO_NEW'))" | grep True 2>&1 >/dev/null; then
        echo "Ansible version ${current_version} too new for DeepOps"
        echo "Please uninstall any ansible, ansible-base, and ansible-core packages and re-run this script"
        exit 1
    elif python -c "from distutils.version import LooseVersion; print(LooseVersion('$current_version') < LooseVersion('$ANSIBLE_VERSION'))" | grep True 2>&1 >/dev/null; then
        echo "Ansible will be upgraded from ${current_version} to ${ANSIBLE_VERSION}"
    fi
fi

echo "Installing Python dependencies..."
cat <<EOF >${VENV_DIR}/requirements.txt
ansible==${ANSIBLE_VERSION}
ansible-lint==${ANSIBLE_LINT_VERSION}
Jinja2==${JINJA2_VERSION}
netaddr
ruamel.yaml
PyMySQL
paramiko
requests==2.31.0
jmespath==${JMESPATH_VERSION}
MarkupSafe==${MARKUPSAFE_VERSION}
selinux
EOF
python -m pip install -q --require-virtualenv --upgrade -r ${VENV_DIR}/requirements.txt

# Copy default configuration
if [[ ! -d ${CONFIG_DIR} ]]; then
    cp -rfp "${ROOT_DIR}/config.example" "${CONFIG_DIR}"
    echo "Copied default configuration to ${CONFIG_DIR}"
else
    echo "Configuration directory '${CONFIG_DIR}' exists, not overwriting"
fi

# Install Ansible Galaxy roles
if command -v ansible-galaxy &>/dev/null; then
    echo "Updating Ansible Galaxy roles..."
    initial_dir="$(pwd)"
    roles_path="${ROOT_DIR}/roles/galaxy"
    collections_path="${ROOT_DIR}/collections"

    cd "${ROOT_DIR}"
    ansible-galaxy collection install -p "${collections_path}" --force -r "roles/requirements.yml" >/dev/null
    ansible-galaxy role install -p "${roles_path}" --force -r "roles/requirements.yml" >/dev/null

    # Install any user-defined config requirements
    if [[ -d ${CONFIG_DIR} && -f "${CONFIG_DIR}/requirements.yml" ]]; then
        cd "${CONFIG_DIR}"
        ansible-galaxy collection install -p "${collections_path}" --force -i -r "requirements.yml" >/dev/null
        ansible-galaxy role install -p "${roles_path}" --force -i -r "requirements.yml" >/dev/null
    fi
    cd "${initial_dir}"
else
    echo "ERROR: Unable to install Ansible Galaxy roles, 'ansible-galaxy' command not found"
fi

# Update submodules
if command -v git &>/dev/null; then
    git submodule update --init --recursive
else
    echo "ERROR: Unable to update Git submodules, 'git' command not found"
fi

echo
echo "*** Setup complete ***"
echo "To use Ansible, run: source ${VENV_DIR}/bin/activate"
echo
