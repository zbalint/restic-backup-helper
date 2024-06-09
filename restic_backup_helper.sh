#!/bin/bash

# directory consts
readonly BASE_DIRECTORY="/root/restic_backup"
readonly CONFIG_DIRECTORY="${BASE_DIRECTORY}/config"

# repository settings consts
readonly REPOSITORY_PATH_FILE="${CONFIG_DIRECTORY}/repository_path"
readonly REPOSITORY_PASS_FILE="${CONFIG_DIRECTORY}/repository_pass"
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
readonly LOCAL_MOUNT_PATH_LIST_FILE="/tmp/restic_mount_path_list"
readonly SSHFS_BACKUP_OPTIONS="ro,reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"
readonly SSHFS_RESTORE_OPTIONS="reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"

# script settings
readonly COMMANDS=(init backup trigger forget prune status logs snapshots restore enable disable help)

# readonly BACKUP_FREQUENCY="*-*-* 00,06,12,18:00:00"
readonly BACKUP_FREQUENCY="hourly"
readonly BACKUP_NAME=restic_backup
readonly BACKUP_SERVICE=/etc/systemd/system/${BACKUP_NAME}.service
readonly BACKUP_TIMER=/etc/systemd/system/${BACKUP_NAME}.timer

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

function get_repository_path() {
    read_file "${REPOSITORY_PATH_FILE}"
}

function get_repository_password() {
    read_file "${REPOSITORY_PASS_FILE}"
}

function get_healthchecks_io_id() {
    read_file "${HEALTHCHECKS_IO_ID_FILE}"
}

function save_mount_path() {
    local mount_path="$1"

    echo "${mount_path}" >> "${LOCAL_MOUNT_PATH_LIST_FILE}"
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

function validate_restic_installation() {
    if ! command -v restic >/dev/null; then
        echo "You need to install restic."
        exit 1
    fi
}

function validate_sshfs_installation() {
    if ! command -v sshfs >/dev/null; then
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

function validate_config_files_and_permissions() {

    if ! file_is_exists "${REPOSITORY_PATH_FILE}" || ! validate_file_permission "${REPOSITORY_PATH_FILE}" "600"; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_PATH_FILE})"
        exit 1
    fi

    if ! file_is_exists "${REPOSITORY_PASS_FILE}" || ! validate_file_permission "${REPOSITORY_PASS_FILE}" "600"; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_PASS_FILE})"
        exit 1
    fi

    if ! file_is_exists "${REPOSITORY_CLIENTS_FILE}" || ! validate_file_permission "${REPOSITORY_CLIENTS_FILE}" "600"; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${REPOSITORY_CLIENTS_FILE})"
        exit 1
    fi

    if ! file_is_exists "${HEALTHCHECKS_IO_ID_FILE}" || ! validate_file_permission "${HEALTHCHECKS_IO_ID_FILE}" "600"; then
        echo "File does not exists or has incorrect permissions. Run: "
        echo "  chmod 0600 $(realpath ${HEALTHCHECKS_IO_ID_FILE})"
        exit 1
    fi
}

function sshfs_mount() {
    local remote_user="$1"
    local remote_host="$2"
    local remote_path="$3"
    local local_path="$4"
    local sshfs_options="$5"

    rm -f ~/.ssh/known_hosts
    ssh-keyscan -t ssh-ed25519 "${remote_host}" >> ~/.ssh/known_hosts && \
    sshfs -o "${sshfs_options}" "${remote_user}@${remote_host}:${remote_path}" "${local_path}" && \
    dir_is_exists "${local_path}" && \
    dir_is_mounted "${local_path}" && \
    save_mount_path "${local_path}"
}

function sshfs_umount() {
    local local_path="$1"

    umount "${local_path}"
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
    sshfs_umount "${local_path}"
}

function backup_clients() {
    local repository_clients_list="${REPOSITORY_CLIENTS_FILE}"

    healthcheck "start"

    while IFS= read -r client
    do
        if [ -n "${client}" ]; then
            backup_client "${client}"
        fi
    done < "${repository_clients_list}"

    restic_forget && \
    restic_check && \
    healthcheck "stop"
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

function backup() { # = Run backup now
    ## Test if running in a terminal and have enabled the backup service:
    if [[ -t 0 ]] && [[ -f ${BACKUP_SERVICE} ]]; then
        ## Run by triggering the systemd unit, so everything gets logged:
        trigger
    ## Not running interactive, or haven't run 'enable' yet, so run directly:
    elif backup_clients; then
        echo "Restic backup finished successfully."
    else
        echo "Restic backup failed!"
        exit 1
    fi
}

function restore() { # [user@host:path] = Restore data from snapshot (default 'latest')
    local client="$1"
    restore_client "${client}"
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
    echo "Backup clients:"
    while IFS= read -r client
    do
        echo "${client}"
    done < "${repository_clients_list}"
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
    validate_restic_installation
    validate_sshfs_installation
    validate_script_permissions
    update_repository_clients_file
    validate_config_files_and_permissions

    if test $# = 0; then
        help
    else
        CMD=$1; shift;
        if [[ " ${COMMANDS[*]} " =~ ${CMD} ]]; then
            ${CMD} "$@"
        else
            echo "Unknown command: ${CMD}" && exit 1
        fi
    fi
}

main "$@"