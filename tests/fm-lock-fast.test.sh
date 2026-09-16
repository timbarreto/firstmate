#!/usr/bin/env bash
# The optional batched lock mechanics must interoperate with the existing
# owner-link protocol. No production lock, process, or home is used here.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-lock-fast)
STATE="$TMP_ROOT/state"
mkdir -p "$STATE"
FM_STATE_OVERRIDE=$STATE
# shellcheck source=bin/fm-wake-lib.sh
. "$ROOT/bin/fm-wake-lib.sh"
owner_pid=''
fm_current_pid owner_pid
LOCK="$STATE/lock ' [literal]"
FAST="$ROOT/bin/fm-lock-fast.pl"

owner=$(MSYS=winsymlinks:sys perl "$FAST" acquire "$LOCK" "$owner_pid") || fail "fast acquisition failed"
[ -L "$LOCK" ] && [ "$(readlink "$LOCK")" = "$owner" ] || fail "fast acquisition changed the owner-link protocol"
[ "$(cat "$LOCK/pid")" = "$owner_pid" ] || fail "fast acquisition published another frame's PID"
if (fm_lock_try_acquire "$LOCK"); then fail "ordinary contender acquired a live fast lock"; fi
MSYS=winsymlinks:sys perl "$FAST" release "$LOCK" "$((owner_pid + 1))" || fail "foreign release should be a no-op"
[ -L "$LOCK" ] || fail "foreign fast release removed the live lock"
fm_lock_release "$LOCK"
[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ] || fail "ordinary release could not consume a fast owner"
pass "fast publication preserves the existing lock identity and cross-frame refusal"

fm_lock_try_acquire "$LOCK" || fail "ordinary acquisition failed"
MSYS=winsymlinks:sys perl "$FAST" release "$LOCK" "$owner_pid" || fail "fast release could not consume an ordinary owner"
[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ] || fail "fast release left the ordinary lock"
pass "fast release consumes the ordinary populated-owner protocol"

mkdir "$LOCK.steal"
printf '%s\n' "$owner_pid" > "$LOCK.steal/pid"
if MSYS=winsymlinks:sys perl "$FAST" acquire "$LOCK" "$owner_pid"; then fail "fast acquisition ignored a concurrent steal claim"; fi
[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ] || fail "refused fast acquisition left a published lock"
[ -f "$LOCK.steal/pid" ] || fail "fast acquisition removed a foreign recovery claim"
rm "$LOCK.steal/pid"
rmdir "$LOCK.steal"
pass "fast acquisition preserves the recovery-claim exclusion"

owner=$(MSYS=winsymlinks:sys perl "$FAST" acquire "$LOCK" "$owner_pid") || fail "second fast acquisition failed"
printf 'evidence\n' > "$owner/unknown-evidence"
MSYS=winsymlinks:sys perl "$FAST" release "$LOCK" "$owner_pid" || fail "fast release failed with unknown evidence"
[ -f "$owner/unknown-evidence" ] || fail "fast release removed an unowned artifact"
if MSYS=winsymlinks:sys perl "$FAST" acquire "$LOCK" '1; exit'; then fail "invalid owner PID reached publication"; fi
[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ] || fail "invalid PID created a lock"
pass "fast mechanics retain unknown artifacts and reject malformed owner identity"
