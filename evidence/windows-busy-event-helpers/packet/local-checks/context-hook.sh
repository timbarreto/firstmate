_fm_test_seen_depth=$BASH_SUBSHELL
set -T
trap 'if [ "$BASH_SUBSHELL" -ne "$_fm_test_seen_depth" ]; then _fm_test_seen_depth=$BASH_SUBSHELL; printf "%s\n" "$BASH_SUBSHELL" >> "$FM_TEST_CONTEXT_LOG"; fi' DEBUG
