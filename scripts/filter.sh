#!/usr/bin/env bash
# Sourced by scripts/recover.sh.

# glob_to_regex <glob> -> anchored regex for jq's test(). Only * and ? are special.
glob_to_regex() {
  local glob="$1" out="" c i
  for ((i = 0; i < ${#glob}; i++)); do
    c="${glob:i:1}"
    case "$c" in
      '*') out+='.*' ;;
      '?') out+='.' ;;
      [A-Za-z0-9_]) out+="$c" ;;
      *) out+="\\$c" ;;
    esac
  done
  printf '^%s$' "$out"
}

# filter_secrets <json-string> <include-csv>
# stdout: filtered JSON object. exit 2: not an object. exit 3: nothing matched.
# Never prints names or values on error.
filter_secrets() {
  local json="$1" include="$2" regexes='[]' explicit_token=false entry
  jq -e 'type == "object"' <<<"$json" >/dev/null 2>&1 || return 2

  local -a entries=()
  IFS=',' read -ra entries <<<"$include"
  for entry in ${entries[@]+"${entries[@]}"}; do   # safe under set -u on bash 3.2
    entry="${entry//[[:space:]]/}"
    [[ -z "$entry" ]] && continue
    [[ "$entry" == "github_token" ]] && explicit_token=true
    regexes="$(jq -c --arg r "$(glob_to_regex "$entry")" '. + [$r]' <<<"$regexes")"
  done

  local result
  result="$(jq -c --argjson rx "$regexes" --argjson tok "$explicit_token" '
    with_entries(select(
      (.key != "github_token" or $tok)
      and (($rx | length) == 0 or (.key as $k | any($rx[]; . as $r | $k | test($r))))
    ))' <<<"$json")"
  [[ "$(jq 'length' <<<"$result")" -gt 0 ]] || return 3
  printf '%s\n' "$result"
}
