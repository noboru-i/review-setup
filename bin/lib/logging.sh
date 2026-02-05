#!/bin/bash
# logging.sh — ログユーティリティ

LOG_DIR="${HOME}/.pr-review-setup/logs"
LOG_FILE=""

init_logging() {
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/review-setup-$(date '+%Y%m%d-%H%M%S').log"
}

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${message}"
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${message}" >> "${LOG_FILE}"
    fi
}

log_error() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "${message}" >&2
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${message}" >> "${LOG_FILE}"
    fi
}
