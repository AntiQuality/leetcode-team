#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/StudyPlanProgress.swift tests/ProgressTests.swift -module-cache-path "$TEST_DIR/cache" -o "$TEST_DIR/progress"
"$TEST_DIR/progress" Resources/hot100.json
swiftc Sources/SidebarHover.swift tests/SidebarTests.swift -module-cache-path "$TEST_DIR/cache" -o "$TEST_DIR/sidebar"
"$TEST_DIR/sidebar"
swiftc Sources/GitHubTeam.swift Sources/GitHubAppSession.swift tests/GitHubTests.swift -module-cache-path "$TEST_DIR/cache" -o "$TEST_DIR/github"
"$TEST_DIR/github"
