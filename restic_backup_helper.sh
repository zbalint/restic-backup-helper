#!/bin/bash

export HOME=/root

readonly BACKUP_SCRIPT_NAME=$(basename "$0")
readonly BACKUP_SCRIPT_URL="https://raw.githubusercontent.com/zbalint/restic-backup-helper/master/restic_backup_helper.sh"

# directory consts
readonly BASE_DIRECTORY="/root/restic_backup"
readonly CONFIG_DIRECTORY="${BASE_DIRECTORY}/config"
readonly WORK_DIRECTORY="${BASE_DIRECTORY}/work"
readonly LOG_DIRECTORY="${BASE_DIRECTORY}/log"

# default remote filesystem driver
REMOTE_FILESYSTEM_DRIVER="sshfs"

# repository settings consts
readonly REPOSITORY_TYPE_FILE="${CONFIG_DIRECTORY}/repository_type"
readonly REPOSITORY_FS_DRIVER_FILE="${CONFIG_DIRECTORY}/repository_fs_driver"
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

# gotify settings
readonly NOTIFICATION_SERVER_URL="https://gotify.lab.escapethelan.com/message?token=Av4r4jsfN6aqn8A"

# healthcheck.io settings consts
readonly HEALTHCHECKS_IO_ID_FILE="${CONFIG_DIRECTORY}/healthchecks_io_id"

readonly LOCAL_MOUNT_PATH="/mnt"
readonly LOCAL_MOUNT_PATH_LIST_FILE="${WORK_DIRECTORY}/restic_mount_path_list"

# sshfs settings consts
readonly SSHFS_SERVER_OPTIONS="reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"
readonly SSHFS_BACKUP_OPTIONS="ro,reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"
readonly SSHFS_RESTORE_OPTIONS="reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"

# rclone settings consts
readonly RCLONE_RC_SERVER_ADDRESS="127.0.0.1:55551"
readonly RCLONE_RC_BACKUP_ADDRESS="127.0.0.1:55552"
readonly RCLONE_RC_RESTORE_ADDRESS="127.0.0.1:55553"
readonly RCLONE_SERVER_OPTIONS="--rc --rc-addr=${RCLONE_RC_SERVER_ADDRESS} --allow-other --no-checksum --vfs-cache-mode writes"
readonly RCLONE_BACKUP_OPTIONS="--rc --rc-addr=${RCLONE_RC_BACKUP_ADDRESS} --allow-other --no-checksum --read-only"
readonly RCLONE_RESTORE_OPTIONS="--rc --rc-addr=${RCLONE_RC_RESTORE_ADDRESS} --allow-other --no-checksum --vfs-cache-mode writes"

# script settings
readonly RESTIC_COMMANDS=(init backup trigger forget prune status snapshots restore unlock cleanup)
readonly COMMANDS=(install init backup trigger forget prune status snapshots restore unlock cleanup driver logs update enable disable help)

# readonly BACKUP_FREQUENCY="hourly"
# readonly BACKUP_FREQUENCY="*-*-* 00,06,12,18:00:00"
readonly BACKUP_FREQUENCY="00/2:00"
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
                echo "Unmounting ${mount_path}..."
                if remote_umount "${mount_path}"; then
                    umount "${mount_path}"
                else 
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

function get_repository_fs_driver() {
    read_file "${REPOSITORY_FS_DRIVER_FILE}"
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

function is_package_installed() {
    if apt-cache policy fuse3 | grep Installed | grep -v "none" >/dev/null; then
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

function is_rclone_installed() {
    if is_installed "rclone"; then
        return 0
    fi

    return 1
}

function is_jq_installed() {
    if is_installed "jq"; then
        return 0
    fi

    return 1
}

function is_fuse_installed() {
    if is_package_installed "fuse"; then
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
    if ! is_sshfs_installed || ! is_fuse_installed; then
        echo "You need to install sshfs and fuse3."
        exit 1
    fi
}

function validate_rclone_installation() {
    if ! is_rclone_installed || ! is_fuse_installed || ! is_jq_installed; then
        echo "You need to install rclone, fuse3 and jq."
        exit 1
    fi
}

function validate_fs_driver_installation() {
    local fs_driver
    fs_driver="$(get_repository_fs_driver)"

    if [ "${fs_driver}" == "sshfs" ]; then
        validate_sshfs_installation
    elif [ "${fs_driver}" == "rclone" ]; then
        validate_rclone_installation
    else
        echo "ERROR: Invalid filesystem driver: ${fs_driver}"
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

function validate_repository_fs_driver_file() {
    if file_is_exists "${REPOSITORY_FS_DRIVER_FILE}" && validate_file_permission "${REPOSITORY_FS_DRIVER_FILE}" "600"; then
        return 0
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

    if ! validate_repository_fs_driver_file; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_FS_DRIVER_FILE})"
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
 
    if ! validate_repository_fs_driver_file; then
        return 1
    elif ! validate_repository_path_file; then
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

function rclone_obscure() {
    local string="$*"
    echo "${string}" | rclone obscure -
}

function rclone_create_config() {
    # remote ssh user
    local remote_user="$1"
    # remote ssh host
    local remote_host="$2"
    # tailscale ssh does not require password, but rclone does so we create a fake password just for the rclone config
    local remote_pass
    remote_pass="$(rclone_obscure ${remote_user})"
    # rclone config location (note: this script rewrite this config)
    local rclone_config_path="/root/.config/rclone/rclone.conf"

    # create or replace existing config
    {
        echo "[${remote_host}]"
        echo "type = sftp"
        echo "host = ${remote_host}"
        echo "user = ${remote_user}"
        echo "pass = ${remote_pass}"
        echo "shell_type = unix"
        echo "use_insecure_cipher = true"
        echo "disable_hashcheck = true"
    } > "${rclone_config_path}"
}

function is_rclone_sync_finished() {
    local address="$1"
    
    rclone rc --rc-addr="${address}" vfs/stats | jq '.diskCache | [.uploadsInProgress, .uploadsQueued] | add'
    if [[ $(rclone rc --rc-addr="${address}" vfs/stats | jq '.diskCache | [.uploadsInProgress, .uploadsQueued] | add') -gt 0 ]]; then
        return 0
    fi

    return 1
}

function start_rclone() {
    local log_file
    log_file="${LOG_DIRECTORY}/rclone-$(date +%Y%m%d_%H%M%S).log"

    
    rclone "$@" --log-file="${log_file}" -log-level=INFO &
    sleep 1

    return 0
}

function is_rclone_mounted() {
    local mount_path="$1"
    mount | grep rclone | grep "${mount_path}" >/dev/null 2>&1
}

function is_rclone_running() {
    kill -0 "$(pidof rclone)" >/dev/null 2>&1
}

function is_rclone_rc_running() {
    local address="$1"
    ss -tulw | grep "${address}" >/dev/null 2>&1
}

function stop_rclone() {
    local address="$1"
    local local_path="$2"

    
    while [[ $(rclone rc --rc-addr="${address}" vfs/stats | jq '.diskCache | [.uploadsInProgress, .uploadsQueued] | add') -gt 0 ]]; do
        echo "Waiting for rclone to finish syncing..."
        sleep 1
    done

    if is_rclone_rc_running "${address}"; then
        echo "Stopping rclone at address: ${address}."
        wget -q -O- --method POST "http://${address}/core/quit" >/dev/null 2>&1
    fi

    local retry_count=1
    local max_retry_count=10
    
    while is_rclone_mounted "${local_path}"; do
        # echo "Waiting for rclone to stop... ${retry_count} / ${max_retry_count}" 
        if [[ ${retry_count} -lt ${max_retry_count} ]]; then
            retry_count=$((retry_count+1))
            sleep 0.5
        else
            if dir_is_mounted "${local_path}"; then
                umount "${local_path}"
            fi
            break
        fi
    done

    if is_rclone_mounted "${local_path}"; then
        return 1
    fi

    return 0
}

function rclone_mount() {
    local rc_address="$1"
    local remote_user="$2"
    local remote_host="$3"
    local remote_path="$4"
    local local_path="$5"
    local rclone_options="$6"

    save_mount_path "${local_path}"

    echo "Mounting rclone drive: ${local_path}"

    
    if is_rclone_mounted "${local_path}" && is_rclone_running && is_rclone_rc_running "${rc_address}"; then
        stop_rclone "${rc_address}" "${local_path}"
    fi

    if dir_is_exists "${local_path}" && dir_is_mounted "${local_path}"; then
        echo "The ${local_path} path is already mounted!"
        echo "Force unmount ${local_path}..."
        umount "${local_path}" && sleep 2
    fi

    RCLONE_RC_ADDRESS="${rc_address}"

    rclone_create_config "${remote_user}" "${remote_host}"
    rm -f ~/.ssh/known_hosts
    ssh-keyscan -t ssh-ed25519 "${remote_host}" >> ~/.ssh/known_hosts
    start_rclone mount ${rclone_options} "${remote_host}:${remote_path}" "${local_path}" 

    local retry_count=1
    local max_retry_count=50

    while ! is_rclone_mounted "${local_path}" && ! is_rclone_rc_running "${address}"; do
        # echo "Waiting for rclone to start... ${retry_count} / ${max_retry_count}"
        sleep 0.1
        if [[ ${retry_count} -lt ${max_retry_count} ]]; then
            retry_count=$((retry_count+1))
        else
            break
        fi
    done
    
    dir_is_exists "${local_path}" && \
    dir_is_mounted "${local_path}" && \
    is_rclone_mounted "${local_path}"
}

function rclone_umount() {
    local local_path="$1"

    echo "Unmounting rclone drive: ${local_path}"

    stop_rclone "${RCLONE_RC_ADDRESS}" "${local_path}"

    umount "${local_path}"
}

function sshfs_mount() {
    local remote_user="$1"
    local remote_host="$2"
    local remote_path="$3"
    local local_path="$4"
    local sshfs_options="$5"

    echo "Mounting sshfs drive: ${local_path}"

    if dir_is_exists "${local_path}" && dir_is_mounted "${local_path}"; then
        echo "The ${local_path} path is already mounted!"
        if ! sshfs_umount "${local_path}"; then
            return 1
        fi 
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

    echo "Unmounting sshfs drive: ${local_path}"

    dir_is_exists "${local_path}" && \
    dir_is_mounted "${local_path}" && \
    umount "${local_path}"
}

function get_mount_options() {
    local fs_handler="$1"
    local mount_type="$2"

    local mount_options="${SSHFS_BACKUP_OPTIONS}"

    if [ "${fs_handler}" == "sshfs" ]; then
        if [ "${mount_type}" == "backup" ]; then
            mount_options="${SSHFS_BACKUP_OPTIONS}"
        elif [ "${mount_type}" == "restore" ]; then
            mount_options="${SSHFS_RESTORE_OPTIONS}"
        elif [ "${mount_type}" == "repository" ]; then
            mount_options="${SSHFS_SERVER_OPTIONS}"
        else
            echo "ERROR: Invalid mount type: ${mount_type}"
            exit 1
        fi
    elif [ "${fs_handler}" == "rclone" ]; then
        if [ "${mount_type}" == "backup" ]; then
            mount_options="${RCLONE_BACKUP_OPTIONS}"
        elif [ "${mount_type}" == "restore" ]; then
            mount_options="${RCLONE_RESTORE_OPTIONS}"
        elif [ "${mount_type}" == "repository" ]; then
            mount_options="${RCLONE_SERVER_OPTIONS}"
        else
            echo "ERROR: Invalid mount type: ${mount_type}"
            exit 1
        fi
    else
        echo "ERROR: Invalid driver type: ${fs_handler}"
        exit 1
    fi
    echo "${mount_options}"
}

function get_rc_address() {
    local mount_type="$1"
    if [ "${mount_type}" == "backup" ]; then
        echo "${RCLONE_RC_BACKUP_ADDRESS}"
        return 0
    elif [ "${mount_type}" == "restore" ]; then
        echo "${RCLONE_RC_RESTORE_ADDRESS}"
        return 0
    elif [ "${mount_type}" == "repository" ]; then
        echo "${RCLONE_RC_SERVER_ADDRESS}"
        return 0
    else
        echo "ERROR: Invalid mount type: ${mount_type}"
        exit 1
    fi
}

function remote_mount() {
    local fs_handler="${REMOTE_FILESYSTEM_DRIVER}"
    local mount_type="$1"
    local remote_user="$2"
    local remote_host="$3"
    local remote_path="$4"
    local local_path="$5"
    
    if ! dir_is_exists "${local_path}"; then
        mkdir -p "${local_path}"
    fi

    if dir_is_mounted "${local_path}"; then
        echo "ERROR: Local path is already mounted: ${local_path}"
    fi

    if [ "${fs_handler}" == "sshfs" ]; then
        local mount_options
        mount_options="$(get_mount_options "${fs_handler}" "${mount_type}")"
        if sshfs_mount "${remote_user}" "${remote_host}" "${remote_path}" "${local_path}" "${mount_options}"; then
            echo "Sshfs drive successfully mounted: ${local_path}"
            return 0
        else
            echo "ERROR: Failed to mount sshfs drive: ${local_path}"
            return 1
        fi
        return 1
    elif [ "${fs_handler}" == "rclone" ]; then
        local rc_address
        local mount_options
        rc_address=$(get_rc_address "${mount_type}")
        mount_options="$(get_mount_options "${fs_handler}" "${mount_type}")"

        local retry_count=1
        local max_retry_count=3

        while [[ ${retry_count} -lt ${max_retry_count} ]]; do
            if rclone_mount "${rc_address}" "${remote_user}" "${remote_host}" "${remote_path}" "${local_path}" "${mount_options}"; then
                echo "Rclone drive successfully mounted: ${local_path}"
                return 0
            else
                echo "ERROR: Failed to mount rclone drive: ${local_path}"
                echo "Rertying in ${retry_count}s..."
                sleep ${retry_count}
            fi
            retry_count=$((retry_count+1))
        done

        if [[ ${retry_count} -ge 1 ]]; then
            echo "Rclone mount failed ${retry_count} times! Switching to sshfs mount."
            mount_options="$(get_mount_options "sshfs" "${mount_type}")"
            if sshfs_mount "${remote_user}" "${remote_host}" "${remote_path}" "${local_path}" "${mount_options}"; then
                echo "Sshfs drive successfully mounted: ${local_path}"
                return 0
            else
                echo "ERROR: Failed to mount sshfs drive: ${local_path}"
                return 1
            fi
        fi

        return 1
    else
        echo "ERROR: Invalid mount driver: ${fs_handler}"
        return 1
    fi

    return 1
}

function remote_umount() {
    local fs_handler="${REMOTE_FILESYSTEM_DRIVER}"
    local local_path="$1"

    if [ "${fs_handler}" == "sshfs" ]; then
        sshfs_umount "${local_path}"
        return $?
    elif [ "${fs_handler}" == "rclone" ]; then
        rclone_umount "${local_path}"
        return $?
    else
        echo "ERROR: Invalid mount driver: ${fs_handler}"
        return 1
    fi
    return 1
}

function remote_server_mount() {
    local repository_server
    local repository_server_user
    local repository_server_host
    local repository_remote_path
    local repository_local_path
    local mount_type="repository"

    repository_server="$(get_repository_server)"
    repository_server_user="$(get_remote_user "${repository_server}")"
    repository_server_host="$(get_remote_host "${repository_server}")"
    repository_remote_path="$(get_remote_path "${repository_server}")"
    repository_local_path="$(get_repository_path)"

    mkdir -p "${repository_local_path}" && \
    remote_mount "${mount_type}" "${repository_server_user}" "${repository_server_host}" "${repository_remote_path}" "${repository_local_path}"
}

function remote_server_umount() {
    remote_umount "$(get_repository_path)"
}

function remote_server_remount() {
    local repository_path
    repository_path="$(get_repository_path)"

    if dir_is_exists "${repository_path}" && dir_is_mounted "${repository_path}"; then
        remote_server_umount
    elif ! dir_is_exists "${repository_path}"; then
        mkdir -p "${repository_path}"
    fi

    remote_server_mount
}

function send_notification() {
    local title
    local message="$*"
    local priority=5
    title="$(hostname)"

    curl --insecure -m 10 --retry 2 "${NOTIFICATION_SERVER_URL}" -F "title=${title}" -F "message=${message}" -F "priority=${priority}"
}


function healthcheck() {
    local status="$1"
    local healthchecks_io_id
    healthchecks_io_id="$(get_healthchecks_io_id)"

    # using curl (10 second timeout, retry up to 5 times):

    case "${status}" in
        start)
            curl --insecure -m 10 --retry 5 https://hc-ping.com/"${healthchecks_io_id}"/start
            ;;
        stop)
            local status_payload
            status_payload=$(status 2>&1)
            curl --insecure -fsS -m 10 --retry 5 --data-raw "${status_payload}" https://hc-ping.com/"${healthchecks_io_id}"
            ;;
        failed)
            local status_payload
            status_payload=$(status 2>&1)
            curl --insecure -fsS -m 10 --retry 5 --data-raw "${status_payload}" https://hc-ping.com/"${healthchecks_io_id}/fail"
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

    call_restic backup --ignore-inode --no-scan "${backup_path}" --tag "${backup_tag}" --host "${backup_host}"
}

function restic_restore() {
    local restore_path="$1"
    local backup_tag="$2"
    local backup_host="$3"
    local backup_path="$4"

    call_restic restore latest --tag "${backup_tag}" --host "${backup_host}" --path "${backup_path}" --target "${restore_path}" --verify
}

function restic_unlock() {
    call_restic unlock
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
    

    local backup_result=1
    

    if remote_mount "backup" "${remote_user}" "${remote_host}" "${remote_path}" "${local_path}"; then
        create_backup "${local_path}" "${remote_user}@${remote_host}:${remote_path}" "${remote_host}"
        local backup_result=$?
        remote_umount "${local_path}"
    else
        echo "Mount failed!"
        remote_umount "${local_path}"
    fi
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
                remote_user=$(get_remote_user "${client}")
                remote_host=$(get_remote_host "${client}")
                remote_path=$(get_remote_path "${client}")
                send_notification "Backup failed for client: [${remote_user}@${remote_host}:${remote_path}]"
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

    local restore_result=1

    if remote_mount "restore" "${remote_user}" "${remote_host}" "${remote_path}" "${local_path}"; then
        restore_backup "/" "${remote_user}@${remote_host}:${remote_path}" "${remote_host}" "${local_path}"
        restore_result=$?
        remote_umount "${local_path}"
    else
        echo "Mount failed!"
    fi

    return ${restore_result}
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
    apt install -y sshfs fuse3
}

function remove_sshfs() {
    apt remove -y sshfs fuse3
}

function install_rclone() {
    apt install -y rclone fuse3 jq && rclone self-update
}

function remove_rclone() {
    apt remove -y rclone fuse3 jq
}

function driver() { # = Change filesystem driver
    read -r -p "Select repository filesystem driver (ex.: sshfs or rclone): " repository_fs_driver

    if [ "${repository_fs_driver}" == "sshfs" ]; then
        echo "${repository_fs_driver:sshfs}" > "${REPOSITORY_FS_DRIVER_FILE}" && chmod 600 "${REPOSITORY_FS_DRIVER_FILE}"
        if ! is_sshfs_installed; then
            read -r -p "Do you wish to install sshfs? (you can do it later manually) (yes/no): " answer
            if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
                answer=""
                install_sshfs
            fi
        fi
    elif [ "${repository_fs_driver}" == "rclone" ]; then
        echo "${repository_fs_driver:rclone}" > "${REPOSITORY_FS_DRIVER_FILE}" && chmod 600 "${REPOSITORY_FS_DRIVER_FILE}"
        if ! is_rclone_installed || ! is_fuse_installed; then
            read -r -p "Do you wish to install rclone and fuse? (you can do it later manually) (yes/no): " answer
            if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
                answer=""
                install_rclone
            fi
        fi
    else
        echo "ERROR: Invalid filesystem driver: ${repository_fs_driver}"
        exit 1
    fi
}

function install() { # = Create required configuration files
    local repository_type
    local repository_fs_driver
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

    read -r -p "Repository filesystem driver (ex.: sshfs or rclone): " repository_fs_driver && echo "${repository_fs_driver:sshfs}" > "${REPOSITORY_FS_DRIVER_FILE}" && chmod 600 "${REPOSITORY_FS_DRIVER_FILE}"
    
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

    if [ "${repository_fs_driver}" == "sshfs" ]; then
        if ! is_sshfs_installed; then
            read -r -p "Do you wish to install sshfs? (you can do it later manually) (yes/no): " answer
            if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
                answer=""
                install_sshfs
            fi
        fi
    elif [ "${repository_fs_driver}" == "rclone" ]; then
        if ! is_rclone_installed || ! is_fuse_installed; then
            read -r -p "Do you wish to install rclone and fuse? (you can do it later manually) (yes/no): " answer
            if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
                answer=""
                install_rclone
            fi
        fi
    else
        echo "ERROR: Invalid filesystem driver: ${repository_fs_driver}"
        exit 1
    fi


    read -r -p "Do you wish to initialize the repository? (you can do it later with the 'init' command) (yes/no): " answer
    if [ "${answer}" = "yes" ] || [ "${answer}" = "YES" ] || [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
        answer=""
        if is_remote_repository && [ "${CMD}" != "install" ]; then
            if remote_server_mount; then 
                init
                remote_server_umount
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
        send_notification "Backup failed!"
        exit 1
    fi
}

function restore() { # [user@host:path] = Restore data from snapshot (default 'latest')
    local client="$1"
    disable
    restore_client "${client}"
    enable
}

function unlock() { # = Remove repository lock
    restic_unlock
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
    echo "Filesystem driver: $(get_repository_fs_driver)"

    echo "Backup clients: $(< "${repository_clients_list}" wc -l)"
    while IFS= read -r client
    do
        echo "${client}"
    done < "${repository_clients_list}"

    echo "Missing clients: $(find_tags_without_client | wc -l)"
    find_tags_without_client

    # show backup result for each client
    cat ${BACKUP_RESULT_FILE}
    
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
    update_repository_clients_file
    validate_config_files_and_permissions
    validate_fs_driver_installation

    REMOTE_FILESYSTEM_DRIVER="$(get_repository_fs_driver)"

    if test $# = 0; then
        help
    else
        CMD=$1; shift;
        if [[ " ${COMMANDS[*]} " =~ ${CMD} ]]; then
            if [[ " ${RESTIC_COMMANDS[*]} " =~ ${CMD} ]] && ! is_remote_repository; then
                restic_unlock
            elif [[ " ${RESTIC_COMMANDS[*]} " =~ ${CMD} ]] && is_remote_repository; then
                if [ "${CMD}" = "backup" ] && is_run_by_systemd_timer; then
                    echo "Defer mounting repository storage server..." 
                else
                    echo "Mounting repository storage server..."
                    if remote_server_mount; then 
                        echo "Respository storage server is mounted!"
                        restic_unlock
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