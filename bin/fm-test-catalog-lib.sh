#!/usr/bin/env bash
# fm-test-catalog-lib.sh - validated test metadata, independent of execution.
#
# Source, then call fm_test_catalog_load <repository-root> once per invocation.
# Both tests/catalog/{core,fork}.tsv are required. Version 1 records:
#   version<TAB>1
#   family<TAB>name<TAB>gate
#   test<TAB>tests/name.test.sh<TAB>family
#   duration<TAB>tests/name.test.sh<TAB>positive-milliseconds
#   parallel-duration<TAB>tests/name.test.sh<TAB>positive-milliseconds
#   map<TAB>key<TAB>positive-order<TAB>glob|glob<TAB>target,target
# A target is a family or __script__:name.test.sh. Globs support * and ?,
# not executable shell syntax. The first matching ordered map wins.
# Fork overrides use override-<kind>, key, all old value fields, then all new
# value fields. Overrides must match the complete prior record exactly.
#
# fm_test_catalog_get <kind> <key> sets FM_TEST_CATALOG_VALUE, returns 1 if absent.
# fm_test_catalog_maps <path> prints the first matching map's targets, or returns
# 1 if unmapped. FM_TEST_CATALOG_FAMILIES and FM_TEST_CATALOG_WEIGHTS contain
# ordered family names and space-separated serial duration rows for bulk consumers.
# FM_TEST_CATALOG_PARALLEL_WEIGHTS holds separate parallel-lane duration rows.
# FM_TEST_CATALOG_RECORDS retains normalized TSV for fixture projection.
# Loading uses one awk process; lookups use Bash builtins, never eval or source
# on metadata. This module cannot admit concurrency or change worker caps.

# Encode keys injectively into scalar names for Bash 3.2's variable table.
fm_test_catalog_cache_key() {
  local kind=$1 encoded=$2 LC_ALL=C
  FM_TEST_CATALOG_CACHE_KEY=
  case "$kind" in family|test|duration|parallel-duration|map) ;; *) return 1 ;; esac
  kind=${kind//-/_}
  case "$encoded" in ''|*[!a-zA-Z0-9_./-]*) return 1 ;; esac
  encoded=${encoded//_/_u}
  encoded=${encoded//\//_s}
  encoded=${encoded//./_d}
  encoded=${encoded//-/_h}
  FM_TEST_CATALOG_CACHE_KEY="FM_TEST_CATALOG_ENTRY_${kind}_${encoded}"
}

fm_test_catalog_load() {
  local root=$1 file records kind key value rest path cache_key cache_value
  local -a catalog_inventory=()
  for file in "$root/tests/catalog/core.tsv" "$root/tests/catalog/fork.tsv"; do
    [ -f "$file" ] && [ -r "$file" ] || {
      printf 'fm-test-catalog: required catalog is missing or unreadable: %s\n' "$file" >&2
      return 2
    }
  done
  for path in "$root"/tests/*.test.sh; do
    [ -f "$path" ] || continue
    catalog_inventory+=("tests/${path##*/}")
  done
  records=$(LC_ALL=C awk -F '\t' '
    function fail(message) {
      print "fm-test-catalog: " FILENAME ":" FNR ": " message > "/dev/stderr"
      failed = 1
      exit 2
    }
    function positive(value) {
      return value ~ /^[1-9][0-9]*$/ && length(value) <= 10 && value + 0 <= 2147483647
    }
    function test_path(value) {
      return value ~ /^tests\/[A-Za-z0-9_.-]+\.test\.sh$/ && value in tests
    }
    function validate(kind, key, value,    n, fields, parts, i, count, target) {
      if (kind == "family") {
        if (key !~ /^[a-z][a-z0-9-]*$/) fail("invalid family key: " key)
        if (value !~ /^(none|herdr|optional-binary|live-capability)$/)
          fail("unknown gate: " value)
      } else if (kind == "test") {
        if (!test_path(key)) fail("test is missing or not a root-level test: " key)
        if (value !~ /^[a-z][a-z0-9-]*$/) fail("invalid family: " value)
      } else if (kind == "duration" || kind == "parallel-duration") {
        if (!test_path(key)) fail("duration references missing test: " key)
        if (!positive(value)) fail("invalid duration milliseconds: " value)
      } else if (kind == "map") {
        if (key !~ /^[a-z][a-z0-9-]*$/) fail("invalid map key: " key)
        n = split(value, fields, "\t")
        if (n != 3 || !positive(fields[1])) fail("invalid map order: " key)
        count = split(fields[2], parts, "|")
        for (i = 1; i <= count; i++) {
          if (parts[i] == "" || parts[i] !~ /^[A-Za-z0-9_.*?\/-]+$/ ||
              parts[i] ~ /^\// || parts[i] ~ /(^|\/)\.\.(\/|$)/ ||
              parts[i] ~ /\/\//)
            fail("invalid repository-relative map glob: " parts[i])
        }
        count = split(fields[3], parts, ",")
        if (!count) fail("empty map targets: " key)
        for (i = 1; i <= count; i++) {
          target = parts[i]
          if (target ~ /^__script__:/) {
            sub(/^__script__:/, "", target)
            if (!test_path("tests/" target)) fail("map references missing test: " target)
          } else if (target !~ /^[a-z][a-z0-9-]*$/) {
            fail("invalid map target: " target)
          }
        }
      } else {
        fail("unknown record kind: " kind)
      }
    }
    NR == FNR { if ($0 != "") tests[$0] = 1; next }
    FNR == 1 {
      file_count++
      if ($0 != "version\t1") fail("expected version<TAB>1 as the first line")
      next
    }
    /^#/ || /^$/ { next }
    {
      if ($0 ~ /\r/) fail("CRLF is not valid TSV; use LF")
      kind = $1
      override = sub(/^override-/, "", kind)
      width = kind == "map" ? 3 : 1
      if (kind !~ /^(family|test|duration|parallel-duration|map)$/) fail("unknown record kind: " $1)
      if (NF != 2 + width * (override ? 2 : 1)) fail("wrong field count for " $1)
      key = $2
      id = kind SUBSEP key
      value = $3
      for (i = 4; i <= 2 + width; i++) value = value "\t" $i
      if (override) {
        if (file_count != 2) fail("overrides belong in fork.tsv")
        if (!(id in values)) fail("override has no existing key: " key)
        if (values[id] != value) fail("stale override for " kind " " key)
        if (id in overridden) fail("duplicate override: " key)
        overridden[id] = 1
        value = $(3 + width)
        for (i = 4 + width; i <= NF; i++) value = value "\t" $i
      } else {
        if (id in values) fail("duplicate key; use an explicit override: " key)
        ids[++record_count] = id
        kinds[id] = kind
        keys[id] = key
      }
      validate(kind, key, value)
      values[id] = value
      locations[id] = FILENAME ":" FNR
    }
    END {
      if (failed) exit 2
      if (file_count != 2) fail("both versioned catalogs are required")
      if (values["family" SUBSEP "unclassified"] != "none")
        fail("unclassified family with gate none is required")
      for (r = 1; r <= record_count; r++) {
        id = ids[r]
        kind = kinds[id]
        value = values[id]
        if (kind == "test" && !(("family" SUBSEP value) in values))
          fail(locations[id] ": unknown family: " value)
        if (kind == "map") {
          split(value, fields, "\t")
          order = fields[1] + 0
          if (order in orders) fail("duplicate map order: " order)
          orders[order] = id
          position = ++map_count
          while (position > 1 && map_order[position - 1] > order) {
            map_order[position] = map_order[position - 1]
            position--
          }
          map_order[position] = order
          count = split(fields[3], targets, ",")
          for (t = 1; t <= count; t++)
            if (targets[t] !~ /^__script__:/ && !(("family" SUBSEP targets[t]) in values))
              fail(locations[id] ": unknown map family: " targets[t])
        }
      }
      for (r = 1; r <= record_count; r++) {
        id = ids[r]
        if (kinds[id] != "map") print kinds[id] "\t" keys[id] "\t" values[id]
      }
      for (r = 1; r <= map_count; r++) {
        id = orders[map_order[r]]
        print "map\t" keys[id] "\t" values[id]
      }
    }
  ' <(printf '%s\n' "${catalog_inventory[@]+"${catalog_inventory[@]}"}") \
    "$root/tests/catalog/core.tsv" "$root/tests/catalog/fork.tsv") || return 2

  # shellcheck disable=SC2034 # Fixture projection consumes this normalized snapshot.
  FM_TEST_CATALOG_RECORDS=$'\n'"$records"$'\n'
  FM_TEST_CATALOG_FAMILIES=
  FM_TEST_CATALOG_WEIGHTS=
  FM_TEST_CATALOG_PARALLEL_WEIGHTS=
  FM_TEST_CATALOG_MAP_PATTERNS=()
  FM_TEST_CATALOG_MAP_TARGETS=()
  for cache_key in "${FM_TEST_CATALOG_CACHE_KEYS[@]+"${FM_TEST_CATALOG_CACHE_KEYS[@]}"}"; do
    unset "$cache_key"
  done
  FM_TEST_CATALOG_CACHE_KEYS=()
  while IFS=$'\t' read -r kind key value rest; do
    fm_test_catalog_cache_key "$kind" "$key" || {
      printf 'fm-test-catalog: invalid cache key: %s %s\n' "$kind" "$key" >&2
      return 2
    }
    cache_value=$value
    [ -z "$rest" ] || cache_value+=$'\t'"$rest"
    printf -v "$FM_TEST_CATALOG_CACHE_KEY" '%s' "$cache_value" || return 2
    FM_TEST_CATALOG_CACHE_KEYS+=("$FM_TEST_CATALOG_CACHE_KEY")
    case "$kind" in
      family) FM_TEST_CATALOG_FAMILIES="${FM_TEST_CATALOG_FAMILIES}${key}"$'\n' ;;
      duration) FM_TEST_CATALOG_WEIGHTS="${FM_TEST_CATALOG_WEIGHTS}${key} ${value}"$'\n' ;;
      parallel-duration) FM_TEST_CATALOG_PARALLEL_WEIGHTS="${FM_TEST_CATALOG_PARALLEL_WEIGHTS}${key} ${value}"$'\n' ;;
      map)
        FM_TEST_CATALOG_MAP_PATTERNS+=("${rest%%$'\t'*}")
        FM_TEST_CATALOG_MAP_TARGETS+=("${rest#*$'\t'}")
        ;;
    esac
  done <<<"$records"
}

# shellcheck disable=SC2034 # FM_TEST_CATALOG_VALUE is the public lookup result.
fm_test_catalog_get() {
  FM_TEST_CATALOG_VALUE=
  fm_test_catalog_cache_key "$1" "$2" || return 1
  FM_TEST_CATALOG_VALUE=${!FM_TEST_CATALOG_CACHE_KEY-}
  [ -n "$FM_TEST_CATALOG_VALUE" ]
}

fm_test_catalog_maps() {
  local path=$1 index=0 pattern target
  local -a catalog_patterns=() catalog_targets=()
  while [ "$index" -lt "${#FM_TEST_CATALOG_MAP_PATTERNS[@]}" ]; do
    IFS='|' read -r -a catalog_patterns <<<"${FM_TEST_CATALOG_MAP_PATTERNS[$index]}"
    for pattern in "${catalog_patterns[@]}"; do
      # shellcheck disable=SC2254 # Validated catalog globs must retain wildcard matching.
      case "$path" in
        $pattern)
          IFS=',' read -r -a catalog_targets <<<"${FM_TEST_CATALOG_MAP_TARGETS[$index]}"
          for target in "${catalog_targets[@]}"; do
            printf '%s\n' "$target"
          done
          return 0
          ;;
      esac
    done
    index=$((index + 1))
  done
  return 1
}
