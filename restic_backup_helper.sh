#!/bin/bash

export HOME=/root

readonly BACKUP_SCRIPT_NAME=$(basename "$0")
readonly BACKUP_SCRIPT_URL="https://raw.githubusercontent.com/zbalint/restic-backup-helper/master/restic_backup_helper.sh"

# directory consts
readonly BASE_DIRECTORY="/root/restic_backup"
readonly CONFIG_DIRECTORY="${BASE_DIRECTORY}/config"
readonly WORK_DIRECTORY="${BASE_DIRECTORY}/work"

# repository settings consts
readonly REPOSITORY_TYPE_FILE="${CONFIG_DIRECTORY}/repository_type"
readonly REPOSITORY_PATH_FILE="${CONFIG_DIRECTORY}/repository_path"
readonly REPOSITORY_PASS_FILE="${CONFIG_DIRECTORY}/repository_pass"
readonly REPOSITORY_SERVER_FILE="${CONFIG_DIRECTORY}/repository_server"
readonly REPOSITORY_CLIENTS_FILE="${CONFIG_DIRECTORY}/repository_clients"
readonly REPOSITORY_CLIENTS_FILE_URL="https://raw.githubusercontent.com/zbalint/restic-backup-helper/master/config/repository_clients"

readonly REPOSITORY_RETENTION_KEEP_YEARLY=3
readonly REPOSITORY_RETENTION_KEEP_MONTHLY=24
readonly REPOSITORY_RETENTION_KEEP_WEEKLY=4
readonly REPOSITORY_RETENTION_KEEP_DAILY=7
readonly REPOSITORY_RETENTION_KEEP_HOURLY=48
readonly REPOSITORY_RETENTION_KEEP_LAST=10

# healthcheck.io settings consts
readonly HEALTHCHECKS_IO_ID_FILE="${CONFIG_DIRECTORY}/healthchecks_io_id"

# sshfs settings consts
readonly LOCAL_MOUNT_PATH="/mnt"
readonly LOCAL_MOUNT_PATH_LIST_FILE="${WORK_DIRECTORY}/restic_mount_path_list"
readonly SSHFS_SERVER_OPTIONS="reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"
readonly SSHFS_BACKUP_OPTIONS="ro,reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"
readonly SSHFS_RESTORE_OPTIONS="reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"

# script settings
readonly RESTIC_COMMANDS=(init backup trigger forget prune status snapshots restore cleanup)
readonly COMMANDS=(install init backup trigger forget prune status snapshots restore cleanup logs update enable disable help)

# readonly BACKUP_FREQUENCY="hourly"
readonly BACKUP_FREQUENCY="*-*-* 00,06,12,18:00:00"
readonly BACKUP_NAME="restic_backup"
readonly BACKUP_SERVICE="/etc/systemd/system/${BACKUP_NAME}.service"
readonly BACKUP_TIMER="/etc/systemd/system/${BACKUP_NAME}.timer"
readonly BACKUP_RESULT_FILE="${WORK_DIRECTORY}/restic_backup_client_status"

trap __cleanup EXIT

function __cleanup() {
    local mount_path_list_file="${LOCAL_MOUNT_PATH_LIST_FILE}"
    local temp_file="${LOCAL_MOUNT_PATH_LIST_FILE}.tmp"

    if file_is_exists "${mount_path_list_file}"; then
        while IFS= read -r mount_path
        do
            if [ -n "${mount_path}" ] && dir_is_exists "${mount_path}" && dir_is_mounted "${mount_path}" ; then
                echo -n "Unmounting ${mount_path}..."
                if sshfs_umount "${mount_path}"; then
                    echo "OK"
                else 
                    echo "FAILED"
                    echo "${mount_path}" >> "${temp_file}"
                fi
            fi
        done < "${mount_path_list_file}"
        
        rm "${mount_path_list_file}"
        
        if file_is_exists "${temp_file}"; then
            mv "${temp_file}" "${mount_path_list_file}"
        fi
    fi
}

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

function dir_is_mounted() {
    local directory="$1"

    if mountpoint -q "${directory}"; then
        return 0
    fi

    return 1
}

function read_file() {
    local file="$1"

    cat "${file}"
}

function save_mount_path() {
    local mount_path="$1"

    echo "${mount_path}" >> "${LOCAL_MOUNT_PATH_LIST_FILE}"
}

function get_repository_type() {
    read_file "${REPOSITORY_TYPE_FILE}"
}

function get_repository_path() {
    read_file "${REPOSITORY_PATH_FILE}"
}

function get_repository_password() {
    read_file "${REPOSITORY_PASS_FILE}"
}

function get_repository_server() {
    read_file "${REPOSITORY_SERVER_FILE}"
}

function get_healthchecks_io_id() {
    read_file "${HEALTHCHECKS_IO_ID_FILE}"
}

function get_remote_user() {
    local client="$1"
    echo "${client}" | cut -d ";" -f 1
}

function get_remote_host() {
    local client="$1"
    echo "${client}" | cut -d ";" -f 2
}

function get_remote_path() {
    local client="$1"
    echo "${client}" | cut -d ";" -f 3
}

function get_local_path() {
    local remote_host="$1"
    local remote_path="$2"
    local local_base_path="${LOCAL_MOUNT_PATH}"
    local local_path="${local_base_path}/${remote_host}${remote_path}"

    mkdir -p "${local_path}"
    echo "${local_path}"
}

function convert_client_to_tag() {
    local client="$1"

    echo "${client}" | awk -F";" '{print $1"@"$2":"$3}'
}

function is_local_repository() {
    local repository_type
    repository_type="$(get_repository_type)"

    if [ "${repository_type}" = "local" ]; then
        return 0
    fi

    return 1
}

function is_remote_repository() {
    local repository_type
    repository_type="$(get_repository_type)"

    if [ "${repository_type}" = "remote" ]; then
        return 0
    fi

    return 1
}

function is_installed() {
    local command="$1"

    if command -v "${command}" >/dev/null; then
        return 0
    fi

    return 1
}

function is_restic_installed() {
    if is_installed "restic"; then
        return 0
    fi

    return 1
}

function is_sshfs_installed() {
    if is_installed "sshfs"; then
        return 0
    fi

    return 1
}

function validate_restic_installation() {
    if ! is_restic_installed; then
        echo "You need to install restic."
        exit 1
    fi
}

function validate_sshfs_installation() {
    if ! is_sshfs_installed; then
        echo "You need to install sshfs."
        exit 1
    fi
}

function validate_script_permissions() {
    if ! validate_file_permission "${BASH_SOURCE[0]}" "700"; then
        echo "Incorrect permissions on script. Run: "
        echo "  chmod 0700 $(realpath "${BASH_SOURCE[0]}")"
        exit 1
    fi
}

function update_repository_clients_file() {
    wget --quiet "${REPOSITORY_CLIENTS_FILE_URL}" -O "${REPOSITORY_CLIENTS_FILE}"
    echo >> "${REPOSITORY_CLIENTS_FILE}"
    chmod 600 "${REPOSITORY_CLIENTS_FILE}"
}

function validate_repository_type_file() {
    if file_is_exists "${REPOSITORY_TYPE_FILE}" && validate_file_permission "${REPOSITORY_TYPE_FILE}" "600"; then
        if is_local_repository || is_remote_repository; then
            return 0
        fi
    fi

    return 1
}

function validate_repository_server_file() {
    if file_is_exists "${REPOSITORY_SERVER_FILE}" && validate_file_permission "${REPOSITORY_SERVER_FILE}" "600"; then
        return 0
    fi

    return 1
}

function validate_repository_path_file() {
    if file_is_exists "${REPOSITORY_PATH_FILE}" && validate_file_permission "${REPOSITORY_PATH_FILE}" "600"; then
        return 0
    fi

    return 1
}

function validate_repository_pass_file() {
    if file_is_exists "${REPOSITORY_PASS_FILE}" && validate_file_permission "${REPOSITORY_PASS_FILE}" "600"; then
        return 0
    fi

    return 1
}

function validate_repository_clients_file() {
    if file_is_exists "${REPOSITORY_CLIENTS_FILE}" && validate_file_permission "${REPOSITORY_CLIENTS_FILE}" "600"; then
        return 0
    fi

    return 1
}

function validate_healthchecks_io_id_file() {
    if file_is_exists "${HEALTHCHECKS_IO_ID_FILE}" && validate_file_permission "${HEALTHCHECKS_IO_ID_FILE}" "600"; then
        return 0
    fi

    return 1
}


function validate_config_files_and_permissions() {

    if validate_repository_type_file; then
        if is_remote_repository && ! validate_repository_server_file; then
            echo "File does not exists or has incorrect permissions. Run: "
            echo "  chmod 0600 $(realpath ${REPOSITORY_SERVER_FILE})"
            exit 1
        fi
    else
        echo "File does not exists or has incorrect permissions or contains invalid repository type. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_TYPE_FILE})"
        exit 1
    fi

    if ! validate_repository_path_file; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_PATH_FILE})"
        exit 1
    fi

    if ! validate_repository_pass_file; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_PASS_FILE})"
        exit 1
    fi

    if ! validate_repository_clients_file; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_CLIENTS_FILE})"
        exit 1
    fi

    if ! validate_healthchecks_io_id_file; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${HEALTHCHECKS_IO_ID_FILE})"
        exit 1
    fi
}

function validate_install() {
    if validate_repository_type_file; then
        if is_remote_repository && ! validate_repository_server_file; then
            return 1
        fi
    else 
        return 1
    fi
 
    if ! validate_repository_path_file; then
        return 1
    elif ! validate_repository_pass_file; then
        return 1
    elif ! validate_repository_clients_file; then
        return 1
    elif ! validate_healthchecks_io_id_file; then
        return 1
    else 
        return 0
    fi

    return 1
}

function sshfs_mount() {
    local remote_user="$1"
    local remote_host="$2"
    local remote_path="$3"
    local local_path="$4"
    local sshfs_options="$5"

    if dir_is_exists "${local_path}" && dir_is_mounted "${local_path}"; then
        echo "The ${local_path} path is already mounted!"
        return 1
    fi

    rm -f ~/.ssh/known_hosts
    ssh-keyscan -t ssh-ed25519 "${remote_host}" >> ~/.ssh/known_hosts && \
    sshfs -o "${sshfs_options}" "${remote_user}@${remote_host}:${remote_path}" "${local_path}" && \
    dir_is_exists "${local_path}" && \
    dir_is_mounted "${local_path}" && \
    save_mount_path "${local_path}"
}

function sshfs_umount() {
    local local_path="$1"

    dir_is_exists "${local_path}" && \
    dir_is_mounted "${local_path}" && \
    umount "${local_path}"
}

function sshfs_mount_server() {
    local repository_server
    local repository_server_user
    local repository_server_host
    local repository_remote_path
    local repository_local_path

    repository_server="$(get_repository_server)"
    repository_server_user="$(get_remote_user "${repository_server}")"
    repository_server_host="$(get_remote_host "${repository_server}")"
    repository_remote_path="$(get_remote_path "${repository_server}")"
    repository_local_path="$(get_repository_path)"
    mkdir -p "${repository_local_path}" && \
    sshfs_mount "${repository_server_user}" "${repository_server_host}" "${repository_remote_path}" "${repository_local_path}" "${SSHFS_SERVER_OPTIONS}"
}

function sshfs_umount_server() {
    sshfs_umount "$(get_repository_path)"
}

function sshfs_remount_server() {
    local repository_path
    repository_path="$(get_repository_path)"

    if dir_is_exists "${repository_path}" && dir_is_mounted "${repository_path}"; then
        sshfs_umount_server
    elif ! dir_is_exists "${repository_path}"; then
        mkdir -p "${repository_path}"
    fi

    sshfs_mount_server
}


function healthcheck() {
    local status="$1"
    local healthchecks_io_id
    healthchecks_io_id="$(get_healthchecks_io_id)"

    # using curl (10 second timeout, retry up to 5 times):

    case "${status}" in
        start)
            curl -m 10 --retry 5 https://hc-ping.com/"${healthchecks_io_id}"/start
            ;;
        stop)
            local status_payload
            status_payload=$(status 2>&1)
            # curl -m 10 --retry 5 https://hc-ping.com/"${healthchecks_io_id}"
            curl -fsS -m 10 --retry 5 --data-raw "${status_payload}" https://hc-ping.com/"${healthchecks_io_id}"
            ;;
        failed)
            local status_payload
            status_payload=$(status 2>&1)
            # curl -m 10 --retry 5 https://hc-ping.com/"${healthchecks_io_id}"
            curl -fsS -m 10 --retry 5 --data-raw "${status_payload}" https://hc-ping.com/"${healthchecks_io_id}/fail"
            ;;
    esac
    
}

function call_restic() {
    local repository_path_file="${REPOSITORY_PATH_FILE}"
    local repository_pass_file="${REPOSITORY_PASS_FILE}"

    restic --verbose --repository-file "${repository_path_file}" --password-file "${repository_pass_file}" "$@"
}

function restic_init() {
    call_restic init
}

function restic_check() {
    call_restic check --read-data-subset 10%
}

function restic_prune() {
    call_restic prune
}

function restic_forget() {
    call_restic forget \
    --keep-yearly "${REPOSITORY_RETENTION_KEEP_YEARLY}" \
    --keep-monthly "${REPOSITORY_RETENTION_KEEP_MONTHLY}" \
    --keep-weekly "${REPOSITORY_RETENTION_KEEP_WEEKLY}" \
    --keep-daily "${REPOSITORY_RETENTION_KEEP_DAILY}" \
    --keep-hourly "${REPOSITORY_RETENTION_KEEP_HOURLY}" \
    --keep-last "${REPOSITORY_RETENTION_KEEP_LAST}" \
    --prune
}

function restic_cleanup() {
    local clients_marked_for_cleanup_file="${WORK_DIRECTORY}/restic_cleanup_clients_list"
    find_tags_without_client > "${clients_marked_for_cleanup_file}"

    while IFS= read -r client
    do
        if [ -n "${client}" ]; then
            echo "Removing missing client's snapshots: ${client}"
            local host
            local path
            local tag
            host=$(get_remote_host "${client}")
            path=/mnt/${host}/$(get_remote_path "${client}")
            tag=$(convert_client_to_tag "${client}")

            call_restic forget --group-by host --host "${host}" --keep-last 1
            call_restic forget latest --group-by host --host "${host}" --tag "${tag}" --path "${path}"
        fi
    done < "${clients_marked_for_cleanup_file}"
}

function restic_backup() {
    local backup_path="$1"
    local backup_tag="$2"
    local backup_host="$3"

    call_restic backup --no-scan "${backup_path}" --tag "${backup_tag}" --host "${backup_host}"
}

function restic_restore() {
    local restore_path="$1"
    local backup_tag="$2"
    local backup_host="$3"
    local backup_path="$4"

    call_restic restore latest --tag "${backup_tag}" --host "${backup_host}" --path "${backup_path}" --target "${restore_path}"
}

function find_tags_without_client() {
    local tag_list_temp_file="${WORK_DIRECTORY}/restic_tag_list"
    local client_list_file="${REPOSITORY_CLIENTS_FILE}"

    call_restic snapshots -c | awk '{print $5}' | grep "\@" | sort | uniq | tr "@" ";" | tr ":" ";" > "${tag_list_temp_file}"

    sort "${tag_list_temp_file}" "${client_list_file}" | uniq -u
}

function create_repository() {
    restic_init
}

function create_backup() {
    local local_path="$1"
    local backup_tag="$2"
    local backup_host="$3"

    dir_is_exists "${local_path}" && \
    dir_is_mounted "${local_path}" && \
    restic_backup "${local_path}" "${backup_tag}" "${backup_host}"
}

function restore_backup() {
    local local_path="$1"
    local backup_tag="$2"
    local backup_host="$3"
    local backup_path="$4"

    dir_is_exists "${local_path}" && \
    dir_is_mounted "${local_path}" && \
    restic_restore "${local_path}" "${backup_tag}" "${backup_host}" "${backup_path}"
}

function backup_client() {
    local client="$1"
    local remote_user
    local remote_host
    local remote_path
    local local_path

    remote_user=$(get_remote_user "${client}")
    remote_host=$(get_remote_host "${client}")
    remote_path=$(get_remote_path "${client}")
    local_path=$(get_local_path "${remote_host}" "${remote_path}")
    
    sshfs_mount "${remote_user}" "${remote_host}" "${remote_path}" "${local_path}" "${SSHFS_BACKUP_OPTIONS}" && \
    create_backup "${local_path}" "${remote_user}@${remote_host}:${remote_path}" "${remote_host}"
    local backup_result=$?
    sshfs_umount "${local_path}"
    return ${backup_result}
}

function backup_clients() {
    local repository_clients_list="${REPOSITORY_CLIENTS_FILE}"
    local status_file="${BACKUP_RESULT_FILE}"
    local status=0

    healthcheck "start"

    echo "Backup result:" > "${status_file}"

    while IFS= read -r client
    do
        if [ -n "${client}" ]; then
            if backup_client "${client}"; then
                echo "Restic backup for client '${client}' was successful!"
                echo "[OK   ] ${client}" >> "${status_file}"
            else
                echo "Restic backup for client '${client}' failed!"
                echo "[ERROR] ${client}" >> "${status_file}"
                status=1
            fi
        fi
    done < "${repository_clients_list}"

    if ! restic_forget || ! restic_check; then
        return 1
    fi
    return ${status}
}

function restore_client() {
    local client="$1"
    local remote_user
    local remote_host
    local remote_path
    local local_path

    remote_user=$(get_remote_user "${client}")
    remote_host=$(get_remote_host "${client}")
    remote_path=$(get_remote_path "${client}")
    local_path=$(get_local_path "${remote_host}" "${remote_path}")

    sshfs_mount "${remote_user}" "${remote_host}" "${remote_path}" "${local_path}" "${SSHFS_RESTORE_OPTIONS}" && \
    restore_backup "/" "${remote_user}@${remote_host}:${remote_path}" "${remote_host}" "${local_path}"
    sshfs_umount "${local_path}"
}

function help() { # = Show this help
    echo "## restic_backup.sh Help:"
    echo -e "# subcommand [ARG1] [ARG2]\t#  Help Description" | expand -t35
    for cmd in "${COMMANDS[@]}"; do
        annotation=$(grep -E "^function ${cmd}\(\) { # " "${BASH_SOURCE[0]}" | sed "s/^function ${cmd}() { # \(.*\)/\1/")
        args=$(echo "${annotation}" | cut -d "=" -f1)
        description=$(echo "${annotation}" | cut -d "=" -f2)
        echo -e "${cmd} ${args}\t# ${description} " | expand -t35
    done
}

function install_restic() {
    apt install -y restic && restic self-update
}

function install_sshfs() {
    apt install -y sshfs
}

function install() { # = Create required configuration files
    local repository_type
    local repository_server
    local repository_path
    local repository_pass
    local healthchecks_io_id
    local answer

    if validate_install; then
        read -r -p "The configuration files already exists! Do you want to rewrite ALL the existsing files? (yes/no): " answer

        if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
            answer=""
            echo "Proceed with caution! This operation will overwrite any existing configuration file."
        elif [ "${answer}" = "no" ] || [ "${answer}" = "NO" ] || [ "${answer}" = "n" ] || [ "${answer}" = "N" ]; then
            echo "Phuh! Dodged a bullet..."
            exit 0
        else
            echo "Invalid answer!"
            exit 1
        fi
    fi

    echo "Creating directories..."
    
    echo "Creating base directory at ${BASE_DIRECTORY}" 
    mkdir -p ${BASE_DIRECTORY} 
    echo "Creating config directory at ${CONFIG_DIRECTORY}"
    mkdir -p ${CONFIG_DIRECTORY} 
    echo "Creating work directory at ${WORK_DIRECTORY}"
    mkdir -p ${WORK_DIRECTORY} 
    
    echo "Please answer the following questions to install the backup script configuration."

    read -r -p "Repository type (ex.: local or remote): " repository_type && echo "${repository_type:-local}" > "${REPOSITORY_TYPE_FILE}" && chmod 600 "${REPOSITORY_TYPE_FILE}"
    if [ "${repository_type}" = "remote" ]; then
        read -r -p "Repository server (ex.: user;host;/path): " repository_server && echo "${repository_server}" > "${REPOSITORY_SERVER_FILE}" && chmod 600 "${REPOSITORY_SERVER_FILE}"
    fi

    read -r -p "Repository path (ex.: /repository): " repository_path && echo "${repository_path:-/repository}" > "${REPOSITORY_PATH_FILE}" && chmod 600 "${REPOSITORY_PATH_FILE}"

    read -r -sp "Repository password (hidden): " repository_pass && echo "********" && echo "${repository_pass}" > "${REPOSITORY_PASS_FILE}" && chmod 600 "${REPOSITORY_PASS_FILE}"

    read -r -p "Healthcheck.io ID: " healthchecks_io_id && echo "${healthchecks_io_id}" > "${HEALTHCHECKS_IO_ID_FILE}" && chmod 600 "${HEALTHCHECKS_IO_ID_FILE}"

    if ! is_restic_installed; then
        read -r -p "Do you wish to install restic? (you can do it later manually) (yes/no): " answer
        if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
            answer=""
            install_restic
        fi
    fi

    if ! is_sshfs_installed; then
        read -r -p "Do you wish to install sshfs? (you can do it later manually) (yes/no): " answer
        if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
            answer=""
            install_sshfs
        fi
    fi

    read -r -p "Do you wish to initialize the repository? (you can do it later with the 'init' command) (yes/no): " answer
    if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
        answer=""
        if is_remote_repository && [ "${CMD}" != "install" ]; then
            if sshfs_mount_server; then 
                local result
                init
                sshfs_umount_server
            else
                echo "Respository storage server is unavaliable!"
                exit 1
            fi
        fi
    fi


    read -r -p "Do you wish to enable the systemd timer? (you can do it later with the 'enable' command) (yes/no): " answer
    if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
        answer=""
        enable
    fi

    read -r -p "Do you wish to update the script? (you can do it later with the 'update' command) (yes/no): " answer
    if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
        answer=""
        update
    fi
}

function init() { # = Initialize restic repository
    create_repository
}

function trigger() { # = Run backup now, by triggering the systemd service
    (set -x; systemctl start ${BACKUP_NAME}.service)
    echo "systemd is now running the backup job in the background. Check 'status' later."
}

function prune() { # = Remove old snapshots from repository
    restic_prune
}

function forget() { # = Apply the configured data retention policy to the backend
    restic_forget
}

function is_run_by_systemd_timer() {
    if [[ -t 0 ]] && [[ -f ${BACKUP_SERVICE} ]]; then
        return 0
    fi

    return 1
}

function backup() { # = Run backup now
    ## Test if running in a terminal and have enabled the backup service:
    if [[ -t 0 ]] && [[ -f ${BACKUP_SERVICE} ]]; then
        ## Run by triggering the systemd unit, so everything gets logged:
        trigger
    ## Not running interactive, or haven't run 'enable' yet, so run directly:
    elif backup_clients; then
        echo "Restic backup finished successfully."
        healthcheck "stop"
    else
        echo "Restic backup failed!"
        healthcheck "failed"
        exit 1
    fi
}

function restore() { # [user@host:path] = Restore data from snapshot (default 'latest')
    local client="$1"
    disable
    restore_client "${client}"
    enable
}

function cleanup() { # = Remove snapshots without client
    restic_cleanup
}

function update() { # = Update this script from github
    local backup_script_url="${BACKUP_SCRIPT_URL}"
    local backup_script_temp_path="${WORK_DIRECTORY}/${BACKUP_SCRIPT_NAME}.temp"
    local backup_script_path="${BASE_DIRECTORY}/${BACKUP_SCRIPT_NAME}"

    echo "Downloading the latest version of the script..."
    if curl -s -o "${backup_script_temp_path}" "${backup_script_url}"; then
        echo "Download complete. Updating the script..."
        chmod 700 "${backup_script_temp_path}"
        mv "${backup_script_temp_path}" "${backup_script_path}"
        echo "Update complete. Restarting the script..."
        exec ./"${BACKUP_SCRIPT_NAME}" "help"
    else
        echo "Failed to download the latest version. Keeping the current version."
        rm "${backup_script_temp_path}"
    fi
}

function snapshots() { # = List all snapshots
    call_restic snapshots
}

function enable() { # = Schedule backups by installing systemd timer
    cat <<EOF > ${BACKUP_SERVICE}
[Unit]
Description=restic_backup $(realpath "${BASH_SOURCE[0]}")
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$(realpath "${BASH_SOURCE[0]}") backup
EOF
    cat <<EOF > ${BACKUP_TIMER}
[Unit]
Description=restic_backup $(realpath "${BASH_SOURCE[0]}") daily backups
[Timer]
OnCalendar=${BACKUP_FREQUENCY}
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

function status() { # = Show the last and next backup times 
    local repository_clients_list="${REPOSITORY_CLIENTS_FILE}"
    # list clients
    echo "Backup clients: $(< "${repository_clients_list}" wc -l)"
    while IFS= read -r client
    do
        echo "${client}"
    done < "${repository_clients_list}"

    # show backup result for each client
    cat ${BACKUP_RESULT_FILE}

    echo "Missing clients: $(find_tags_without_client | wc -l)"
    find_tags_without_client
    
    # show repo path
    echo "Repository path: $(get_repository_path)"

    # show service logs
    journalctl --unit ${BACKUP_NAME} --since yesterday | \
        grep -E "(Restic backup finished successfully|Restic backup failed)" | \
        sort | awk '{ gsub("Restic backup finished successfully", "\033[1;33m&\033[0m");
                      gsub("Restic backup failed", "\033[1;31m&\033[0m"); print }'
    echo "Run the 'logs' subcommand for more information."
    (set -x; systemctl list-timers ${BACKUP_NAME} --no-pager)
    call_restic stats
    echo "Repository size on disk:"
    du -sh "$(get_repository_path)"
}

function logs() { # = Show recent service logs
    set -x
    journalctl --unit ${BACKUP_NAME} --since yesterday
}

function main() {
    validate_script_permissions
    if ! validate_install; then install; fi
    validate_restic_installation
    validate_sshfs_installation
    update_repository_clients_file
    validate_config_files_and_permissions

    if test $# = 0; then
        help
    else
        CMD=$1; shift;
        if [[ " ${COMMANDS[*]} " =~ ${CMD} ]]; then
            if [[ " ${RESTIC_COMMANDS[*]} " =~ ${CMD} ]] && is_remote_repository; then
                if [ "${CMD}" = "backup" ] && is_run_by_systemd_timer; then
                    echo "Defer mounting repository storage server..." 
                else
                    echo "Mounting repository storage server..."
                    if sshfs_mount_server; then 
                        echo "Respository storage server is mounted!"
                    else
                        echo "Respository storage server is unavaliable!"
                        exit 1 
                    fi
                fi
            fi

            ${CMD} "$@"
        else
            echo "Unknown command: ${CMD}" && exit 1
        fi
    fi
}

main "$@"