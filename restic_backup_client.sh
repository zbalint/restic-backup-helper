#!/bin/bash

export HOME=/root

readonly BACKUP_SCRIPT_NAME=$(basename "$0")
readonly BACKUP_SCRIPT_URL="https://raw.githubusercontent.com/zbalint/restic-backup-helper/master/restic_backup_client.sh"
readonly BACKUP_USER="hermes
"
# directory consts
readonly BASE_DIRECTORY="/root/restic_backup"
readonly CONFIG_DIRECTORY="${BASE_DIRECTORY}/config"
readonly WORK_DIRECTORY="${BASE_DIRECTORY}/work"

# repository settings consts
readonly REPOSITORY_TYPE_FILE="${CONFIG_DIRECTORY}/repository_type"
readonly REPOSITORY_PATH_FILE="${CONFIG_DIRECTORY}/repository_path"
readonly REPOSITORY_PASS_FILE="${CONFIG_DIRECTORY}/repository_pass"

# readonly RESTIC_REST_SERVER="http://127.0.0.1:80"


# restic -r rest:http://admin:12345678@127.0.0.1:80/ init

# helper functions

# validates the files permission
function validate_file_permission() {
    local file="$1"
    local permission="$2"

    if [[ $(stat -c "%a" "${file}") != "${permission}" ]]; then
        return 1
    fi
}

# checks if the file is exists
function file_is_exists() {
    local file="$1"
    
    if [ -e "${file}" ]; then
        if [ -r "${file}" ]; then
            return 0
        fi
    fi

    return 1
}

# checks if the directory is exists
function dir_is_exists() {
    local directory="$1"

    if [ -d "${directory}" ]; then
        return 0
    fi

    return 1
}

# checks if the directory is mounted
function dir_is_mounted() {
    local directory="$1"

    if mountpoint -q "${directory}"; then
        return 0
    fi

    return 1
}

# reads the file
function read_file() {
    local file="$1"

    cat "${file}"
}

# incus functions

# calls incus executable
function call_incus() {
    incus "$@"
}

# list incus instances in csv format
function incus_list_instances() {
    call_incus list --columns n --format csv
}

# export an instance
function incus_export_instance() {
    local instance_name="$1"
    local export_path="$2"

    call_incus export --instance-only "${instance_name}" "${export_path}"
}

# restic functions

# calls restic executable
function call_restic() {
    local repository_path_file="${REPOSITORY_PATH_FILE}"
    local repository_pass_file="${REPOSITORY_PASS_FILE}"

    restic --verbose --repository-file "${repository_path_file}" --password-file "${repository_pass_file}" "$@"
}

function main() {

}

