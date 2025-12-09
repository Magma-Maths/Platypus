#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# svn-failures.bats - Failure modes for git-svn operations
#

load test_helper

setup() {
  setup_docker_svn
}

create_svn_failure_fixture() {
  local name=$1
  local svn_url remote git_repo

  svn_url=$(create_svn_repo "$name" 2>/dev/null | tr -d '\r')
  svn_add_file "$svn_url" "README.txt" "Initial content" "Initial import" >/dev/null 2>&1

  remote=$(create_bare_repo "origin-$name" 2>/dev/null | tr -d '\r')
  git_repo="$TEST_TMP/$name-mono"
  mkdir -p "$git_repo"

  (
    cd "$git_repo"
    git svn init "$svn_url"
    git svn fetch
    git checkout -b main git-svn
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    git remote add origin "$remote"
    git push -u origin main
    git push origin main:refs/heads/svn-marker
    git fetch origin
  ) >/dev/null 2>&1

  echo "$svn_url|$git_repo"
}

make_git_wrapper() {
  local mode=$1
  local dir="$TEST_TMP/fake-git-$mode"
  mkdir -p "$dir"
  cat > "$dir/git" <<'EOF'
#!/usr/bin/env bash
case "$GIT_WRAPPER_MODE" in
  rebase_fail)
    if [[ "$1" == "svn" && "$2" == "rebase" ]]; then
      echo "forced git svn rebase failure" >&2
      exit 1
    fi
    ;;
  dcommit_fail)
    if [[ "$1" == "svn" && "$2" == "dcommit" ]]; then
      echo "forced git svn dcommit failure" >&2
      exit 1
    fi
    ;;
esac
exec /usr/bin/env git "$@"
EOF
  chmod +x "$dir/git"
  export PATH="$dir:$PATH"
  export GIT_WRAPPER_MODE="$mode"
}

# bats test_tags=docker
@test "svn update aborts cleanly when git svn rebase fails" {
  local setup svn_url git_repo
  setup=$(create_svn_failure_fixture "rebase-fail-pull")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  make_git_wrapper rebase_fail
  cd "$git_repo"

  run platypus svn update
  [ "$status" -ne 0 ]
  [[ "$output" == *"git svn rebase failed"* ]]

  # Ensure marker wasn't moved
  git fetch origin >/dev/null 2>&1
  local marker
  marker=$(git rev-parse origin/svn-marker)
  [ "$marker" = "$(git rev-parse main)" ]
}

# bats test_tags=docker
@test "svn export stops before marker advance when dcommit fails" {
  local setup svn_url git_repo before_marker after_marker rev_before rev_after
  setup=$(create_svn_failure_fixture "dcommit-fail")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  cd "$git_repo"
  echo "change" > file.txt
  git add file.txt
  git commit -m "Change to export"
  git push origin main

  rev_before=$(svn log "$svn_url" --quiet | grep -c "^r")
  before_marker=$(git rev-parse origin/svn-marker)

  make_git_wrapper dcommit_fail

  run platypus svn export
  [ "$status" -ne 0 ]
  [[ "$output" == *"dcommit"* ]] || [[ "$output" == *"svn dcommit"* ]]

  git fetch origin >/dev/null 2>&1
  after_marker=$(git rev-parse origin/svn-marker)
  [ "$before_marker" = "$after_marker" ]

  rev_after=$(svn log "$svn_url" --quiet | grep -c "^r")
  [ "$rev_after" -eq "$rev_before" ]
}

