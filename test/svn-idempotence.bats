#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# svn-idempotence.bats - Idempotence tests for platypus svn pull/push
#

load test_helper

# Use Docker-backed SVN; skip if unavailable
setup() {
  setup_docker_svn
}

# Helper: create SVN repo, git-svn clone, origin remote, and marker
create_svn_fixture() {
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

    if git rev-parse --verify main >/dev/null 2>&1; then
      git checkout main
      git reset --hard git-svn
    else
      git checkout -b main git-svn
    fi

    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"

    git remote add origin "$remote"
    git push -u origin main
    git push origin main:refs/heads/svn-marker
    git fetch origin

    # Ensure svn branch exists for pulls
    git checkout -B svn git-svn
    git checkout main
  ) >/dev/null 2>&1

  echo "$svn_url|$git_repo"
}

# bats test_tags=docker
@test "svn push is idempotent when no new commits" {
  local setup svn_url git_repo before_revs after_revs initial_marker after_marker
  setup=$(create_svn_fixture "idempotent-push")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  before_revs=$(svn log "$svn_url" --quiet | grep -c "^r")
  initial_marker=$(cd "$git_repo" && git rev-parse origin/svn-marker)

  cd "$git_repo"
  run platypus svn push
  [ "$status" -eq 0 ]
  git fetch origin >/dev/null 2>&1
  after_marker=$(git rev-parse origin/svn-marker)
  [ "$initial_marker" = "$after_marker" ]
  after_revs=$(svn log "$svn_url" --quiet | grep -c "^r")
  [ "$before_revs" -eq "$after_revs" ]

  # Second run should also be a no-op
  run platypus svn push
  [ "$status" -eq 0 ]
  git fetch origin >/dev/null 2>&1
  after_marker=$(git rev-parse origin/svn-marker)
  [ "$initial_marker" = "$after_marker" ]
  after_revs=$(svn log "$svn_url" --quiet | grep -c "^r")
  [ "$before_revs" -eq "$after_revs" ]
}

# bats test_tags=docker
@test "svn pull is idempotent when no new SVN revisions" {
  local setup svn_url git_repo before_rev after_rev before_tip after_tip
  setup=$(create_svn_fixture "idempotent-pull")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  before_rev=$(svn log "$svn_url" --quiet | grep -c "^r")
  before_tip=$(cd "$git_repo" && git rev-parse svn)

  cd "$git_repo"
  run platypus svn pull
  [ "$status" -eq 0 ]
  after_tip=$(git rev-parse svn)
  [ "$before_tip" = "$after_tip" ]
  after_rev=$(svn log "$svn_url" --quiet | grep -c "^r")
  [ "$before_rev" -eq "$after_rev" ]

  # Second run should also be a no-op
  run platypus svn pull
  [ "$status" -eq 0 ]
  after_tip=$(git rev-parse svn)
  [ "$before_tip" = "$after_tip" ]
  after_rev=$(svn log "$svn_url" --quiet | grep -c "^r")
  [ "$before_rev" -eq "$after_rev" ]
}

