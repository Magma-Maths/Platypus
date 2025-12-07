#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# svn-env-overrides.bats - Environment override tests for platypus svn
#

load test_helper

setup() {
  setup_docker_svn
}

create_svn_env_fixture() {
  local name=$1
  local svn_url remote git_repo

  svn_url=$(create_svn_repo "$name" 2>/dev/null | tr -d '\r')
  svn_add_file "$svn_url" "README.txt" "Initial content" "Initial import" >/dev/null 2>&1

  remote=$(create_bare_repo "remote-$name" 2>/dev/null | tr -d '\r')
  git_repo="$TEST_TMP/$name-mono"
  mkdir -p "$git_repo"

  (
    cd "$git_repo"
    git svn init "$svn_url"
    git svn fetch
    git checkout -b main git-svn
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    git remote add remote "$remote"
    git push -u remote main
    git push remote main:refs/heads/svn-marker
    git fetch remote
  ) >/dev/null 2>&1

  echo "$svn_url|$git_repo|$remote"
}

@test "svn push respects REMOTE and MAIN overrides" {
  local setup svn_url git_repo remote marker_before marker_after rev_before rev_after
  setup=$(create_svn_env_fixture "env-remote-main")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)
  remote=$(echo "$setup" | cut -d'|' -f3)

  cd "$git_repo"

  # Rename main -> master to exercise MAIN override
  git branch -m main master
  git push remote master:master
  git push remote master:refs/heads/svn-marker --force
  git fetch remote

  echo "override change" > override.txt
  git add override.txt
  git commit -m "Override change"
  git push remote master

  marker_before=$(git rev-parse refs/remotes/remote/svn-marker)
  rev_before=$(svn log "$svn_url" --quiet | grep -c "^r")

  REMOTE=remote MAIN=master run platypus svn push
  [ "$status" -eq 0 ]

  git fetch remote >/dev/null 2>&1
  marker_after=$(git rev-parse refs/remotes/remote/svn-marker)
  [ "$marker_after" != "$marker_before" ]

  rev_after=$(svn log "$svn_url" --quiet | grep -c "^r")
  [ "$rev_after" -gt "$rev_before" ]
}

@test "svn pull uses custom SVN_REMOTE_REF and SVN_BRANCH" {
  local setup svn_url git_repo remote rev_before rev_after
  setup=$(create_svn_env_fixture "env-svn-ref")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)
  remote=$(echo "$setup" | cut -d'|' -f3)

  cd "$git_repo"

  # Move git-svn tracking ref and remove default to force override usage
  git update-ref refs/remotes/custom-svn refs/remotes/git-svn
  git update-ref -d refs/remotes/git-svn
  git checkout -B mirror-svn refs/remotes/custom-svn
  git checkout main

  # Add change directly to SVN
  svn_add_file "$svn_url" "new-svn-file.txt" "SVN change" "SVN change"
  rev_before=$(svn log "$svn_url" --quiet | grep -c "^r")

  SVN_REMOTE_REF=refs/remotes/custom-svn SVN_BRANCH=mirror-svn REMOTE=remote run platypus svn pull
  [ "$status" -eq 0 ]

  # The custom branch should now have the new file
  git checkout mirror-svn
  [ -f new-svn-file.txt ]

  rev_after=$(svn log "$svn_url" --quiet | grep -c "^r")
  [ "$rev_after" -ge "$rev_before" ]
}

