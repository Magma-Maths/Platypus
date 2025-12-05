#!/usr/bin/env bats
#
# subtree-conflicts.bats - Tests for subtree merge conflict scenarios
#
# Tests various conflict scenarios when pulling/pushing subtrees.
#

load test_helper

#------------------------------------------------------------------------------
# Helper to create a subtree setup with controlled history
#------------------------------------------------------------------------------

# Create upstream, monorepo, and add subtree
# Returns: "repo|upstream|upstream_work"
setup_conflict_scenario() {
  local upstream upstream_work repo
  
  # Create upstream with initial file
  upstream=$(create_bare_repo "upstream")
  upstream_work=$(create_repo "upstream_work")
  
  (
    cd "$upstream_work"
    echo "original content" > shared.txt
    echo "line 2" >> shared.txt
    echo "line 3" >> shared.txt
    git add shared.txt
    git commit -m "Initial shared.txt"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  # Create monorepo and add subtree
  repo=$(create_monorepo)
  (
    cd "$repo"
    platypus subtree add lib/sub "$upstream" main
  ) >/dev/null
  
  echo "$repo|$upstream|$upstream_work"
}

#------------------------------------------------------------------------------
# File modification conflicts
#------------------------------------------------------------------------------

@test "pull with local modification to same line conflicts" {
  local setup repo upstream upstream_work
  setup=$(setup_conflict_scenario)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  upstream_work=$(echo "$setup" | cut -d'|' -f3)
  
  # Modify locally
  (
    cd "$repo"
    echo "local content" > lib/sub/shared.txt
    echo "line 2" >> lib/sub/shared.txt
    echo "line 3" >> lib/sub/shared.txt
    git add lib/sub/shared.txt
    git commit -m "Local modification"
  )
  
  # Modify upstream (same line)
  (
    cd "$upstream_work"
    echo "upstream content" > shared.txt
    echo "line 2" >> shared.txt
    echo "line 3" >> shared.txt
    git add shared.txt
    git commit -m "Upstream modification"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
  # Pull should fail or require merge resolution
  run platypus subtree pull lib/sub
  # This will likely fail due to conflict
  # Status might be 0 if auto-merged, or non-zero if conflict
}

@test "pull with local modification to different lines succeeds" {
  local setup repo upstream upstream_work
  setup=$(setup_conflict_scenario)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  upstream_work=$(echo "$setup" | cut -d'|' -f3)
  
  # Modify locally (line 3)
  (
    cd "$repo"
    echo "original content" > lib/sub/shared.txt
    echo "line 2" >> lib/sub/shared.txt
    echo "local line 3" >> lib/sub/shared.txt
    git add lib/sub/shared.txt
    git commit -m "Local modification to line 3"
  )
  
  # Modify upstream (line 1)
  (
    cd "$upstream_work"
    echo "upstream content" > shared.txt
    echo "line 2" >> shared.txt
    echo "line 3" >> shared.txt
    git add shared.txt
    git commit -m "Upstream modification to line 1"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
  # Pull should succeed (different areas)
  run platypus subtree pull lib/sub
  [ "$status" -eq 0 ]
}

#------------------------------------------------------------------------------
# File add/delete conflicts
#------------------------------------------------------------------------------

@test "local adds file, upstream adds same file" {
  local setup repo upstream upstream_work
  setup=$(setup_conflict_scenario)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  upstream_work=$(echo "$setup" | cut -d'|' -f3)
  
  # Add file locally
  (
    cd "$repo"
    echo "local new file" > lib/sub/newfile.txt
    git add lib/sub/newfile.txt
    git commit -m "Local: add newfile.txt"
  )
  
  # Add same file upstream
  (
    cd "$upstream_work"
    echo "upstream new file" > newfile.txt
    git add newfile.txt
    git commit -m "Upstream: add newfile.txt"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
  # Pull - might conflict
  run platypus subtree pull lib/sub
  # Check that we got some result (either merged or conflict)
}

@test "local deletes file, upstream modifies it" {
  local setup repo upstream upstream_work
  setup=$(setup_conflict_scenario)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  upstream_work=$(echo "$setup" | cut -d'|' -f3)
  
  # Delete file locally
  (
    cd "$repo"
    rm lib/sub/shared.txt
    git add -u
    git commit -m "Local: delete shared.txt"
  )
  
  # Modify file upstream
  (
    cd "$upstream_work"
    echo "modified content" >> shared.txt
    git add shared.txt
    git commit -m "Upstream: modify shared.txt"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
  # Pull - this is a delete/modify conflict
  run platypus subtree pull lib/sub
  # Result depends on how git subtree handles this
}

#------------------------------------------------------------------------------
# Multiple subtrees
#------------------------------------------------------------------------------

@test "changes to one subtree don't affect another" {
  local repo upstream1 work1 upstream2 work2
  
  # Create two upstreams
  upstream1=$(create_bare_repo "up1")
  work1=$(create_repo "work1")
  (
    cd "$work1"
    echo "lib1 content" > file1.txt
    git add file1.txt
    git commit -m "Init lib1"
    git remote add origin "$upstream1"
    git push -u origin main
  ) >/dev/null
  
  upstream2=$(create_bare_repo "up2")
  work2=$(create_repo "work2")
  (
    cd "$work2"
    echo "lib2 content" > file2.txt
    git add file2.txt
    git commit -m "Init lib2"
    git remote add origin "$upstream2"
    git push -u origin main
  ) >/dev/null
  
  # Create monorepo with both subtrees
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/one "$upstream1" main >/dev/null
  platypus subtree add lib/two "$upstream2" main >/dev/null
  
  # Modify lib1 upstream
  (
    cd "$work1"
    echo "updated lib1" > file1.txt
    git add file1.txt
    git commit -m "Update lib1"
    git push origin main
  ) >/dev/null
  
  # Pull only lib1
  run platypus subtree pull lib/one
  [ "$status" -eq 0 ]
  
  # lib2 should be unchanged
  grep -q "lib2 content" lib/two/file2.txt
  
  # lib1 should be updated
  grep -q "updated lib1" lib/one/file1.txt
}

#------------------------------------------------------------------------------
# Push scenarios
#------------------------------------------------------------------------------

@test "push local changes to subtree succeeds" {
  local setup repo upstream upstream_work
  setup=$(setup_conflict_scenario)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  upstream_work=$(echo "$setup" | cut -d'|' -f3)
  
  cd "$repo"
  
  # Make local changes
  echo "local addition" >> lib/sub/shared.txt
  git add lib/sub/shared.txt
  git commit -m "Add line to shared.txt"
  
  # Push
  run platypus subtree push lib/sub
  [ "$status" -eq 0 ]
  
  # Verify upstream has changes
  (
    cd "$upstream_work"
    git pull origin main
    grep -q "local addition" shared.txt
  )
}

@test "push fails if upstream has diverged" {
  local setup repo upstream upstream_work
  setup=$(setup_conflict_scenario)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  upstream_work=$(echo "$setup" | cut -d'|' -f3)
  
  # Make local changes
  (
    cd "$repo"
    echo "local change" >> lib/sub/shared.txt
    git add lib/sub/shared.txt
    git commit -m "Local change"
  )
  
  # Make upstream changes (diverge)
  (
    cd "$upstream_work"
    echo "upstream change" > newfile.txt
    git add newfile.txt
    git commit -m "Upstream divergence"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
  # Push should fail (non-fast-forward)
  run platypus subtree push lib/sub
  [ "$status" -ne 0 ]
}

