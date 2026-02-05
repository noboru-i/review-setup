#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=lib/github.sh
source "${SCRIPT_DIR}/lib/github.sh"
# shellcheck source=lib/worktree.sh
source "${SCRIPT_DIR}/lib/worktree.sh"

usage() {
    echo "Usage: $(basename "$0") <PR_URL>"
    echo ""
    echo "Create a git worktree for reviewing a GitHub pull request."
    echo ""
    echo "Arguments:"
    echo "  PR_URL  GitHub PR URL (e.g., https://github.com/owner/repo/pull/123)"
    exit 1
}

check_prerequisites() {
    local missing=0

    for cmd in gh ghq git; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "Required command not found: ${cmd}"
            missing=1
        fi
    done

    if [[ "${missing}" -eq 1 ]]; then
        return 1
    fi

    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI is not authenticated."
        log_error "Run: gh auth login"
        return 1
    fi
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    local pr_url="$1"

    init_logging
    log "Starting PR review setup"

    check_prerequisites

    parse_pr_url "${pr_url}"
    find_repo_path "${PR_OWNER}" "${PR_REPO}"
    create_worktree_with_pr "${PR_NUMBER}" "${REPO_PATH}" "${PR_REPO}"

    log "PR review setup complete"
    log "Worktree: ${WORKTREE_PATH}"
}

main "$@"
