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

#------------------------------------------------------------------------------
# Complex end-to-end scenario: SVN + multiple subtrees
#------------------------------------------------------------------------------

# bats test_tags=docker
@test "complex: SVN repo with subtrees, upstream changes, merge, sync back" {
  #---------------------------------------------------------------------------
  # SETUP: Create SVN repo with two library directories
  #---------------------------------------------------------------------------
  
  local svn_name="complex-test"
  
  # Create SVN repository with initial structure
  SVN_URL=$(create_svn_repo "$svn_name")
  
  # Add initial structure to SVN: two library directories
  local svn_wc="$TEST_TMP/svn-wc"
  svn checkout "$SVN_URL" "$svn_wc" --quiet
  (
    cd "$svn_wc"
    
    # Create lib1 directory with initial content
    mkdir -p lib1
    echo "lib1 initial content" > lib1/lib1.txt
    echo "# Lib1 README" > lib1/README.md
    svn add lib1
    svn commit -m "Add lib1 directory" --quiet
    
    # Create lib2 directory with initial content
    mkdir -p lib2
    echo "lib2 initial content" > lib2/lib2.txt
    echo "# Lib2 README" > lib2/README.md
    svn add lib2
    svn commit -m "Add lib2 directory" --quiet
    
    # Add a main file
    echo "Main project file" > main.txt
    svn add main.txt
    svn commit -m "Add main.txt" --quiet
  )
  
  #---------------------------------------------------------------------------
  # Clone SVN to Git monorepo
  #---------------------------------------------------------------------------
  
  GIT_REPO="$TEST_TMP/monorepo"
  mkdir -p "$GIT_REPO"
  (
    cd "$GIT_REPO"
    git svn init "$SVN_URL"
    git svn fetch
    
    # Create main branch
    if git rev-parse --verify main >/dev/null 2>&1; then
      git checkout main
      git reset --hard git-svn
    else
      git checkout -b main git-svn
    fi
    
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
  ) >/dev/null 2>&1
  
  # Set up origin for pushing/marker
  REMOTE_REPO=$(create_bare_repo "origin")
  (
    cd "$GIT_REPO"
    git remote add origin "$REMOTE_REPO"
    git push -u origin main
    git push origin main:refs/heads/svn-marker
    git fetch origin
  ) >/dev/null 2>&1
  
  #---------------------------------------------------------------------------
  # Create upstream repos by splitting out the lib directories
  # This preserves the history relationship for proper merges
  #---------------------------------------------------------------------------
  
  cd "$GIT_REPO"
  
  # Create bare repos for the upstreams
  local lib1_bare="$TEST_TMP/lib1-upstream.git"
  local lib2_bare="$TEST_TMP/lib2-upstream.git"
  git init --bare "$lib1_bare" >/dev/null 2>&1
  git init --bare "$lib2_bare" >/dev/null 2>&1
  
  # Split lib1 out with --rejoin to establish the subtree merge base
  git subtree split --prefix=lib1 --rejoin -b lib1-split >/dev/null 2>&1
  git push "$lib1_bare" lib1-split:main >/dev/null 2>&1
  
  # Split lib2 out with --rejoin to establish the subtree merge base
  git subtree split --prefix=lib2 --rejoin -b lib2-split >/dev/null 2>&1
  git push "$lib2_bare" lib2-split:main >/dev/null 2>&1
  
  # Create working directories for the upstream repos
  local lib1_work="$TEST_TMP/lib1-work"
  local lib2_work="$TEST_TMP/lib2-work"
  
  git clone "$lib1_bare" "$lib1_work" >/dev/null 2>&1
  (cd "$lib1_work" && git config user.name "$GIT_AUTHOR_NAME" && git config user.email "$GIT_AUTHOR_EMAIL") >/dev/null 2>&1
  
  git clone "$lib2_bare" "$lib2_work" >/dev/null 2>&1
  (cd "$lib2_work" && git config user.name "$GIT_AUTHOR_NAME" && git config user.email "$GIT_AUTHOR_EMAIL") >/dev/null 2>&1
  
  #---------------------------------------------------------------------------
  # Initialize subtrees in monorepo (pointing to the upstream repos)
  # The --rejoin from split already established the merge base
  #---------------------------------------------------------------------------
  
  # Initialize lib1 as a subtree and record the split sha
  run platypus subtree init lib1 --remote "$lib1_bare" -b main
  [ "$status" -eq 0 ]
  # Record the split sha for proper incremental pulls
  local lib1_split_sha
  lib1_split_sha=$(git rev-parse lib1-split)
  git config --file .gitsubtrees subtree.lib1.splitSha "$lib1_split_sha"
  git branch -D lib1-split >/dev/null 2>&1
  
  # Initialize lib2 as a subtree and record the split sha
  run platypus subtree init lib2 --remote "$lib2_bare" -b main
  [ "$status" -eq 0 ]
  local lib2_split_sha
  lib2_split_sha=$(git rev-parse lib2-split)
  git config --file .gitsubtrees subtree.lib2.splitSha "$lib2_split_sha"
  git branch -D lib2-split >/dev/null 2>&1
  
  git add .gitsubtrees
  git commit --amend --no-edit >/dev/null 2>&1
  
  # Push to origin and update marker to current state
  # This ensures we only push NEW changes to SVN (not the rejoin setup)
  git push origin main --force >/dev/null 2>&1
  git push origin main:refs/heads/svn-marker --force >/dev/null 2>&1
  git fetch origin >/dev/null 2>&1

  # Verify both subtrees are configured
  run platypus subtree list --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib1"* ]]
  [[ "$output" == *"lib2"* ]]
  
  # Push to origin
  git push origin main
  
  #---------------------------------------------------------------------------
  # Make changes in upstream lib1
  #---------------------------------------------------------------------------
  
  (
    cd "$lib1_work"
    echo "New feature in lib1" > feature1.txt
    git add feature1.txt
    git commit -m "Add feature1 to lib1"
    git push origin main
  ) >/dev/null 2>&1
  
  #---------------------------------------------------------------------------
  # Make changes in upstream lib2
  #---------------------------------------------------------------------------
  
  (
    cd "$lib2_work"
    echo "New feature in lib2" > feature2.txt
    git add feature2.txt
    git commit -m "Add feature2 to lib2"
    git push origin main
  ) >/dev/null 2>&1
  
  #---------------------------------------------------------------------------
  # Make a local change in monorepo (outside subtrees)
  #---------------------------------------------------------------------------
  
  cd "$GIT_REPO"
  echo "Updated main file" >> main.txt
  git add main.txt
  git commit -m "Update main.txt in monorepo"
  git push origin main
  
  #---------------------------------------------------------------------------
  # Pull changes from both subtrees (creates merge commits)
  #---------------------------------------------------------------------------
  
  # Pull lib1 changes
  run platypus subtree pull lib1
  [ "$status" -eq 0 ]
  
  # Verify lib1 feature is now in monorepo
  [ -f "lib1/feature1.txt" ]
  
  # Pull lib2 changes
  run platypus subtree pull lib2
  [ "$status" -eq 0 ]
  
  # Verify lib2 feature is now in monorepo
  [ -f "lib2/feature2.txt" ]
  
  # Push merged changes to origin
  git push origin main
  
  #---------------------------------------------------------------------------
  # Verify the history has merge commits
  #---------------------------------------------------------------------------
  
  # Count merge commits (commits with more than one parent)
  local merge_count
  merge_count=$(git log --merges --oneline | wc -l | tr -d ' ')
  [ "$merge_count" -ge 2 ]  # At least 2 merges (one per subtree pull)
  
  #---------------------------------------------------------------------------
  # Sync everything to SVN
  #---------------------------------------------------------------------------
  
  # First, ensure SVN mirror is up to date
  run platypus svn pull
  [ "$status" -eq 0 ]
  
  # Push to SVN (use --push-conflicts for merge commits from subtree pulls)
  run platypus svn push --push-conflicts
  # Status 2 = completed with conflicts which is acceptable for merge commits
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
  
  #---------------------------------------------------------------------------
  # Verify SVN has all the changes
  #---------------------------------------------------------------------------
  
  # Checkout SVN to verify
  local svn_verify="$TEST_TMP/svn-verify"
  rm -rf "$svn_verify"
  svn checkout "$SVN_URL" "$svn_verify" --quiet
  
  # Check all files are present
  [ -f "$svn_verify/main.txt" ]
  [ -f "$svn_verify/lib1/lib1.txt" ]
  [ -f "$svn_verify/lib1/feature1.txt" ]
  [ -f "$svn_verify/lib2/lib2.txt" ]
  [ -f "$svn_verify/lib2/feature2.txt" ]
  
  # Verify content
  grep -q "Updated main file" "$svn_verify/main.txt"
  grep -q "New feature in lib1" "$svn_verify/lib1/feature1.txt"
  grep -q "New feature in lib2" "$svn_verify/lib2/feature2.txt"
  
  #---------------------------------------------------------------------------
  # Verify SVN history is linear (first-parent walk excludes subtree internals)
  #---------------------------------------------------------------------------
  
  # SVN log should show clean commits, not subtree internal history
  local svn_log
  svn_log=$(svn log "$SVN_URL" --quiet)
  
  # Should have multiple revisions
  local rev_count
  rev_count=$(echo "$svn_log" | grep -c "^r[0-9]" || true)
  [ "$rev_count" -ge 4 ]  # Initial commits + updates
}

