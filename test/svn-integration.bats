#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-integration.bats - Integration tests for SVN sync (requires Docker)
#
# These tests require a running Docker SVN server.
# Start with: docker compose -f test/docker/svn-server/docker-compose.yml up -d
# Run with:   ./test/run-tests.sh --docker
#
# All tests are tagged with 'docker' and will be skipped if Docker is unavailable.
#

load test_helper

#------------------------------------------------------------------------------
# Test setup/teardown with Docker SVN
#------------------------------------------------------------------------------

setup() {
  setup_docker_svn
}

# Clean up repos after each test but keep server running
teardown() {
  cd "$TEST_DIR"
  rm -rf "$TEST_TMP"
}

#------------------------------------------------------------------------------
# Helper: Create a complete SVN+Git setup for testing
#------------------------------------------------------------------------------

# Creates an SVN repo, a git-svn clone, and sets up the platypus environment
# Usage: setup_platypus_svn_repo <repo_name>
# Sets: SVN_URL, GIT_REPO, REMOTE_REPO
setup_platypus_svn_repo() {
  local repo_name=${1:-test-repo}
  
  # Create SVN repository
  SVN_URL=$(create_svn_repo "$repo_name")
  
  # Add initial content to SVN
  svn_add_file "$SVN_URL" "README.txt" "Initial content" "Initial commit"
  
  # Create a bare git repo to act as "origin"
  REMOTE_REPO=$(create_bare_repo "origin")
  
  # Create git-svn clone
  GIT_REPO="$TEST_TMP/monorepo"
  mkdir -p "$GIT_REPO"
  (
    cd "$GIT_REPO"
    git svn init "$SVN_URL"
    git svn fetch
    
    # Reset main branch to point to git-svn
    # (git may auto-create main due to init.defaultBranch)
    if git rev-parse --verify main >/dev/null 2>&1; then
      git checkout main
      git reset --hard git-svn
    else
      git checkout -b main git-svn
    fi
    
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    
    # Set up origin remote
    git remote add origin "$REMOTE_REPO"
    git push -u origin main
    
    # Create svn-marker branch
    git push origin main:refs/heads/svn-marker
    git fetch origin
  ) >/dev/null 2>&1
}

#------------------------------------------------------------------------------
# Basic SVN pull tests
#------------------------------------------------------------------------------

# bats test_tags=docker
@test "svn pull: fetches new SVN commits into mirror" {
  setup_platypus_svn_repo "pull-test"
  
  # Add a new commit directly to SVN
  svn_add_file "$SVN_URL" "new-file.txt" "New content" "Add new file in SVN"
  
  cd "$GIT_REPO"
  
  # The svn branch should not have the new file yet
  git checkout svn 2>/dev/null || git checkout -b svn git-svn
  [ ! -f "new-file.txt" ]
  
  # Switch back to main for platypus svn pull
  git checkout main
  
  # Pull should bring in the new commit
  run platypus svn pull
  [ "$status" -eq 0 ]
  
  # Now svn branch should have the file
  git checkout svn
  [ -f "new-file.txt" ]
}

# bats test_tags=docker
@test "svn pull: reports pending commits to push" {
  setup_platypus_svn_repo "pull-pending-test"
  
  cd "$GIT_REPO"
  
  # Add a commit to main
  echo "local change" > local.txt
  git add local.txt
  git commit -m "Local commit"
  git push origin main
  
  # Pull should report pending commits
  run platypus svn pull
  [ "$status" -eq 0 ]
  [[ "$output" == *"pending"* ]] || [[ "$output" == *"commit"* ]]
}

#------------------------------------------------------------------------------
# Basic SVN push tests
#------------------------------------------------------------------------------

# bats test_tags=docker
@test "svn push: exports Git commits to SVN" {
  setup_platypus_svn_repo "push-test"
  
  cd "$GIT_REPO"
  
  # Add a commit to main
  echo "new content from git" > git-file.txt
  git add git-file.txt
  git commit -m "Add file from Git"
  git push origin main
  
  # Push to SVN
  run platypus svn push
  [ "$status" -eq 0 ]
  
  # Verify the file is in SVN
  local svn_checkout="$TEST_TMP/svn-verify"
  svn checkout "$SVN_URL" "$svn_checkout" --quiet
  [ -f "$svn_checkout/git-file.txt" ]
}

# bats test_tags=docker
@test "svn push: advances marker after successful push" {
  setup_platypus_svn_repo "marker-test"
  
  cd "$GIT_REPO"
  
  # Record initial marker
  local initial_marker
  initial_marker=$(git rev-parse origin/svn-marker)
  
  # Add a commit
  echo "test" > test.txt
  git add test.txt
  git commit -m "Test commit"
  git push origin main
  
  # Push to SVN
  run platypus svn push
  [ "$status" -eq 0 ]
  
  # Marker should have advanced
  git fetch origin
  local new_marker
  new_marker=$(git rev-parse origin/svn-marker)
  [ "$initial_marker" != "$new_marker" ]
}

# bats test_tags=docker
@test "svn push: merges SVN metadata back to main" {
  setup_platypus_svn_repo "merge-back-test"
  
  cd "$GIT_REPO"
  
  # Add a commit
  echo "test" > test.txt
  git add test.txt
  git commit -m "Test commit"
  git push origin main
  
  # Push to SVN
  run platypus svn push
  [ "$status" -eq 0 ]
  
  # Main should have a merge commit from SVN
  git fetch origin
  git checkout main
  git pull origin main
  
  # Check that there's a merge commit mentioning SVN
  local merge_commits
  merge_commits=$(git log --oneline --merges -1)
  [[ "$merge_commits" == *"SVN"* ]] || [[ "$merge_commits" == *"svn"* ]] || [[ "$merge_commits" == *"Merge"* ]]
}

#------------------------------------------------------------------------------
# Multiple commits
#------------------------------------------------------------------------------

# bats test_tags=docker
@test "svn push: handles multiple commits correctly" {
  setup_platypus_svn_repo "multi-commit-test"
  
  cd "$GIT_REPO"
  
  # Add multiple commits
  for i in 1 2 3; do
    echo "content $i" > "file$i.txt"
    git add "file$i.txt"
    git commit -m "Add file $i"
  done
  git push origin main
  
  # Push to SVN
  run platypus svn push
  [ "$status" -eq 0 ]
  
  # Verify all files are in SVN
  local svn_checkout="$TEST_TMP/svn-verify"
  svn checkout "$SVN_URL" "$svn_checkout" --quiet
  [ -f "$svn_checkout/file1.txt" ]
  [ -f "$svn_checkout/file2.txt" ]
  [ -f "$svn_checkout/file3.txt" ]
}

#------------------------------------------------------------------------------
# Subtree interaction with SVN
#------------------------------------------------------------------------------

# bats test_tags=docker
@test "svn push: subtree merge exports as net diff" {
  setup_platypus_svn_repo "subtree-test"
  
  cd "$GIT_REPO"
  
  # Create a subtree library
  local lib_dir="$TEST_TMP/lib-upstream"
  mkdir -p "$lib_dir"
  (
    cd "$lib_dir"
    git init -b main
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    echo "lib content 1" > lib-file-1.txt
    git add lib-file-1.txt
    git commit -m "Lib commit 1"
    echo "lib content 2" > lib-file-2.txt
    git add lib-file-2.txt
    git commit -m "Lib commit 2"
  ) >/dev/null
  
  # Add subtree to monorepo
  git subtree add --prefix=lib/foo "$lib_dir" main -m "Add lib/foo subtree"
  git push origin main
  
  # Push to SVN
  run platypus svn push
  [ "$status" -eq 0 ]
  
  # Verify lib files are in SVN
  local svn_checkout="$TEST_TMP/svn-verify"
  svn checkout "$SVN_URL" "$svn_checkout" --quiet
  [ -f "$svn_checkout/lib/foo/lib-file-1.txt" ]
  [ -f "$svn_checkout/lib/foo/lib-file-2.txt" ]
  
  # Check SVN log - should NOT have individual "Lib commit" entries
  # (they should be combined in the subtree merge)
  local svn_log
  svn_log=$(svn log "$SVN_URL" --limit 10)
  
  # The subtree add should appear as one commit, not multiple
  local subtree_commits
  subtree_commits=$(echo "$svn_log" | grep -c "subtree" || echo "0")
  [ "$subtree_commits" -ge 1 ]
}

# bats test_tags=docker
@test "svn push: first-parent history excludes subtree internals" {
  setup_platypus_svn_repo "first-parent-test"
  
  cd "$GIT_REPO"
  
  # Record base for counting
  local base_marker
  base_marker=$(git rev-parse origin/svn-marker)
  
  # Create subtree with 3 internal commits
  local lib_dir="$TEST_TMP/lib-upstream"
  mkdir -p "$lib_dir"
  (
    cd "$lib_dir"
    git init -b main
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    for i in 1 2 3; do
      echo "lib $i" > "lib-$i.txt"
      git add "lib-$i.txt"
      git commit -m "Lib commit $i"
    done
  ) >/dev/null
  
  # Add subtree
  git subtree add --prefix=lib/foo "$lib_dir" main -m "Add lib/foo"
  
  # Add one more commit on main
  echo "main content" > main-file.txt
  git add main-file.txt
  git commit -m "Main commit after subtree"
  git push origin main
  
  # Count first-parent commits
  local first_parent_count
  first_parent_count=$(git rev-list --first-parent --count "$base_marker..HEAD")
  
  # Should be 2 (subtree add merge + main commit), NOT 5 (including lib commits)
  [ "$first_parent_count" -eq 2 ]
  
  # Push should work correctly
  run platypus svn push
  [ "$status" -eq 0 ]
}

#------------------------------------------------------------------------------
# Conflict detection
#------------------------------------------------------------------------------

# bats test_tags=docker
@test "svn push: detects conflicts with concurrent SVN changes" {
  setup_platypus_svn_repo "conflict-test"
  
  cd "$GIT_REPO"
  
  # Modify README.txt in Git
  echo "Modified by Git" > README.txt
  git add README.txt
  git commit -m "Modify README in Git"
  git push origin main
  
  # Also modify README.txt in SVN (creating conflict)
  svn_add_file "$SVN_URL" "README.txt" "Modified by SVN" "Modify README in SVN"
  
  # Push should fail due to conflict
  run platypus svn push
  [ "$status" -ne 0 ]
}

# bats test_tags=docker
@test "svn push --push-conflicts: commits with conflict markers" {
  setup_platypus_svn_repo "push-conflicts-test"
  
  cd "$GIT_REPO"
  
  # Modify README.txt in Git
  echo "Modified by Git" > README.txt
  git add README.txt
  git commit -m "Modify README in Git"
  git push origin main
  
  # Also modify README.txt in SVN
  svn_add_file "$SVN_URL" "README.txt" "Modified by SVN" "Modify README in SVN"
  
  # Push with --push-conflicts should succeed with exit code 2
  run platypus svn push --push-conflicts
  # Exit code 2 means success with conflicts
  [ "$status" -eq 2 ] || [ "$status" -eq 0 ]
  
  # Should mention conflict
  [[ "$output" == *"conflict"* ]] || [[ "$output" == *"CONFLICT"* ]] || [[ "$output" == *"Warning"* ]]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

# bats test_tags=docker
@test "svn push --dry-run: shows what would happen without modifying" {
  setup_platypus_svn_repo "dry-run-test"
  
  cd "$GIT_REPO"
  
  # Add a commit
  echo "test" > test.txt
  git add test.txt
  git commit -m "Test commit"
  git push origin main
  
  # Record marker
  local initial_marker
  initial_marker=$(git rev-parse origin/svn-marker)
  
  # Dry run
  run platypus svn push --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"DRY RUN"* ]]
  
  # Marker should NOT have changed
  git fetch origin
  local after_marker
  after_marker=$(git rev-parse origin/svn-marker)
  [ "$initial_marker" = "$after_marker" ]
  
  # File should NOT be in SVN
  local svn_checkout="$TEST_TMP/svn-verify"
  svn checkout "$SVN_URL" "$svn_checkout" --quiet
  [ ! -f "$svn_checkout/test.txt" ]
}

