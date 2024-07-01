#!/bin/bash

readonly DOCKER_DATA_DIR_PATH="/opt/docker"
readonly DOCKER_STACKS_DIR_PATH="${DOCKER_DATA_DIR_PATH}/stacks"
readonly DOCKER_VOLUMES_DIR_PATH="${DOCKER_DATA_DIR_PATH}/volumes"
readonly DOCKER_ARCHIVE_DIR_PATH="${DOCKER_DATA_DIR_PATH}/archive"

readonly TMP_DIR_PATH="/tmp"
readonly TMP_PROJECTS_LIST_FILE_PATH="${TMP_DIR_PATH}/docker_projects.tmp"

readonly BACKUP_FREQUENCY_ONE="*-*-* 03:00:00"
readonly BACKUP_FREQUENCY_TWO="*-*-* 15:00:00"
readonly BACKUP_ACCURACY_SEC="30min"
readonly BACKUP_RAND_DELAY_SEC=1800 seconds
readonly BACKUP_NAME="docker_backup"
readonly BACKUP_SERVICE="/etc/systemd/system/${BACKUP_NAME}.service"
readonly BACKUP_TIMER="/etc/systemd/system/${BACKUP_NAME}.timer"

function validate_file_permission() {
    local file="$1"
    local permission="$2"

    if [[ $(stat -c "%a" "${file}") != "${permission}" ]]; then
        return 1
    fi
}

function file_is_exists() {
    local file="$1"
    
    if [ -e "${file}" ]; then
        if [ -r "${file}" ]; then
            return 0
        fi
    fi

    return 1
}

function dir_is_exists() {
    local directory="$1"

    if [ -d "${directory}" ]; then
        return 0
    fi

    return 1
}

function archive_directory() {
    local archive_name="$1"
    local source_path="$2"
    local dest_path="$3"
    local archive_old_path="${dest_path}/${archive_name}.tar.gz.old"
    local archive_path="${dest_path}/${archive_name}.tar.gz"

    if ! dir_is_exists "${dest_path}"; then
        mkdir -p "${dest_path}"
    fi

    if file_is_exists "${archive_old_path}"; then
        rm "${archive_old_path}"
    fi

    if file_is_exists "${archive_path}"; then
        mv "${archive_path}" "${archive_old_path}"
    fi

    tar -czvf "${archive_path}" "${source_path}"
}

function docker_compose_down() {
    local stack_path="$1"
    cd "${stack_path}" &&
    docker compose down &&
    cd - ||
    return 1
}

function docker_compose_up() {
    local stack_path="$1"
    cd "${stack_path}" &&
    docker compose up -d &&
    cd - ||
    return 1
}

function archive_projects() {
    ls -d ${DOCKER_STACKS_DIR_PATH}/*/ > "${TMP_PROJECTS_LIST_FILE_PATH}"

    while IFS= read -r project
    do
        echo "project ${project}"
        if docker_compose_down "${project}"; then
            local project_name
            project_name="$(basename "${project}")"
            
            local stack_path="${project}"
            local volume_path=""${DOCKER_VOLUMES_DIR_PATH}/${project_name}""
            
            archive_directory "${project_name}-stack" "${stack_path}" "${DOCKER_ARCHIVE_DIR_PATH}"

            if dir_is_exists "${volume_path}"; then
                archive_directory "${project_name}-volume" "${volume_path}" "${DOCKER_ARCHIVE_DIR_PATH}"
            fi

            docker_compose_up "${project}"
        fi
    done < "${TMP_PROJECTS_LIST_FILE_PATH}"
    rm "${TMP_PROJECTS_LIST_FILE_PATH}"
}

function enable() {
    cat <<EOF > ${BACKUP_SERVICE}
[Unit]
Description=docker_backup $(realpath "${BASH_SOURCE[0]}")
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$(realpath "${BASH_SOURCE[0]}") backup
EOF
    cat <<EOF > ${BACKUP_TIMER}
[Unit]
Description=docker_backup $(realpath "${BASH_SOURCE[0]}") daily backups
[Timer]
OnCalendar=${BACKUP_FREQUENCY_ONE}
OnCalendar=${BACKUP_FREQUENCY_TWO}
AccuracySec=${BACKUP_ACCURACY_SEC}
RandomizedDelaySec=${BACKUP_RAND_DELAY_SEC}
Persistent=true
[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now ${BACKUP_NAME}.timer
    systemctl status ${BACKUP_NAME} --no-pager
    echo "You can watch the logs with this command:"
    echo "   journalctl --unit ${BACKUP_NAME}"
}

function disable() { # = Disable scheduled backups and remove systemd timer
    systemctl disable --now ${BACKUP_NAME}.timer
    rm -f ${BACKUP_SERVICE} ${BACKUP_TIMER}
    systemctl daemon-reload
}

function init() {
    if ! validate_file_permission "${BASH_SOURCE[0]}" "700"; then
        echo "Incorrect permissions on script. Run: "
        echo "  chmod 0700 $(realpath "${BASH_SOURCE[0]}")"
        exit 1
    fi
}

function main() {
    local command="$1"

    if [ "${command}" == "enable" ]; then
        enable
    elif [ "${command}" == "disable" ]; then
        disable
    elif [ "${command}" == "backup" ]; then
        archive_projects
    else
        echo "usage: ${BASH_SOURCE[0]} backup | enable | disable"
    fi
}

init
main "$@"