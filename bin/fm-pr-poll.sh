#!/usr/bin/env bash
# Static watcher program for a validated pull request, merge request, or Gerrit
# change poll sidecar.
# It emits exactly one merged line for a merged change and stays silent
# otherwise, including on every error, so a failed lookup can never be read as
# a merge. The provider-tagged identity is data in the sidecar and is never
# interpolated into this source: these bytes are identical for every task.
# Each provider is read through its own standard CLI: gh for GitHub, glab for
# GitLab, gerrit-axi with jq for Gerrit, and az with the azure-devops extension
# and Perl's core JSON::PP for Azure DevOps Services.
# Provider-specific prerequisites do not apply to reads of the other forges.
#
# This static program also owns the Azure identity/response codec, so its copied
# sidecar-driven form and every trusted lifecycle caller use identical rules:
#   fm-pr-poll.sh --azure-identity <url>
#   fm-pr-poll.sh --azure-read <url>
# Both print provider, canonical URL, host, path, number on separate lines.
# --azure-read additionally prints status and the source head ("-" if unknown).
# Browser and repository-scoped REST URLs on dev.azure.com or the legacy
# <org>.visualstudio.com[/DefaultCollection] host are accepted. REST URLs may
# omit the project and include only an api-version query. Names are UTF-8
# percent-encoded; separators, controls, traversal and double encoding refuse.
# Registration resolves aliases through a native read to one browser identity.
# A read verifies the response's organization, project, target repository and PR
# number, never az's configured default. Only status=completed proves completion;
# mergeStatus and a lastMergeCommit preview on an active PR do not.
set -u
LC_ALL=C
export LC_ALL

azure_pr_record() {  # identity|response <url>; response JSON arrives on stdin
  perl -MJSON::PP -MEncode=decode,encode,FB_CROAK -e '
    use strict;
    use warnings;
    sub reject {
      print STDERR "error: invalid Azure DevOps PR identity or response\n";
      exit 2;
    }
    sub text {
      my ($value) = @_;
      return defined($value) && !ref($value) && encode_json($value) =~ /\A"/;
    }
    sub name {
      my ($value) = @_;
      reject() unless text($value) && length($value) && length($value) <= 255;
      reject() if $value =~ /[\p{C}\/\\%?#]/ || $value =~ /[^\S ]/
        || $value eq "." || $value eq ".." || $value =~ /\A | \z/;
      return $value;
    }
    sub component {
      my ($encoded) = @_;
      reject() unless $encoded =~ /\A(?:[A-Za-z0-9._~-]|%[0-9A-Fa-f]{2})+\z/;
      $encoded =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
      my $decoded = eval { decode("UTF-8", $encoded, FB_CROAK) };
      reject() if $@;
      return name($decoded);
    }
    sub escape {
      my $value = $_[0];
      my $bytes = encode("UTF-8", $value, FB_CROAK);
      $bytes =~ s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge;
      return $bytes;
    }
    sub parse {
      my ($raw) = @_;
      reject() unless text($raw) && length($raw) <= 4096;
      my ($org, $rest);
      if ($raw =~ m{\Ahttps://dev\.azure\.com/([^/]+)/(.+)\z}) {
        ($org, $rest) = ($1, $2);
      } elsif ($raw =~ m{\Ahttps://([A-Za-z0-9-]+)\.visualstudio\.com/(?:DefaultCollection/)?(.+)\z}) {
        ($org, $rest) = ($1, $2);
      } else {
        reject();
      }
      reject() unless $org =~ /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?\z/;
      $org = lc($org);
      my ($project, $repo, $number, $route);
      if ($rest =~ m{\A([^/]+)/_git/([^/]+)/pullrequest/([1-9][0-9]*)\z}) {
        ($project, $repo, $number, $route) = ($1, $2, $3, "browser");
      } elsif ($rest =~ m{\A(?:([^/]+)/)?_apis/git/repositories/([^/]+)/pull[Rr]equests/([1-9][0-9]*)(?:\?api-version=[0-9]+\.[0-9]+(?:-preview(?:\.[0-9]+)?)?)?\z}) {
        ($project, $repo, $number, $route) = ($1, $2, $3, "api");
      } else {
        reject();
      }
      reject() if length($number) > 10 || $number > 2147483647;
      $project = defined($project) ? component($project) : "";
      $repo = component($repo);
      my $path = $org . (length($project) ? "/" . escape($project) : "");
      $path .= $route eq "browser"
        ? "/_git/" . escape($repo) . "/pullrequest"
        : "/_apis/git/repositories/" . escape($repo) . "/pullRequests";
      return { org => $org, project => $project, repo => $repo, number => $number,
        route => $route, path => $path, url => "https://dev.azure.com/$path/$number" };
    }
    sub guid {
      return text($_[0]) && $_[0] =~ /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i;
    }
    sub matches {
      my ($selector, $object) = @_;
      return $selector eq $object->{name} || lc($selector) eq lc($object->{id});
    }
    my ($mode, $raw) = @ARGV;
    my $identity = parse($raw);
    my @extra;
    if ($mode eq "response") {
      my $json = do { local $/; <STDIN> };
      my $pr = eval { decode_json($json) };
      reject() if $@ || ref($pr) ne "HASH";
      reject() unless defined($pr->{pullRequestId})
        && encode_json($pr->{pullRequestId}) eq $identity->{number};
      my $repo = $pr->{repository};
      reject() unless ref($repo) eq "HASH" && guid($repo->{id});
      my $project = $repo->{project};
      reject() unless ref($project) eq "HASH" && guid($project->{id});
      name($repo->{name});
      name($project->{name});
      reject() unless matches($identity->{repo}, $repo)
        && (!$identity->{project} || matches($identity->{project}, $project));
      my $response = parse($pr->{url});
      reject() unless $response->{route} eq "api"
        && $response->{org} eq $identity->{org}
        && $response->{number} eq $identity->{number}
        && matches($response->{repo}, $repo)
        && (!$response->{project} || matches($response->{project}, $project));
      my $state = $pr->{status};
      reject() unless text($state) && $state =~ /\A(?:active|completed|abandoned)\z/;
      my $head = "-";
      if (defined($pr->{lastMergeSourceCommit})) {
        reject() unless ref($pr->{lastMergeSourceCommit}) eq "HASH";
        $head = $pr->{lastMergeSourceCommit}{commitId};
        reject() unless text($head) && $head =~ /\A[0-9a-f]{40}\z/;
      }
      $identity = parse("https://dev.azure.com/$identity->{org}/"
        . escape($project->{name}) . "/_git/" . escape($repo->{name})
        . "/pullrequest/$identity->{number}");
      @extra = ($state, $head);
    } else {
      reject() unless $mode eq "identity";
    }
    print join("\n", "azure", $identity->{url}, "dev.azure.com",
      $identity->{path}, $identity->{number}, @extra), "\n";
  ' "$@"
}

azure_pr_read() {
  local url=$1 identity org number raw
  command -v az >/dev/null 2>&1 || {
    echo "error: watching an Azure DevOps PR requires az with the azure-devops extension on PATH" >&2
    return 1
  }
  identity=$(azure_pr_record identity "$url") || return 1
  org=$(printf '%s\n' "$identity" | sed -n '4s#/.*##p')
  number=$(printf '%s\n' "$identity" | sed -n '5p')
  # Do not install an extension or infer another organization while monitoring.
  raw=$(AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no az repos pr show \
    --id "$number" --organization "https://dev.azure.com/$org" --detect false \
    --output json --only-show-errors) || {
    echo "error: Azure DevOps PR lookup failed; check az authentication and the azure-devops extension" >&2
    return 1
  }
  printf '%s' "$raw" | azure_pr_record response "$url"
}

case "${1:-}" in
  --azure-identity|--azure-read)
    [ "$#" -eq 2 ] || exit 2
    if [ "$1" = --azure-identity ]; then
      azure_pr_record identity "$2"
    else
      azure_pr_read "$2"
    fi
    exit "$?"
    ;;
esac

if [ "$#" -eq 6 ] && [ "$1" = --validated ]; then
  provider=$2
  url=$3
  host=$4
  path=$5
  number=$6
elif [ "$#" -eq 0 ]; then
  case "$0" in
    *.check.sh) data=${0%.check.sh}.pr-poll ;;
    *) exit 0 ;;
  esac

  [ -f "$data" ] && [ ! -L "$data" ] || exit 0
  { exec 3< "$data"; } 2>/dev/null || exit 0
  IFS= read -r provider <&3 || exit 0
  IFS= read -r url <&3 || exit 0
  IFS= read -r host <&3 || exit 0
  IFS= read -r path <&3 || exit 0
  IFS= read -r number <&3 || exit 0
  if IFS= read -r _extra <&3; then
    exit 0
  fi
  exec 3<&-
else
  exit 0
fi

case "$number" in
  [1-9]*) ;;
  *) exit 0 ;;
esac
case "$number" in
  *[!0-9]*) exit 0 ;;
esac

# Every component is revalidated here rather than trusted from the sidecar, and
# the stored URL must then be exactly reconstructible from those components, so
# a doctored sidecar cannot redirect this poll at another host or project.
case "$provider" in
  github)
    [ "$host" = github.com ] || exit 0
    owner=${path%%/*}
    repo=${path#*/}
    [ "${#owner}" -ge 1 ] && [ "${#owner}" -le 39 ] || exit 0
    case "$owner" in
      *[!A-Za-z0-9-]*|-*|*-|*--*) exit 0 ;;
    esac
    [ "${#repo}" -ge 1 ] && [ "${#repo}" -le 100 ] || exit 0
    case "$repo" in
      .|..|*[!A-Za-z0-9._-]*) exit 0 ;;
    esac
    [ "$url" = "https://github.com/$owner/$repo/pull/$number" ] || exit 0
    state=$(gh pr view "$url" --json state -q .state 2>/dev/null) || exit 0
    [ "$state" = MERGED ] && printf '%s\n' merged
    ;;
  gitlab)
    [ "${#host}" -ge 1 ] && [ "${#host}" -le 253 ] || exit 0
    [ "$host" != github.com ] || exit 0
    case "$host" in
      .*|*.|*..*|*[!a-z0-9.-]*) exit 0 ;;
    esac
    [ "${#path}" -ge 3 ] && [ "${#path}" -le 1024 ] || exit 0
    case "$path" in
      /*|*/|*//*) exit 0 ;;
    esac
    # A GitLab project sits under at least one group at no fixed depth, and
    # GitLab reserves the "-" segment as its route separator.
    rest=$path
    segments=0
    while [ -n "$rest" ]; do
      case "$rest" in
        */*) segment=${rest%%/*}; rest=${rest#*/} ;;
        *) segment=$rest; rest= ;;
      esac
      segments=$((segments + 1))
      [ "$segments" -le 20 ] || exit 0
      [ "${#segment}" -ge 1 ] && [ "${#segment}" -le 255 ] || exit 0
      case "$segment" in
        .|..|-*|*.git|*.atom|*[!A-Za-z0-9._-]*) exit 0 ;;
      esac
    done
    [ "$segments" -ge 2 ] || exit 0
    [ "$url" = "https://$host/$path/-/merge_requests/$number" ] || exit 0
    # glab resolves the instance from the project URL passed to -R, so the host
    # comes from the validated record rather than glab's configured default.
    # It cannot take a merge request URL the way gh does: that form shells out
    # to git for the current repository, and the watcher runs in no repository.
    # The state is read from glab's own field output rather than its JSON,
    # because plain glab has no field selector and firstmate does not require a
    # JSON processor; only an exact "merged" wakes, so a changed format or an
    # unreadable merge request stays silent instead of reporting a merge.
    raw=$(glab mr view "$number" -R "https://$host/$path" 2>/dev/null) || exit 0
    state=$(printf '%s\n' "$raw" | sed -n 's/^state:[[:space:]]*//p' | head -1) || exit 0
    [ "$state" = merged ] && printf '%s\n' merged
    ;;
  azure)
    identity=$(azure_pr_record identity "$url" 2>/dev/null) || exit 0
    [ "$identity" = "$(printf '%s\n' azure "$url" "$host" "$path" "$number")" ] || exit 0
    record=$(azure_pr_read "$url" 2>/dev/null) || exit 0
    state=$(printf '%s\n' "$record" | sed -n '6p')
    [ "$state" = completed ] && printf '%s\n' merged
    ;;
  gerrit)
    [ "${#host}" -ge 1 ] && [ "${#host}" -le 253 ] || exit 0
    [ "$host" != github.com ] || exit 0
    case "$host" in
      .*|*.|*..*|*[!a-z0-9.-]*) exit 0 ;;
    esac
    [ "${#path}" -ge 1 ] && [ "${#path}" -le 1024 ] || exit 0
    case "$path" in
      /*|*/|*//*) exit 0 ;;
    esac
    # A Gerrit project name is a path at no fixed depth that needs no enclosing
    # group, so one segment is canonical here where GitLab needs two, and Gerrit
    # reserves no route segment inside it.
    rest=$path
    segments=0
    while [ -n "$rest" ]; do
      case "$rest" in
        */*) segment=${rest%%/*}; rest=${rest#*/} ;;
        *) segment=$rest; rest= ;;
      esac
      segments=$((segments + 1))
      [ "$segments" -le 20 ] || exit 0
      [ "${#segment}" -ge 1 ] && [ "${#segment}" -le 255 ] || exit 0
      case "$segment" in
        .|..|-*|*.git|*[!A-Za-z0-9._-]*) exit 0 ;;
      esac
    done
    [ "$segments" -ge 1 ] || exit 0
    [ "$url" = "https://$host/c/$path/+/$number" ] || exit 0
    # gerrit-axi resolves its server from the current directory's origin remote
    # first, and the watcher runs in no repository, so the host must be passed
    # explicitly from the validated record. Without it the tool has no host to
    # reach and fails before reading anything, and this poll is silent on every
    # failure, so the watch would wait forever on a change it never looked at.
    #
    # The status is read explicitly and is the only thing that can wake this
    # poll. Gerrit's submittability is a different question: a merged change
    # still reports its submit state as OK with nothing blocking it, so reading
    # submittability, a blocked_on list, or vote values would report a merge for
    # an open change that is merely ready to submit.
    #
    # jq selects the one record whose change number matches. A change number is
    # server-global and --host already pins the server, so the number alone
    # names the change. The record's own url field is deliberately not compared
    # against the stored URL: Gerrit composes that field from
    # gerrit.canonicalWebUrl and omits it when that setting is unset, so an
    # equality test would leave a correctly armed watch silent forever on such
    # a server, and this poll has no channel to report that it never matched.
    json=$(gerrit-axi show "$number" --host "$host" --json 2>/dev/null) || exit 0
    [ -n "$json" ] || exit 0
    status=$(printf '%s' "$json" | jq -r --argjson change "$number" '
      if type == "object" and .ok == true and (.changes | type) == "array" then
        [.changes[] | select((.change | type) == "number" and .change == $change)] as $match
        | if ($match | length) == 1
             and ($match[0].status | type) == "string"
          then $match[0].status
          else error("no exact change record")
          end
      else
        error("invalid gerrit record")
      end' 2>/dev/null) || exit 0
    [ "$status" = MERGED ] && printf '%s\n' merged
    ;;
  *) exit 0 ;;
esac
exit 0
