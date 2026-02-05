#!/bin/bash
# github.sh — PR URL解析

PR_NUMBER=""
PR_OWNER=""
PR_REPO=""

validate_pr_url() {
    local pr_url="$1"
    if [[ ! "${pr_url}" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+$ ]]; then
        return 1
    fi
}

parse_pr_url() {
    local pr_url="$1"

    if ! validate_pr_url "${pr_url}"; then
        log_error "Invalid PR URL: ${pr_url}"
        log_error "Expected format: https://github.com/{owner}/{repo}/pull/{number}"
        return 1
    fi

    # URLからowner/repo/numberを抽出
    PR_OWNER="$(echo "${pr_url}" | sed 's|https://github.com/||' | cut -d'/' -f1)"
    PR_REPO="$(echo "${pr_url}" | sed 's|https://github.com/||' | cut -d'/' -f2)"
    PR_NUMBER="$(echo "${pr_url}" | sed 's|https://github.com/||' | cut -d'/' -f4)"

    export PR_OWNER PR_REPO PR_NUMBER

    log "PR: ${PR_OWNER}/${PR_REPO}#${PR_NUMBER}"

    # gh pr viewでPRの存在を確認
    if ! gh pr view "${PR_NUMBER}" --repo "${PR_OWNER}/${PR_REPO}" --json state >/dev/null 2>&1; then
        log_error "PR not found: ${PR_OWNER}/${PR_REPO}#${PR_NUMBER}"
        log_error "Check that the PR exists and you have access to the repository."
        return 1
    fi

    log "PR verified successfully"
}
