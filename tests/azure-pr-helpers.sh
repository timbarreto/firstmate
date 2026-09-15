#!/usr/bin/env bash
# Isolated Azure CLI/API fixtures shared by PR lifecycle behavior suites.
# fm_test_azure_pr <case-dir> [source-head] installs only a read-only fake az.
# Its API response is <case-dir>/azure.json and argv evidence is azure.log.

fm_test_azure_pr() {
  local dir=$1 head=${2:-0123456789abcdef0123456789abcdef01234567}
  mkdir -p "$dir/fakebin"
  cat > "$dir/fakebin/az" <<'SH'
#!/usr/bin/env bash
set -eu
dir="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$*" >> "$dir/azure.log"
[ "${AZURE_EXTENSION_USE_DYNAMIC_INSTALL:-}" = no ] || exit 2
[ "$*" = "repos pr show --id 42 --organization https://dev.azure.com/example-org --detect false --output json --only-show-errors" ] || exit 2
if [ "${FM_TEST_AZ_FAIL:-0}" != 0 ]; then
  echo 'fixture Azure authentication/transport failure' >&2
  exit 1
fi
cat "$dir/azure.json"
SH
  chmod +x "$dir/fakebin/az"
  : > "$dir/azure.log"
  cat > "$dir/azure.json" <<EOF
{
  "pullRequestId": 42,
  "status": "active",
  "mergeStatus": "succeeded",
  "closedDate": null,
  "sourceRefName": "refs/heads/fm/task-a",
  "targetRefName": "refs/heads/main",
  "lastMergeCommit": {"commitId": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
  "lastMergeSourceCommit": {"commitId": "$head"},
  "url": "https://dev.azure.com/example-org/22222222-2222-2222-2222-222222222222/_apis/git/repositories/11111111-1111-1111-1111-111111111111/pullRequests/42",
  "repository": {
    "id": "11111111-1111-1111-1111-111111111111",
    "name": "example-repo",
    "remoteUrl": "https://dev.azure.com/example-org/Example%20Project/_git/example-repo",
    "project": {
      "id": "22222222-2222-2222-2222-222222222222",
      "name": "Example Project"
    }
  }
}
EOF
}
