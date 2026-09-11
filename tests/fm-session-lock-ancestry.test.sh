#!/usr/bin/env bash
# tests/fm-session-lock-ancestry.test.sh - session-lock harness identity
# (bin/fm-session-lock-lib.sh).
#
# Two layers. The unit cases drive the library's own functions behind a
# deterministic fake ps, so both platforms' reporting semantics are covered from
# either host: macOS reports argv[0] in `ps -o comm=`, while procps on Linux
# reports the kernel exec name and ignores argv[0] entirely. The end-to-end cases
# run the REAL Stop auto-arm inside real process trees whose shapes differ only
# in how the per-session process is named and what its parent is. Those trees are
# orphaned before the hook fires, so the ancestry walk terminates inside the
# fixture and can never escape into the session running this suite.
# shellcheck disable=SC2016 # single quotes are deliberate: $FM_HOME and $$ expand inside the fixture child
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-session-lock-ancestry)
fm_git_identity fmtest fmtest@example.invalid

LIB="$ROOT/bin/fm-session-lock-lib.sh"

BASH_ALIAS=
install_bash_alias() {
  local destination=$1
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      cat > "$destination" <<'SH'
#!/usr/bin/env bash
exec -a "$0" /bin/bash "$@"
SH
      chmod +x "$destination"
      ;;
    *) ln -s /bin/bash "$destination" ;;
  esac
  BASH_ALIAS=$destination
}

# Claude Code's native installer names the per-session executable by its version,
# so the harness identity has to survive a basename that says nothing.
CLAUDE_VERSION_DIR="$TMP_ROOT/claude-install/share/claude/versions"
mkdir -p "$CLAUDE_VERSION_DIR"
install_bash_alias "$CLAUDE_VERSION_DIR/2.1.220"
VERSIONED_CLAUDE=$BASH_ALIAS

FAKEBIN=$(fm_fakebin "$TMP_ROOT/harness-bin")
install_bash_alias "$FAKEBIN/claude"
NAMED_CLAUDE=$BASH_ALIAS

# --- unit layer: identity behind a deterministic process table ---------------

# Run one library expression with <fakebin> shadowing ps. kill is stubbed so
# liveness questions are decided by the process table alone.
lib_eval() {  # <fakebin> <expression>
  local fakebin=$1 expr=$2
  FM_PROC_ROOT_OVERRIDE="$fakebin/no-proc" PATH="$fakebin:$PATH" bash -c "
    . \"\$0\"
    kill() { return 0; }
    $expr
  " "$LIB"
}

test_version_named_session_is_identified_on_both_platforms() {
  local dir fakebin shape got
  dir="$TMP_ROOT/version-named"
  fakebin=$(fm_fakebin "$dir")
  mkdir -p "$dir/state"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field:${FM_TEST_CLAUDE_SHAPE:-linux}" in
  700:comm=:linux) printf '%s\n' '2.1.220' ;;
  700:args=:linux) printf '%s\n' '/opt/claude/versions/2.1.220 --resume' ;;
  700:comm=:macos) printf '%s\n' '/Users/u/.local/share/claude/versions/2.1.220' ;;
  700:args=:macos) printf '%s\n' '/Users/u/.local/share/claude/versions/2.1.220 --resume' ;;
  700:ppid=:*) printf '%s\n' 1 ;;
  *:comm=:*) printf '%s\n' bash ;;
  *:args=:*) printf '%s\n' 'bash /repo/bin/fm-claude-stop-autoarm.sh' ;;
  *:ppid=:*) printf '%s\n' 700 ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '700\n' > "$dir/state/.lock"

  for shape in linux macos; do
    got=$(FM_TEST_CLAUDE_SHAPE="$shape" lib_eval "$fakebin" 'fm_harness_ancestry_pid') \
      || fail "$shape: the version-named session was not found in the ancestry at all"
    [ "$got" = 700 ] || fail "$shape: ancestry resolved '$got', expected the version-named session pid 700"
    FM_TEST_CLAUDE_SHAPE="$shape" lib_eval "$fakebin" 'fm_harness_pid_alive 700' \
      || fail "$shape: a live version-named session was not recognized as a harness"
    FM_TEST_CLAUDE_SHAPE="$shape" lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'" \
      || fail "$shape: the session holding the lock did not recognize itself as the owner"
  done
  pass "session-lock: a version-named Claude Code session is identified from its install path and argv[0]"
}

test_ordinary_paths_are_never_harness_processes() {
  local dir fakebin shape
  dir="$TMP_ROOT/ordinary-paths"
  fakebin=$(fm_fakebin "$dir")
  mkdir -p "$dir/state"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field:${FM_TEST_PATH_SHAPE:-hookdir}" in
  810:comm=:hookdir) printf '%s\n' '/home/u/.claude/hooks/notify.sh' ;;
  810:args=:hookdir) printf '%s\n' '/home/u/.claude/hooks/notify.sh --quiet' ;;
  810:comm=:piprefix) printf '%s\n' '/opt/pipeline/bin/runner' ;;
  810:args=:piprefix) printf '%s\n' '/opt/pipeline/bin/runner --once' ;;
  810:ppid=:*) printf '%s\n' 1 ;;
  *:comm=:*) printf '%s\n' bash ;;
  *:args=:*) printf '%s\n' 'bash /repo/bin/fm-watch-arm.sh' ;;
  *:ppid=:*) printf '%s\n' 810 ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '810\n' > "$dir/state/.lock"

  # Identity may be read from an executable path, but only from whole path
  # components: anything merely living under ~/.claude, and any component that
  # merely starts with a harness name, must stay outside the harness identity.
  for shape in hookdir piprefix; do
    if FM_TEST_PATH_SHAPE="$shape" lib_eval "$fakebin" 'fm_harness_ancestry_pid'; then
      fail "$shape: an ordinary script path was treated as a harness process"
    fi
    if FM_TEST_PATH_SHAPE="$shape" lib_eval "$fakebin" 'fm_harness_pid_alive 810'; then
      fail "$shape: an ordinary script path passed the harness-liveness predicate"
    fi
    if FM_TEST_PATH_SHAPE="$shape" lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
      fail "$shape: an ordinary script path claimed the home's session lock"
    fi
  done
  pass "session-lock: ordinary script paths under a harness directory are not harness processes"
}

test_harness_beyond_a_gap_never_owns_the_lock() {
  local dir fakebin got
  dir="$TMP_ROOT/gap"
  fakebin=$(fm_fakebin "$dir")
  mkdir -p "$dir/state"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field" in
  900:comm=) printf '%s\n' claude ;;
  900:args=) printf '%s\n' 'claude' ;;
  900:ppid=) printf '%s\n' 910 ;;
  910:comm=) printf '%s\n' bash ;;
  910:args=) printf '%s\n' 'bash tests/run.sh' ;;
  910:ppid=) printf '%s\n' 920 ;;
  920:comm=) printf '%s\n' claude ;;
  920:args=) printf '%s\n' 'claude' ;;
  920:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' bash ;;
  *:ppid=) printf '%s\n' 900 ;;
esac
SH
  chmod +x "$fakebin/ps"

  got=$(lib_eval "$fakebin" 'fm_harness_ancestry_pid') || fail "the contiguous harness run was not resolved"
  [ "$got" = 900 ] || fail "ancestry crossed a non-harness gap, resolved '$got' instead of 900"
  printf '920\n' > "$dir/state/.lock"
  if lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "an unrelated harness beyond a non-harness gap was accepted as this session's lock owner"
  fi
  printf '900\n' > "$dir/state/.lock"
  lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'" \
    || fail "the contiguous harness run did not recognize its own lock"
  pass "session-lock: ownership stops at the first non-harness gap above the contiguous run"
}

test_competing_version_named_session_is_seen_as_live() {
  local dir fakebin
  dir="$TMP_ROOT/competing"
  fakebin=$(fm_fakebin "$dir")
  mkdir -p "$dir/state"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field" in
  600:comm=) printf '%s\n' '2.1.220' ;;
  600:args=) printf '%s\n' '/opt/claude/versions/2.1.220' ;;
  600:ppid=) printf '%s\n' 1 ;;
  650:comm=) printf '%s\n' claude ;;
  650:args=) printf '%s\n' claude ;;
  650:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' bash ;;
  *:ppid=) printf '%s\n' 650 ;;
esac
SH
  chmod +x "$fakebin/ps"
  # pid 600 is a different live session that holds the lock; this process
  # descends from 650 instead. Treating 600 as dead would let this session
  # reclaim a live competitor's home.
  printf '600\n' > "$dir/state/.lock"
  if lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "a lock held outside this ancestry was claimed as this session's own"
  fi
  lib_eval "$fakebin" 'fm_harness_pid_alive 600' \
    || fail "a live competing version-named session was classified as a dead lock owner"
  pass "session-lock: a live version-named session holding the lock is not mistaken for a stale owner"
}

# --- end-to-end layer: the real Stop auto-arm in real process trees ----------

install_autoarm_scripts() {
  local dir=$1
  mkdir -p "$dir/bin"
  cp "$ROOT/bin/fm-claude-stop-autoarm.sh" "$dir/bin/fm-claude-stop-autoarm.sh"
  cp "$ROOT/bin/fm-primary-scope-lib.sh" "$dir/bin/fm-primary-scope-lib.sh"
  cp "$ROOT/bin/fm-supervision-lib.sh" "$dir/bin/fm-supervision-lib.sh"
  cp "$ROOT/bin/fm-wake-lib.sh" "$dir/bin/fm-wake-lib.sh"
  cp "$ROOT/bin/fm-session-lock-lib.sh" "$dir/bin/fm-session-lock-lib.sh"
  cp "$ROOT/bin/fm-platform-process-lib.sh" "$dir/bin/fm-platform-process-lib.sh"
  # shellcheck source=tests/harness-helpers.sh
  . "$ROOT/tests/harness-helpers.sh"
  fm_test_install_harness_modules "$dir" || fail "session identity fixture adapter dependencies"
  cp "$ROOT/bin/fm-cursor-lib.sh" "$dir/bin/fm-cursor-lib.sh"
  cp "$ROOT/bin/fm-hook-host-lib.sh" "$dir/bin/fm-hook-host-lib.sh"
  cp "$ROOT/bin/fm-lock.sh" "$dir/bin/fm-lock.sh"
  chmod +x "$dir/bin/fm-claude-stop-autoarm.sh" "$dir/bin/fm-lock.sh"
  cat > "$dir/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
echo "$$" >> "$FM_HOME/state/arm-ran"
printf 'pending:downtime:fixture-generation\n' > "$FM_HOME/state/.watcher-down"
touch "$FM_HOME/state/.last-watcher-beat"
printf 'watcher: started pid=%s (beacon fresh)\n' "$$"
printf 'stale: fixture-win actionable\n'
exit 0
SH
  chmod +x "$dir/bin/fm-watch-arm.sh"
}

# A primary home with one task in flight, so the hook's scope and supervision-need
# gates both pass and only identity decides the outcome.
make_primary_home() {  # <dir>
  local dir=$1
  mkdir -p "$dir/state"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m init
  : > "$dir/AGENTS.md"
  : > "$dir/state/task.meta"
  install_autoarm_scripts "$dir"
  # The process that fires the hook records its own pid as the session lock
  # owner, exactly as a real session does at session start.
  cat > "$dir/session.sh" <<'SH'
#!/usr/bin/env bash
if [ "${FM_FIXTURE_ORPHAN_HERE:-0}" = 1 ]; then
  i=0
  while [ "$i" -lt 200 ] && [ "$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')" != 1 ]; do
    sleep 0.05
    i=$((i + 1))
  done
fi
printf '%s\n' "$$" > "$FM_HOME/state/session-pid"
printf '%s\n' "$$" > "$FM_HOME/state/.lock"
"$FM_HOME/bin/fm-claude-stop-autoarm.sh" </dev/null > "$FM_HOME/state/hook.out" 2>&1
printf '%s\n' "$?" > "$FM_HOME/state/hook.rc"
SH
  cat > "$dir/daemon.sh" <<'SH'
#!/usr/bin/env bash
if [ "${FM_FIXTURE_ORPHAN_HERE:-0}" = 1 ]; then
  i=0
  while [ "$i" -lt 200 ] && [ "$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')" != 1 ]; do
    sleep 0.05
    i=$((i + 1))
  done
fi
printf '%s\n' "$$" > "$FM_HOME/state/daemon-pid"
FM_FIXTURE_ORPHAN_HERE=0 "$FM_SESSION_BIN" "$FM_HOME/session.sh"
exit 0
SH
  chmod +x "$dir/session.sh" "$dir/daemon.sh"
}

# Start the fixture tree detached from this suite's own process tree: the
# launcher exits immediately, so the tree is reparented to init and the ancestry
# walk terminates inside the fixture. Returns once the hook has recorded its exit
# code.
run_fixture_tree() {  # <dir> <session-bin> [<daemon-bin>]
  local dir=$1 session_bin=$2 daemon_bin=${3:-} i orphan_here=1
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) orphan_here=0 ;;
  esac
  # This fixture creates a synthetic Claude ancestry. Do not let an outer
  # Copilot CLI session's native-loader bridge replace that process tree.
  if [ -n "$daemon_bin" ]; then
    env -u COPILOT_CLI -u COPILOT_LOADER_PID -u COPILOT_AGENT_SESSION_ID \
      FM_HOME="$dir" FM_SESSION_BIN="$session_bin" FM_FIXTURE_ORPHAN_HERE="$orphan_here" \
      bash -c '"$0" "$1" &' "$daemon_bin" "$dir/daemon.sh"
  else
    env -u COPILOT_CLI -u COPILOT_LOADER_PID -u COPILOT_AGENT_SESSION_ID \
      FM_HOME="$dir" FM_FIXTURE_ORPHAN_HERE="$orphan_here" \
      bash -c '"$0" "$1" &' "$session_bin" "$dir/session.sh"
  fi
  i=0
  while [ "$i" -lt 400 ] && [ ! -s "$dir/state/hook.rc" ]; do
    sleep 0.05
    i=$((i + 1))
  done
  [ -s "$dir/state/hook.rc" ] || fail "the fixture hook never finished"
}

hook_rc() {
  tr -d '[:space:]' < "$1/state/hook.rc"
}

epoch_outcome() {
  sed -n 's/^.*outcome=\([a-z][a-z]*\) .*$/\1/p' "$1/state/.claude-autoarm-epoch" 2>/dev/null || true
}

test_e2e_version_named_session_claims_the_home() {
  local dir
  dir="$TMP_ROOT/e2e-version-named"
  make_primary_home "$dir"
  run_fixture_tree "$dir" "$VERSIONED_CLAUDE"
  expect_code 2 "$(hook_rc "$dir")" "a version-named session must claim its home and rewake"
  [ -e "$dir/state/arm-ran" ] || fail "supervision never armed for a version-named session"
  [ "$(epoch_outcome "$dir")" = rewake ] || fail "no claim was recorded, got: $(epoch_outcome "$dir")"
  pass "session-lock e2e: a version-named session claims the home and arms supervision"
}

test_e2e_daemon_parented_session_claims_the_home() {
  local dir session_pid daemon_pid lock_after
  dir="$TMP_ROOT/e2e-daemon-parented"
  make_primary_home "$dir"
  run_fixture_tree "$dir" "$NAMED_CLAUDE" "$NAMED_CLAUDE"
  session_pid=$(tr -d '[:space:]' < "$dir/state/session-pid")
  daemon_pid=$(tr -d '[:space:]' < "$dir/state/daemon-pid")
  [ -n "$session_pid" ] && [ "$session_pid" != "$daemon_pid" ] \
    || fail "fixture did not produce a distinct daemon and session: session=$session_pid daemon=$daemon_pid"
  lock_after=$(tr -d '[:space:]' < "$dir/state/.lock")
  expect_code 2 "$(hook_rc "$dir")" "a session parented by a harness-named daemon must claim its home and rewake"
  [ -e "$dir/state/arm-ran" ] || fail "supervision never armed for a daemon-parented session"
  [ "$lock_after" = "$session_pid" ] || fail "the session lock moved off the session: expected $session_pid, got $lock_after"
  pass "session-lock e2e: a session parented by a harness-named daemon claims the home and arms supervision"
}

test_e2e_daemon_parented_version_named_session_keeps_its_lock() {
  local dir session_pid daemon_pid lock_after
  dir="$TMP_ROOT/e2e-daemon-version-named"
  make_primary_home "$dir"
  run_fixture_tree "$dir" "$VERSIONED_CLAUDE" "$NAMED_CLAUDE"
  session_pid=$(tr -d '[:space:]' < "$dir/state/session-pid")
  daemon_pid=$(tr -d '[:space:]' < "$dir/state/daemon-pid")
  lock_after=$(tr -d '[:space:]' < "$dir/state/.lock")
  [ "$lock_after" != "$daemon_pid" ] \
    || fail "the live session's lock was reclaimed as stale and rewritten to the shared daemon pid $daemon_pid"
  [ "$lock_after" = "$session_pid" ] || fail "the session lock moved off the session: expected $session_pid, got $lock_after"
  expect_code 2 "$(hook_rc "$dir")" "a version-named session under a daemon must claim its home and rewake"
  [ -e "$dir/state/arm-ran" ] || fail "supervision never armed for a version-named daemon-parented session"
  pass "session-lock e2e: a version-named session under a harness-named daemon keeps its own lock"
}

# A portable model of the observed split: tool shell -> MSYS bash pid 38 -> 1,
# while that bash's native PID 90380 has Claude parents outside the MSYS tree.
# Only OS fact providers are faked; acquisition, identity and ownership are real.
make_windows_process_fixture() {  # <dir>
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  mkdir -p "$dir/proc/38" "$dir/state"
  printf '90380\n' > "$dir/proc/38/winpid"
  printf '90381\tC:/Tools/claude.exe\tclaude.exe --bg-worker\n90382\tC:/Program Files/Claude/claude.exe\tclaude.exe\n90383\tC:/Windows/powershell.exe\tpowershell.exe\n90384\tclaude.exe\tclaude.exe\n' > "$dir/parents"
  printf '90382\tC:/Program Files/Claude/claude.exe\tclaude.exe\n' > "$dir/info-90382"
  printf '90399\tC:/Tools/claude.exe\tclaude.exe --resume\n' > "$dir/info-90399"
  cat > "$dir/child-env.sh" <<'SH'
mkdir -p "$FM_PROC_ROOT_OVERRIDE/$$"
printf '90400\n' > "$FM_PROC_ROOT_OVERRIDE/$$/winpid"
SH
  cat > "$fakebin/uname" <<'SH'
#!/usr/bin/env bash
printf 'MINGW64_NT\n'
SH
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  '-W') printf 'PID PPID PGID WINPID COMMAND\n' ;;
  '-o comm= -p '*) printf 'bash\n' ;;
  '-o args= -p '*) printf 'bash\n' ;;
  '-o ppid= -p 38') printf '1\n' ;;
  '-o ppid= -p '*) printf '38\n' ;;
  *) exit 1 ;;
esac
SH
  cat > "$fakebin/tasklist.exe" <<'SH'
#!/usr/bin/env bash
printf 'INFO: no matching task\n'
SH
  cat > "$fakebin/powershell.exe" <<'SH'
#!/usr/bin/env bash
set -u
operation=${!#}
printf '%s %s\n' "$operation" "$FM_PROCESS_NATIVE_PID" >> "$FM_HOME/native-queries"
case "$operation" in
  parent-processes)
    [ "$FM_PROCESS_NATIVE_PID" = 90380 ] || exit 2
    cat "$FM_HOME/parents"
    [ ! -e "$FM_HOME/parents-error" ] || exit 2
    ;;
  process-info)
    [ ! -e "$FM_HOME/info-error" ] || exit 1
    [ -f "$FM_HOME/info-$FM_PROCESS_NATIVE_PID" ] || exit 3
    cat "$FM_HOME/info-$FM_PROCESS_NATIVE_PID"
    ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fakebin/"*
}

windows_fixture_run() {  # <dir> <command...>
  local dir=$1
  shift
  env -u COPILOT_CLI -u COPILOT_LOADER_PID -u COPILOT_AGENT_SESSION_ID \
    -u CLAUDECODE -u CLAUDE_PID -u CLAUDE_CODE_SESSION_ID \
    FM_HOME="$dir" FM_STATE_OVERRIDE="$dir/state" FM_PROC_ROOT_OVERRIDE="$dir/proc" \
    PATH="$dir/fakebin:$PATH" BASH_ENV="$dir/child-env.sh" "$@"
}

test_windows_native_ancestry_uses_verified_parent_rows() {
  local dir="$TMP_ROOT/windows-parents" out
  make_windows_process_fixture "$dir"
  out=$(windows_fixture_run "$dir" bash -c '. "$1"; fm_harness_ancestry_pids' _ "$LIB") \
    || fail "native ancestry did not bridge the MSYS parent"
  [ "$out" = "$(printf '90381\n90382')" ] \
    || fail "native ancestry lost the contiguous Claude chain or crossed its gap: $out"
  [ "$(<"$dir/native-queries")" = 'parent-processes 90380' ] \
    || fail "native ancestry did not use one query of the translated Windows PID"
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh") \
    || fail "native Windows acquisition failed: $out"
  [ "$(<"$dir/state/.lock")" = 90382 ] || fail "lock names a transient native worker"
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh" status)
  assert_contains "$out" 'held by live harness pid 90382' "native lock liveness"
  windows_fixture_run "$dir" bash -c '. "$1"; fm_session_lock_owned_by_self "$2"' \
    _ "$LIB" "$dir/state" || fail "another hook from the same native session did not own its lock"
  printf '90384\n' > "$dir/state/.lock"
  if windows_fixture_run "$dir" bash -c '. "$1"; fm_session_lock_owned_by_self "$2"' _ "$LIB" "$dir/state"; then
    fail "native ownership crossed a non-harness parent gap"
  fi
  pass "session-lock: native parent rows preserve Claude nesting, numeric PID domains, and gap refusal"
}

test_windows_native_competitor_and_stale_owner() {
  local dir="$TMP_ROOT/windows-competitor" out rc=0
  make_windows_process_fixture "$dir"
  printf '90399\n' > "$dir/state/.lock"
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
  expect_code 1 "$rc" "native competitor must prevent acquisition"
  assert_contains "$out" 'another live firstmate session' "native competitor diagnostic"
  [ "$(<"$dir/state/.lock")" = 90399 ] || fail "native competitor's lock was overwritten"
  rm "$dir/info-90399"
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh") \
    || fail "a verified dead native owner was not reclaimed: $out"
  [ "$(<"$dir/state/.lock")" = 90382 ] || fail "stale native owner was not replaced"
  pass "session-lock: native competitors stay protected and verified dead owners can be replaced"
}

test_windows_native_lookup_failure_never_means_stale() {
  local dir="$TMP_ROOT/windows-query-failure" out rc=0
  make_windows_process_fixture "$dir"
  printf '90399\n' > "$dir/state/.lock"
  : > "$dir/info-error"
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
  expect_code 1 "$rc" "failed native lookup must refuse acquisition"
  assert_contains "$out" 'cannot verify session-lock holder' "native lookup failure diagnostic"
  [ "$(<"$dir/state/.lock")" = 90399 ] || fail "query failure overwrote an unverified owner"
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh" status)
  assert_contains "$out" 'lock: unverifiable' "failed lookup was reported as a stale owner"
  rm "$dir/state/.lock"
  : > "$dir/parents-error"
  rc=0
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
  expect_code 1 "$rc" "partial rows from a failed native query must not acquire"
  [ ! -e "$dir/state/.lock" ] || fail "partial native ancestry was published as an owner"
  pass "session-lock: failed native queries neither acquire nor reclaim a lock"
}

test_windows_native_identity_does_not_trust_markers_or_bad_rows() {
  local dir="$TMP_ROOT/windows-no-proof" out rc row
  make_windows_process_fixture "$dir"
  for row in \
    $'90381\tC:/Windows/powershell.exe\tpowershell.exe -Command claude' \
    $'not-a-pid\tclaude.exe\tclaude.exe' \
    $'1\tclaude.exe\tclaude.exe'; do
    printf '%s\n' "$row" > "$dir/parents"
    rc=0
    out=$(windows_fixture_run "$dir" bash -c 'export CLAUDECODE=1; exec bash "$1"' _ "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
    expect_code 1 "$rc" "a marker or invalid row cannot establish native ancestry: $out"
    [ ! -e "$dir/state/.lock" ] || fail "unverified native process acquired the lock"
  done
  pass "session-lock: inherited markers, argument-only names, and malformed native rows remain untrusted"
}

test_windows_native_pid_collision_cannot_claim_an_msys_session() {
  local dir="$TMP_ROOT/windows-pid-collision" out rc=0
  make_windows_process_fixture "$dir"
  # PID 90382 is BOTH our native Claude and an unrelated MSYS Claude whose
  # actual native PID is 99990. A numeric lock must not conflate the sessions.
  mkdir -p "$dir/proc/90382"
  printf '99990\n' > "$dir/proc/90382/winpid"
  printf 'Name:\tclaude\nPPid:\t1\n' > "$dir/proc/90382/status"
  printf 'claude\0' > "$dir/proc/90382/cmdline"
  printf '90382\n' > "$dir/state/.lock"
  if windows_fixture_run "$dir" bash -c '. "$1"; fm_session_lock_owned_by_self "$2"' _ "$LIB" "$dir/state"; then
    fail "a native PID collision claimed an unrelated MSYS session's numeric lock"
  fi
  out=$(windows_fixture_run "$dir" bash "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
  expect_code 1 "$rc" "ambiguous native/MSYS owner must refuse acquisition: $out"
  [ "$(<"$dir/state/.lock")" = 90382 ] || fail "ambiguous owner was overwritten"
  # The reverse collision is equally unsafe: a visible MSYS Claude cannot
  # claim a numeric lock that may name a different native Claude process.
  rm -rf "$dir/proc/90382"
  printf 'Name:\tclaude\nPPid:\t1\n' > "$dir/proc/38/status"
  printf 'claude\0' > "$dir/proc/38/cmdline"
  printf '38\tC:/Tools/claude.exe\tclaude.exe\n' > "$dir/info-38"
  printf '38\n' > "$dir/state/.lock"
  if windows_fixture_run "$dir" bash -c '. "$1"; fm_session_lock_owned_by_self "$2"' _ "$LIB" "$dir/state"; then
    fail "an MSYS PID collision claimed an unrelated native session's numeric lock"
  fi
  pass "session-lock: colliding native/MSYS harness PIDs never establish ownership"
}

test_windows_orphaned_claude_uses_verified_pid_handoff() {
  local dir="$TMP_ROOT/windows-orphaned" out
  make_windows_process_fixture "$dir"
  # Real Claude can reap its intermediate launcher before a hook runs, leaving
  # no native parents either. It supplies its long-lived native session PID.
  : > "$dir/parents"
  out=$(windows_fixture_run "$dir" bash -c '
    export CLAUDECODE=1 CLAUDE_PID=90382 CLAUDE_CODE_SESSION_ID=11111111-2222-4333-8444-555555555555
    bash "$1/bin/fm-lock.sh" || exit 1
    . "$1/bin/fm-session-lock-lib.sh"
    fm_session_lock_owned_by_self "$FM_HOME/state" || exit 1
    fm_harness_pid_alive 90382
  ' _ "$ROOT") || fail "orphaned Claude did not acquire and recognize its handed-off session PID: $out"
  [ "$(<"$dir/state/.lock")" = 90382 ] || fail "orphaned Claude recorded the wrong native owner"
  # A concrete nearer session always wins over an inherited handoff marker.
  printf '90381\tclaude.exe\tclaude.exe\n' > "$dir/parents"
  out=$(windows_fixture_run "$dir" bash -c '
    export CLAUDECODE=1 CLAUDE_PID=90382 CLAUDE_CODE_SESSION_ID=11111111-2222-4333-8444-555555555555
    . "$1"; fm_harness_ancestry_pid
  ' _ "$LIB") || fail "native ancestry was lost in the presence of a handoff"
  [ "$out" = 90381 ] || fail "inherited handoff overrode a concrete native ancestor: $out"
  pass "session-lock: orphaned Claude hooks use a verified native PID handoff without overriding concrete ancestry"
}

test_windows_orphaned_claude_rejects_unverified_handoffs() {
  local dir="$TMP_ROOT/windows-bad-handoff" out rc scenario
  make_windows_process_fixture "$dir"
  : > "$dir/parents"
  printf '90398\tC:/Windows/powershell.exe\tpowershell.exe -Command claude\n' > "$dir/info-90398"
  for scenario in no-marker no-session bad-session invalid-pid foreign-pid dead-pid; do
    rc=0
    out=$(windows_fixture_run "$dir" bash -c '
      export CLAUDECODE=1 CLAUDE_PID=90382 CLAUDE_CODE_SESSION_ID=11111111-2222-4333-8444-555555555555
      case "$2" in
        no-marker) unset CLAUDECODE ;;
        no-session) unset CLAUDE_CODE_SESSION_ID ;;
        bad-session) CLAUDE_CODE_SESSION_ID="not a session" ;;
        invalid-pid) CLAUDE_PID="90382; echo forged" ;;
        foreign-pid) CLAUDE_PID=90398 ;;
        dead-pid) CLAUDE_PID=90397 ;;
      esac
      exec bash "$1/bin/fm-lock.sh"
    ' _ "$ROOT" "$scenario" 2>&1) || rc=$?
    expect_code 1 "$rc" "$scenario handoff must refuse acquisition: $out"
    [ ! -e "$dir/state/.lock" ] || fail "$scenario handoff published a lock"
  done
  pass "session-lock: orphaned hooks reject incomplete, invalid, stale and non-Claude PID handoffs"
}

# Cross the real native-Windows -> Git Bash boundary without a model session or
# any real fleet state. The renamed Node binary is only the long-lived native
# parent; the child runs the production lock executable and ownership checks.
test_native_windows_claude_session_acquires_lock() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) return 0 ;;
  esac
  local dir native_dir native_bash out rc=0
  dir="$TMP_ROOT/native-session"
  mkdir -p "$dir/state"
  native_dir=$(cygpath -w "$dir") || fail "could not convert native fixture directory"
  native_bash=$(cygpath -w "$(command -v bash)") || fail "could not resolve native Bash"
  cat > "$dir/check.sh" <<'SH'
#!/usr/bin/env bash
set -eu
"$FM_TEST_REPO/bin/fm-lock.sh"
. "$FM_TEST_REPO/bin/fm-session-lock-lib.sh"
owner=$(<"$FM_HOME/state/.lock")
[ "$owner" = "$FM_TEST_NATIVE_SESSION_PID" ] || {
  printf 'wrong session owner: expected %s, got %s\n' "$FM_TEST_NATIVE_SESSION_PID" "$owner" >&2
  exit 1
}
fm_session_lock_owned_by_self "$FM_HOME/state"
fm_harness_pid_alive "$owner"
printf 'native session owns the lock\n'
SH
  cat > "$dir/session.cjs" <<'JS'
const { spawnSync } = require("node:child_process");
const result = spawnSync(process.env.FM_TEST_NATIVE_BASH, [process.env.FM_TEST_CHECK], {
  env: { ...process.env, FM_TEST_NATIVE_SESSION_PID: String(process.pid) },
  encoding: "utf8",
  timeout: 30000,
});
process.stdout.write(result.stdout || "");
process.stderr.write(result.stderr || "");
if (result.error) throw result.error;
process.exit(result.status ?? 1);
JS
  out=$(env -u COPILOT_CLI -u COPILOT_LOADER_PID -u COPILOT_AGENT_SESSION_ID \
    FM_TEST_REPO="$ROOT" FM_HOME="$dir" FM_STATE_OVERRIDE="$dir/state" \
    FM_TEST_NATIVE_DIR="$native_dir" FM_TEST_NATIVE_BASH="$native_bash" \
    FM_TEST_CHECK="$dir/check.sh" node 2>&1 <<'JS'
const { copyFileSync } = require("node:fs");
const { join } = require("node:path");
const { spawnSync } = require("node:child_process");
const dir = process.env.FM_TEST_NATIVE_DIR;
const session = join(dir, "claude.exe");
copyFileSync(process.execPath, session);
const result = spawnSync(session, [join(dir, "session.cjs")], {
  env: process.env, encoding: "utf8", timeout: 45000,
});
process.stdout.write(result.stdout || "");
process.stderr.write(result.stderr || "");
if (result.error) throw result.error;
process.exit(result.status ?? 1);
JS
  ) || rc=$?
  expect_code 0 "$rc" "native Claude-shaped session must acquire and recognize its lock: $out"
  assert_contains "$out" 'native session owns the lock' "native session ownership proof"
  pass "session-lock: native Windows Claude parent owns the lock across the Git Bash boundary"
}

fm_test_run_cases \
  test_windows_native_ancestry_uses_verified_parent_rows \
  test_windows_native_competitor_and_stale_owner \
  test_windows_native_lookup_failure_never_means_stale \
  test_windows_native_identity_does_not_trust_markers_or_bad_rows \
  test_windows_native_pid_collision_cannot_claim_an_msys_session \
  test_windows_orphaned_claude_uses_verified_pid_handoff \
  test_windows_orphaned_claude_rejects_unverified_handoffs \
  test_native_windows_claude_session_acquires_lock \
  test_version_named_session_is_identified_on_both_platforms \
  test_ordinary_paths_are_never_harness_processes \
  test_harness_beyond_a_gap_never_owns_the_lock \
  test_competing_version_named_session_is_seen_as_live \
  test_e2e_version_named_session_claims_the_home \
  test_e2e_daemon_parented_session_claims_the_home \
  test_e2e_daemon_parented_version_named_session_keeps_its_lock
