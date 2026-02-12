#!/usr/bin/env zsh
# =============================================================================
# Test suite for kk.plugin.zsh
# Usage: zsh tests.zsh
# =============================================================================

setopt null_glob

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/kk.plugin.zsh"

# =============================================================================
# Minimal test framework
# =============================================================================

typeset -i _test_pass=0 _test_fail=0 _test_total=0
typeset _current_test=""

_strip_ansi() {
  # Remove ANSI escape sequences for clean comparison
  sed $'s/\e\\[[0-9;]*m//g'
}

_test_begin() {
  _current_test="$1"
  _test_total+=1
}

_test_ok() {
  _test_pass+=1
  printf "  \e[32m✓\e[0m %s\n" "$_current_test"
}

_test_fail() {
  _test_fail+=1
  printf "  \e[31m✗\e[0m %s\n" "$_current_test"
  printf "    \e[31m%s\e[0m\n" "$1"
}

assert_eq() {
  local expected="$1" actual="$2"
  if [[ "$expected" == "$actual" ]]; then
    _test_ok
  else
    _test_fail "expected: $(printf '%q' "$expected")\n     got: $(printf '%q' "$actual")"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    _test_ok
  else
    _test_fail "expected to contain: $needle\n    in: ${haystack[1,200]}"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    _test_ok
  else
    _test_fail "expected NOT to contain: $needle"
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  "$@" >/dev/null 2>&1
  local actual=$?
  if (( expected == actual )); then
    _test_ok
  else
    _test_fail "expected exit code $expected, got $actual"
  fi
}

assert_line_count() {
  local expected="$1" actual_text="$2"
  local -i count=0
  [[ -n "$actual_text" ]] && count=$(echo "$actual_text" | wc -l | tr -d ' ')
  if (( expected == count )); then
    _test_ok
  else
    _test_fail "expected $expected lines, got $count"
  fi
}

# =============================================================================
# Test fixtures
# =============================================================================

TMPDIR_BASE=""
FIXTURE_DIR=""

setup_fixture() {
  TMPDIR_BASE=$(mktemp -d)
  FIXTURE_DIR="$TMPDIR_BASE/fixture"
  mkdir -p "$FIXTURE_DIR"

  # Create test files with known properties
  echo "hello" > "$FIXTURE_DIR/file-a.txt"
  echo "hello world, this is a longer file" > "$FIXTURE_DIR/file-b.txt"
  mkdir "$FIXTURE_DIR/dir-c"
  echo "nested" > "$FIXTURE_DIR/dir-c/nested.txt"
  ln -s file-a.txt "$FIXTURE_DIR/link-d"
  touch "$FIXTURE_DIR/.hidden-file"
  mkdir "$FIXTURE_DIR/.hidden-dir"
  mkfifo "$FIXTURE_DIR/pipe-e" 2>/dev/null || true
}

teardown_fixture() {
  [[ -n "$TMPDIR_BASE" && -d "$TMPDIR_BASE" ]] && rm -rf "$TMPDIR_BASE"
}

# =============================================================================
# Unit tests: _kk_bsd_to_ansi
# =============================================================================

test_bsd_to_ansi() {
  print "\n\e[1m_kk_bsd_to_ansi\e[0m"

  _test_begin "converts foreground 'e' (blue) + background 'x' (default)"
  assert_eq "0;34" "$(_kk_bsd_to_ansi e x)"

  _test_begin "converts foreground 'b' (red) + background 'a' (black)"
  assert_eq "40;31" "$(_kk_bsd_to_ansi b a)"

  _test_begin "converts foreground 'x' (default) + background 'x' (default)"
  assert_eq "0;0" "$(_kk_bsd_to_ansi x x)"

  _test_begin "backward-compatible alias _k_bsd_to_ansi works"
  assert_eq "0;34" "$(_k_bsd_to_ansi e x)"
}

# =============================================================================
# Unit tests: _kk_init_colors
# =============================================================================

test_init_colors() {
  print "\n\e[1m_kk_init_colors\e[0m"

  # Clear any existing LSCOLORS to test defaults
  local saved_lscolors="$LSCOLORS"
  unset LSCOLORS

  _kk_init_colors

  _test_begin "sets default directory color (blue)"
  assert_eq "0;34" "$K_COLOR_DI"

  _test_begin "sets default symlink color (magenta)"
  assert_eq "0;35" "$K_COLOR_LN"

  _test_begin "sets default executable color (red)"
  assert_eq "0;31" "$K_COLOR_EX"

  _test_begin "sets default socket color (green)"
  assert_eq "0;32" "$K_COLOR_SO"

  _test_begin "sets default pipe color (yellow)"
  assert_eq "0;33" "$K_COLOR_PI"

  [[ -n "$saved_lscolors" ]] && LSCOLORS="$saved_lscolors"
}

# =============================================================================
# Unit tests: _kk_resolve_sort
# =============================================================================

test_resolve_sort() {
  print "\n\e[1m_kk_resolve_sort\e[0m"
  local SORT_GLOB

  _test_begin "default sort is by name ascending"
  local -a o_sort=() o_sort_reverse=() o_group_directories=()
  _kk_resolve_sort
  assert_eq "on" "$SORT_GLOB"

  _test_begin "-t sorts by mtime"
  o_sort=(-t)
  _kk_resolve_sort
  assert_eq "om" "$SORT_GLOB"

  _test_begin "-S sorts by size descending"
  o_sort=(-S)
  _kk_resolve_sort
  assert_eq "OL" "$SORT_GLOB"

  _test_begin "-r reverses sort order"
  o_sort=(-t) o_sort_reverse=(-r)
  _kk_resolve_sort
  assert_eq "Om" "$SORT_GLOB"

  _test_begin "-U disables sorting"
  o_sort=(-U) o_sort_reverse=()
  _kk_resolve_sort
  assert_eq "oN" "$SORT_GLOB"

  _test_begin "-c sorts by ctime"
  o_sort=(-c) o_sort_reverse=()
  _kk_resolve_sort
  assert_eq "oc" "$SORT_GLOB"

  _test_begin "-u sorts by atime"
  o_sort=(-u) o_sort_reverse=()
  _kk_resolve_sort
  assert_eq "oa" "$SORT_GLOB"

  _test_begin "--group-directories-first prepends directory qualifier"
  o_sort=() o_sort_reverse=() o_group_directories=(--group-directories-first)
  _kk_resolve_sort
  assert_contains "$SORT_GLOB" "oe:"
}

# =============================================================================
# Unit tests: _kk_format_repomarker
# =============================================================================

test_format_repomarker() {
  print "\n\e[1m_kk_format_repomarker\e[0m"
  local REPOMARKER
  local -i IS_GIT_REPO
  typeset -A VCS_STATUS

  _test_begin "returns empty string when not in a git repo"
  IS_GIT_REPO=0
  VCS_STATUS=()
  _kk_format_repomarker "file.txt"
  assert_eq "" "$REPOMARKER"

  IS_GIT_REPO=1

  _test_begin "shows '|' (green) for tracked clean file"
  VCS_STATUS=([file.txt]="==")
  _kk_format_repomarker "file.txt"
  local clean=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " |" "$clean"

  _test_begin "shows '+' (yellow) for directory with changes"
  VCS_STATUS=([src]="//")
  _kk_format_repomarker "src"
  local dir_changed=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " +" "$dir_changed"

  _test_begin "shows '|' (dim) for ignored file"
  VCS_STATUS=([ignored.log]="!!")
  _kk_format_repomarker "ignored.log"
  local ignored=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " |" "$ignored"

  _test_begin "shows '?' for untracked file"
  VCS_STATUS=([new.txt]="??")
  _kk_format_repomarker "new.txt"
  local untracked=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " ?" "$untracked"

  _test_begin "shows '+' (green) for staged file (index matches work tree)"
  VCS_STATUS=([staged.txt]="A ")
  _kk_format_repomarker "staged.txt"
  local staged=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " +" "$staged"

  _test_begin "shows '+' (red) for work tree modification"
  VCS_STATUS=([modified.txt]=" M")
  _kk_format_repomarker "modified.txt"
  local wt_changed=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " +" "$wt_changed"

  _test_begin "shows '+' (orange) for both index and work tree changed"
  VCS_STATUS=([both.txt]="MM")
  _kk_format_repomarker "both.txt"
  local both=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " +" "$both"

  _test_begin "shows spaces for file outside repository"
  VCS_STATUS=()
  _kk_format_repomarker "outside.txt"
  assert_eq "  " "$REPOMARKER"

  _test_begin "inherits parent ignored status"
  VCS_STATUS=(["."]="!!" [child.txt]="==")
  _kk_format_repomarker "child.txt"
  local child_ignored=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " |" "$child_ignored"

  _test_begin ".. does NOT inherit parent ignored status"
  VCS_STATUS=(["."]="!!" [".."]="==" [child.txt]="==")
  _kk_format_repomarker ".."
  local dotdot=$(echo "$REPOMARKER" | _strip_ansi)
  assert_eq " |" "$dotdot"
}

# =============================================================================
# Unit tests: _kk_color_filename
# =============================================================================

test_color_filename() {
  print "\n\e[1m_kk_color_filename\e[0m"
  _kk_init_colors
  setup_fixture

  _test_begin "colors directories with DI color"
  local COLORED_NAME="dir-c"
  _kk_color_filename "$FIXTURE_DIR/dir-c" "drwxr-xr-x"
  assert_contains "$COLORED_NAME" "$K_COLOR_DI"

  _test_begin "colors symlinks with LN color"
  COLORED_NAME="link-d"
  _kk_color_filename "$FIXTURE_DIR/link-d" "lrwxr-xr-x"
  assert_contains "$COLORED_NAME" "$K_COLOR_LN"

  _test_begin "colors pipes with PI color"
  if [[ -p "$FIXTURE_DIR/pipe-e" ]]; then
    COLORED_NAME="pipe-e"
    _kk_color_filename "$FIXTURE_DIR/pipe-e" "prw-r--r--"
    assert_contains "$COLORED_NAME" "$K_COLOR_PI"
  else
    _test_ok  # mkfifo may have failed
  fi

  _test_begin "leaves regular files uncolored"
  COLORED_NAME="file-a.txt"
  _kk_color_filename "$FIXTURE_DIR/file-a.txt" "-rw-r--r--"
  assert_eq "file-a.txt" "$COLORED_NAME"

  teardown_fixture
}

# =============================================================================
# Integration tests: kk command
# =============================================================================

test_kk_basic() {
  print "\n\e[1mkk basic listing\e[0m"
  setup_fixture

  _test_begin "lists files in a directory"
  local output=$(kk --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  assert_contains "$output" "file-a.txt"

  _test_begin "shows 'total' line"
  assert_contains "$output" "total "

  _test_begin "shows directory names"
  assert_contains "$output" "dir-c"

  _test_begin "shows symlink with arrow"
  assert_contains "$output" "link-d -> file-a.txt"

  _test_begin "does not show hidden files by default"
  assert_not_contains "$output" ".hidden-file"

  teardown_fixture
}

test_kk_all_flags() {
  print "\n\e[1mkk -a / -A flags\e[0m"
  setup_fixture

  _test_begin "-a shows hidden files including . and .."
  local output_a=$(kk -a --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  assert_contains "$output_a" ".hidden-file"

  _test_begin "-a includes . entry"
  assert_contains "$output_a" " ."$'\n'

  _test_begin "-a includes .. entry"
  assert_contains "$output_a" " .."$'\n'

  _test_begin "-A shows hidden files but not . and .."
  local output_A=$(kk -A --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  assert_contains "$output_A" ".hidden-file"

  _test_begin "-A does not include . entry"
  # Check that there's no line ending with just " ." (not ".hidden-file")
  local dot_lines=$(echo "$output_A" | grep -c ' \.$' || true)
  assert_eq "0" "$dot_lines"

  teardown_fixture
}

test_kk_directory_flags() {
  print "\n\e[1mkk -d / -n flags\e[0m"
  setup_fixture

  _test_begin "-d shows the directory entry itself"
  local output_d=$(kk -d --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  assert_contains "$output_d" "fixture"

  _test_begin "-d does not show regular files"
  assert_not_contains "$output_d" "file-a.txt"

  _test_begin "-n excludes directories"
  local output_n=$(kk -n --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  assert_not_contains "$output_n" "dir-c"

  _test_begin "-n shows regular files"
  assert_contains "$output_n" "file-a.txt"

  _test_begin "-d and -n together returns error"
  assert_exit_code 1 kk -d -n --no-vcs "$FIXTURE_DIR"

  teardown_fixture
}

test_kk_sort() {
  print "\n\e[1mkk sort options\e[0m"
  setup_fixture

  # Make file-b.txt newer than file-a.txt
  sleep 1
  touch "$FIXTURE_DIR/file-b.txt"

  _test_begin "-t sorts by modification time (newest first)"
  local output_t=$(kk -t --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  # file-b.txt was touched last, should appear before file-a.txt
  # Use -m1 to get only the first match (symlink line may also match file-a.txt)
  local pos_b=$(echo "$output_t" | grep -n -m1 'file-b\.txt' | cut -d: -f1)
  local pos_a=$(echo "$output_t" | grep -n -m1 'file-a\.txt' | cut -d: -f1)
  if (( pos_b < pos_a )); then _test_ok; else _test_fail "file-b.txt (line $pos_b) should come before file-a.txt (line $pos_a)"; fi

  _test_begin "-S sorts by size (largest first)"
  local output_S=$(kk -S --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  # file-b.txt is larger, should appear first among files
  local pos_b_s=$(echo "$output_S" | grep -n -m1 'file-b\.txt' | cut -d: -f1)
  local pos_a_s=$(echo "$output_S" | grep -n -m1 'file-a\.txt' | cut -d: -f1)
  if (( pos_b_s < pos_a_s )); then _test_ok; else _test_fail "file-b.txt (line $pos_b_s) should come before file-a.txt (line $pos_a_s)"; fi

  _test_begin "-r reverses sort order"
  local output_r=$(kk -r --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  # Default is by name ascending; reversed should have pipe-e, link-d, file-b, file-a, dir-c
  # Exclude symlink lines (contain ' -> ') to avoid matching target filename
  local pos_b_r=$(echo "$output_r" | grep -v ' -> ' | grep -n -m1 'file-b\.txt' | cut -d: -f1)
  local pos_a_r=$(echo "$output_r" | grep -v ' -> ' | grep -n -m1 'file-a\.txt' | cut -d: -f1)
  if (( pos_b_r < pos_a_r )); then _test_ok; else _test_fail "file-b.txt (line $pos_b_r) should come before file-a.txt (line $pos_a_r)"; fi

  teardown_fixture
}

test_kk_human_readable() {
  print "\n\e[1mkk -h human readable\e[0m"
  setup_fixture

  # Create a file with known size
  dd if=/dev/zero of="$FIXTURE_DIR/bigfile" bs=1024 count=10 2>/dev/null

  _test_begin "-h shows human-readable sizes"
  local output_h=$(kk -h --no-vcs "$FIXTURE_DIR" | _strip_ansi)
  # 10KB file should show as "10K"
  assert_contains "$output_h" "10K"

  teardown_fixture
}

test_kk_help() {
  print "\n\e[1mkk --help\e[0m"

  _test_begin "--help prints usage and returns 1"
  local output
  output=$(kk --help 2>&1)
  local rc=$?
  assert_eq "1" "$rc"

  _test_begin "--help output contains Usage"
  assert_contains "$output" "Usage:"

  _test_begin "--help output contains all options"
  assert_contains "$output" "--all"
}

test_kk_nonexistent() {
  print "\n\e[1mkk error handling\e[0m"

  _test_begin "reports error for non-existent path"
  local output=$(kk /no/such/path 2>&1)
  assert_contains "$output" "no such file or directory"
}

test_kk_no_vcs() {
  print "\n\e[1mkk --no-vcs\e[0m"

  _test_begin "--no-vcs output has no git markers"
  local output=$(kk --no-vcs "$SCRIPT_DIR" | _strip_ansi)
  # Without VCS, no |, +, or ? markers in marker column
  # Each line should NOT have the git marker patterns
  assert_not_contains "$output" " | "
}

test_kk_multiple_dirs() {
  print "\n\e[1mkk multiple directories\e[0m"
  setup_fixture
  mkdir -p "$FIXTURE_DIR/sub1" "$FIXTURE_DIR/sub2"
  touch "$FIXTURE_DIR/sub1/aaa" "$FIXTURE_DIR/sub2/bbb"

  _test_begin "lists multiple directories with headers"
  local output=$(kk --no-vcs "$FIXTURE_DIR/sub1" "$FIXTURE_DIR/sub2" | _strip_ansi)
  assert_contains "$output" "sub1:"

  _test_begin "shows second directory header"
  assert_contains "$output" "sub2:"

  _test_begin "lists files from both directories"
  assert_contains "$output" "aaa"

  teardown_fixture
}

test_kk_single_file() {
  print "\n\e[1mkk single file argument\e[0m"
  setup_fixture

  _test_begin "can list a single file"
  local output=$(kk --no-vcs "$FIXTURE_DIR/file-a.txt" | _strip_ansi)
  assert_contains "$output" "file-a.txt"

  teardown_fixture
}

# =============================================================================
# Integration tests: git status with test-dir
# =============================================================================

test_kk_git_status() {
  print "\n\e[1mkk git status (test-dir)\e[0m"

  local test_dir="$SCRIPT_DIR/test-dir"
  [[ -d "$test_dir/.git" ]] || { print "  (skipped: test-dir not available)"; return }

  _test_begin "shows git markers for tracked files"
  local output=$(kk "$test_dir" | _strip_ansi)
  # MODIFIED-FILE should have a marker (not just spaces)
  assert_contains "$output" "MODIFIED-FILE"

  _test_begin "shows untracked marker for NOT-TRACKED-FILE"
  local nt_line=$(echo "$output" | grep 'NOT-TRACKED-FILE')
  assert_contains "$nt_line" "?"

  _test_begin "shows ignored marker for IGNORED-FILE"
  local ig_line=$(echo "$output" | grep 'IGNORED-FILE$')
  assert_contains "$ig_line" "|"

  _test_begin "-a shows . and .. with git markers"
  local output_a=$(kk -a "$test_dir" | _strip_ansi)
  assert_contains "$output_a" " ."$'\n'
}

# =============================================================================
# Run all tests
# =============================================================================

print "\e[1m========================================\e[0m"
print "\e[1m  kk.plugin.zsh test suite\e[0m"
print "\e[1m========================================\e[0m"

test_bsd_to_ansi
test_init_colors
test_resolve_sort
test_format_repomarker
test_color_filename
test_kk_basic
test_kk_all_flags
test_kk_directory_flags
test_kk_sort
test_kk_human_readable
test_kk_help
test_kk_nonexistent
test_kk_no_vcs
test_kk_multiple_dirs
test_kk_single_file
test_kk_git_status

# Summary
print "\n\e[1m========================================\e[0m"
if (( _test_fail == 0 )); then
  printf "\e[32m  All %d tests passed\e[0m\n" $_test_total
else
  printf "\e[31m  %d of %d tests failed\e[0m\n" $_test_fail $_test_total
fi
print "\e[1m========================================\e[0m"

exit $(( _test_fail > 0 ? 1 : 0 ))
