# shellcheck shell=bash
# manifest.sh — parse the small fleet.toml subset (supervisor table + [[child]]
# array-of-tables). We only support `key = "string"` and `key = number`, plus
# `[supervisor]` and repeated `[[child]]` blocks. No nesting, no inline tables.

# Globals populated by fleet_manifest_load:
#   SUP_STRATEGY SUP_MAX_RESTARTS SUP_MAX_SECONDS SUP_PROVIDER
#   CHILD_IDS  (bash array of ids, in manifest order)
#   CHILD_<id>_<field>  via fleet_child_get
# Fields stored in an associative array MANIFEST_KV keyed "<id>.<field>".

declare -gA MANIFEST_KV
declare -ga CHILD_IDS

# strip surrounding quotes and trailing inline comments from a TOML value
_toml_value() {
  local v="$1"
  # drop a ' #...' trailing comment when not inside quotes (best-effort: only
  # strip when the value is unquoted or after the closing quote)
  if [[ "$v" =~ ^\"(.*)\"[[:space:]]*(#.*)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    v="${v%%#*}"
    # trim
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    printf '%s\n' "$v"
  fi
}

fleet_manifest_load() {
  local file="$1"
  [[ -f "$file" ]] || die "manifest not found: $file"
  MANIFEST_KV=(); CHILD_IDS=()
  SUP_STRATEGY="one_for_one"; SUP_MAX_RESTARTS=3; SUP_MAX_SECONDS=60; SUP_MAX_HOPS=6; SUP_PROVIDER="${FLEET_AGENT_PROVIDER:-claude}"

  local section="" cur_id="" anon=0 line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    # strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    if [[ "$line" == "[[child]]" ]]; then
      section="child"; cur_id=""; anon=$(( anon + 1 ))
      # provisional id; replaced if the block sets one
      cur_id="__anon$anon"
      CHILD_IDS+=("$cur_id"); continue
    fi
    if [[ "$line" =~ ^\[([a-zA-Z0-9_]+)\]$ ]]; then
      section="${BASH_REMATCH[1]}"; cur_id=""; continue
    fi

    [[ "$line" =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"; val="$(_toml_value "${BASH_REMATCH[2]}")"

    case "$section" in
      supervisor)
        case "$key" in
          strategy)     SUP_STRATEGY="$val" ;;
          max_restarts) SUP_MAX_RESTARTS="$val" ;;
          max_seconds)  SUP_MAX_SECONDS="$val" ;;
          max_hops)     SUP_MAX_HOPS="$val" ;;
          provider|default_provider) SUP_PROVIDER="$val" ;;
        esac
        ;;
      child)
        if [[ "$key" == "id" ]]; then
          # rename the provisional id to the real one
          local old="$cur_id" i mk
          cur_id="$val"
          for i in "${!CHILD_IDS[@]}"; do
            [[ "${CHILD_IDS[$i]}" == "$old" ]] && CHILD_IDS[$i]="$cur_id"
          done
          # migrate any fields stored BEFORE `id` was seen (TOML need not put id first)
          for mk in "${!MANIFEST_KV[@]}"; do
            if [[ "$mk" == "$old".* ]]; then
              MANIFEST_KV["$cur_id.${mk#"$old".}"]="${MANIFEST_KV[$mk]}"
              unset 'MANIFEST_KV[$mk]'
            fi
          done
        fi
        MANIFEST_KV["$cur_id.$key"]="$val"
        ;;
    esac
  done <"$file"
}

# fleet_child_get <id> <field> [default]
fleet_child_get() {
  local id="$1" field="$2" def="${3:-}"
  local v="${MANIFEST_KV["$id.$field"]:-}"
  printf '%s\n' "${v:-$def}"
}
