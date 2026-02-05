#!/bin/bash
# worktree.sh — Git worktree操作

REPO_PATH=""
WORKTREE_PATH=""

find_repo_path() {
    local owner="$1"
    local repo="$2"

    local ghq_root
    ghq_root="$(ghq root)"

    REPO_PATH="${ghq_root}/github.com/${owner}/${repo}"
    export REPO_PATH

    if [[ ! -d "${REPO_PATH}" ]]; then
        log_error "Repository not found: ${REPO_PATH}"
        log_error "Run: ghq get ${owner}/${repo}"
        return 1
    fi

    log "Repository found: ${REPO_PATH}"
}

create_worktree_with_pr() {
    local pr_number="$1"
    local repo_path="$2"
    local repo_name="$3"

    local worktree_dir="${repo_path}/../${repo_name}.worktrees"
    WORKTREE_PATH="${worktree_dir}/pr-${pr_number}"
    export WORKTREE_PATH

    # 既存worktreeがあれば再利用
    if [[ -d "${WORKTREE_PATH}" ]]; then
        log "Reusing existing worktree: ${WORKTREE_PATH}"
        return 0
    fi

    mkdir -p "${worktree_dir}"

    log "Creating worktree: ${WORKTREE_PATH}"
    if ! git -C "${repo_path}" worktree add --detach "${WORKTREE_PATH}"; then
        log_error "Failed to create worktree"
        return 1
    fi

    log "Checking out PR #${pr_number}"
    if ! gh pr checkout "${pr_number}" --repo "${PR_OWNER}/${PR_REPO}" --dir "${WORKTREE_PATH}" 2>/dev/null; then
        # --dir が使えない場合は worktree 内で直接実行
        if ! (cd "${WORKTREE_PATH}" && gh pr checkout "${pr_number}" --repo "${PR_OWNER}/${PR_REPO}"); then
            log_error "Failed to checkout PR #${pr_number}"
            log "Cleaning up worktree..."
            git -C "${repo_path}" worktree remove --force "${WORKTREE_PATH}" 2>/dev/null
            return 1
        fi
    fi

    log "Worktree ready: ${WORKTREE_PATH}"
}
