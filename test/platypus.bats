#!/usr/bin/env bats
#
# platypus.bats - Tests for the main platypus wrapper script
#

load test_helper

#------------------------------------------------------------------------------
# Help and version
#------------------------------------------------------------------------------

@test "platypus help shows usage" {
  run platypus help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"svn"* ]]
  [[ "$output" == *"subtree"* ]]
}

@test "platypus --help shows usage" {
  run platypus --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "platypus -h shows usage" {
  run platypus -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "platypus version shows version number" {
  run platypus version
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+\.[0-9]+ ]]
}

@test "platypus --version shows version number" {
  run platypus --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+\.[0-9]+ ]]
}

#------------------------------------------------------------------------------
# Subcommand routing
#------------------------------------------------------------------------------

@test "platypus with no args shows usage" {
  run platypus
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "platypus unknown subcommand shows error" {
  run platypus foobar
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "platypus subtree routes to subtree command" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Just test that it invokes the subtree help
  run platypus subtree --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"subtree"* ]]
}

@test "platypus subtree list works" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree list
  [ "$status" -eq 0 ]
}

