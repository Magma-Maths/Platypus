#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# subtree-scenarios.bats - Complex real-world subtree scenarios
#
# Tests realistic workflows like:
# - Add file in monorepo, push to upstream, upstream edits, pull back
# - Rename/move files
# - Binary files
# - Deep directory structures
#

load test_helper

#------------------------------------------------------------------------------
# Round-trip scenarios
#------------------------------------------------------------------------------

@test "add file locally, push, upstream edits, pull back" {
  local repo upstream work_dir
  
  # Setup
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "initial" > existing.txt
    git add existing.txt
    git commit -m "Initial"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Step 1: Add a new file locally
  echo "created locally" > lib/sub/local.txt
  git add lib/sub/local.txt
  git commit -m "Add local.txt in monorepo"
  
  # Step 2: Push to upstream
  platypus subtree push lib/sub >/dev/null
  
  # Step 3: Upstream edits the file
  (
    cd "$work_dir"
    git pull origin main
    echo "edited by upstream" >> local.txt
    git add local.txt
    git commit -m "Upstream edits local.txt"
    git push origin main
  ) >/dev/null
  
  # Step 4: Pull back
  run platypus subtree pull lib/sub
  [ "$status" -eq 0 ]
  
  # Verify the upstream edit is present
  grep -q "edited by upstream" lib/sub/local.txt
  grep -q "created locally" lib/sub/local.txt
}

@test "multiple round trips maintain consistency" {
  local repo upstream work_dir
  
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "v1" > version.txt
    git add version.txt
    git commit -m "v1"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Round trip 1: local change
  echo "v2-local" > lib/sub/version.txt
  git add lib/sub/version.txt
  git commit -m "v2 local"
  platypus subtree push lib/sub >/dev/null
  
  # Round trip 2: upstream change
  (
    cd "$work_dir"
    git pull origin main
    echo "v3-upstream" > version.txt
    git add version.txt
    git commit -m "v3 upstream"
    git push origin main
  ) >/dev/null
  
  platypus subtree pull lib/sub >/dev/null
  
  # Round trip 3: local change again
  echo "v4-local" > lib/sub/version.txt
  git add lib/sub/version.txt
  git commit -m "v4 local"
  platypus subtree push lib/sub >/dev/null
  
  # Verify final state
  grep -q "v4-local" lib/sub/version.txt
  
  # Verify upstream has it too
  (
    cd "$work_dir"
    git pull origin main
    grep -q "v4-local" version.txt
  )
}

#------------------------------------------------------------------------------
# Directory structure changes
#------------------------------------------------------------------------------

@test "add nested directory structure" {
  local repo upstream work_dir
  
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "root" > root.txt
    git add root.txt
    git commit -m "Root"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Add nested structure locally
  mkdir -p lib/sub/a/b/c
  echo "deep file" > lib/sub/a/b/c/deep.txt
  git add lib/sub/a/b/c/deep.txt
  git commit -m "Add deep nested file"
  
  # Push
  run platypus subtree push lib/sub
  [ "$status" -eq 0 ]
  
  # Verify upstream has it
  (
    cd "$work_dir"
    git pull origin main
    [ -f "a/b/c/deep.txt" ]
    grep -q "deep file" a/b/c/deep.txt
  )
}

@test "upstream adds directory, local adds to same directory" {
  local repo upstream work_dir
  
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "init" > init.txt
    git add init.txt
    git commit -m "Init"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Upstream adds a directory
  (
    cd "$work_dir"
    mkdir -p src
    echo "upstream src file" > src/upstream.txt
    git add src
    git commit -m "Add src/upstream.txt"
    git push origin main
  ) >/dev/null
  
  # Local adds to same directory (before pulling)
  mkdir -p lib/sub/src
  echo "local src file" > lib/sub/src/local.txt
  git add lib/sub/src
  git commit -m "Add src/local.txt"
  
  # Pull - should merge both files
  run platypus subtree pull lib/sub
  [ "$status" -eq 0 ]
  
  # Both files should exist
  [ -f "lib/sub/src/upstream.txt" ]
  [ -f "lib/sub/src/local.txt" ]
}

#------------------------------------------------------------------------------
# File rename/move scenarios
#------------------------------------------------------------------------------

@test "upstream renames file" {
  local repo upstream work_dir
  
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "content" > old-name.txt
    git add old-name.txt
    git commit -m "Add old-name.txt"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Upstream renames file
  (
    cd "$work_dir"
    git mv old-name.txt new-name.txt
    git commit -m "Rename old-name.txt to new-name.txt"
    git push origin main
  ) >/dev/null
  
  # Pull
  run platypus subtree pull lib/sub
  [ "$status" -eq 0 ]
  
  # Old file should be gone, new file should exist
  [ ! -f "lib/sub/old-name.txt" ]
  [ -f "lib/sub/new-name.txt" ]
}

@test "local renames file, pushes successfully" {
  local repo upstream work_dir
  
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "content" > file.txt
    git add file.txt
    git commit -m "Add file.txt"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Rename locally
  git mv lib/sub/file.txt lib/sub/renamed.txt
  git commit -m "Rename file.txt to renamed.txt"
  
  # Push
  run platypus subtree push lib/sub
  [ "$status" -eq 0 ]
  
  # Verify upstream
  (
    cd "$work_dir"
    git pull origin main
    [ ! -f "file.txt" ]
    [ -f "renamed.txt" ]
  )
}

#------------------------------------------------------------------------------
# Many files/commits
#------------------------------------------------------------------------------

@test "handle many small commits" {
  local repo upstream work_dir
  
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "init" > init.txt
    git add init.txt
    git commit -m "Init"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Make 10 small commits locally
  for i in $(seq 1 10); do
    echo "file $i" > "lib/sub/file-$i.txt"
    git add "lib/sub/file-$i.txt"
    git commit -m "Add file $i"
  done
  
  # Push all at once
  run platypus subtree push lib/sub
  [ "$status" -eq 0 ]
  
  # Verify all files in upstream
  (
    cd "$work_dir"
    git pull origin main
    for i in $(seq 1 10); do
      [ -f "file-$i.txt" ]
    done
  )
}

@test "pull many upstream commits" {
  local repo upstream work_dir
  
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "init" > init.txt
    git add init.txt
    git commit -m "Init"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  repo=$(create_monorepo)
  cd "$repo"
  platypus subtree add lib/sub "$upstream" main >/dev/null
  
  # Make 10 commits upstream
  (
    cd "$work_dir"
    for i in $(seq 1 10); do
      echo "upstream $i" > "up-$i.txt"
      git add "up-$i.txt"
      git commit -m "Upstream commit $i"
    done
    git push origin main
  ) >/dev/null
  
  # Pull all
  run platypus subtree pull lib/sub
  [ "$status" -eq 0 ]
  
  # Verify all files
  for i in $(seq 1 10); do
    [ -f "lib/sub/up-$i.txt" ]
  done
}

