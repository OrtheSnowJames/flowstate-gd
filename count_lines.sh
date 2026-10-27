# loc_by_ext is a command I have in my zshrc, I put it in a script though
loc_by_ext() {
  if (( $# == 0 )) || [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: loc_by_ext EXT [EXT ...] [--exclude DIR ...]
Count total lines for one or more file extensions under the current directory.

Examples:
  loc_by_ext lua
  loc_by_ext lua py js
  loc_by_ext .lua .py
  loc_by_ext gd --exclude tests build
EOF
    return 0
  fi

  local -a exts excludes
  local arg ext clean_ext count

  # Parse arguments
  while (( $# )); do
    if [[ "$1" == "--exclude" ]]; then
      shift
      while (( $# )) && [[ "$1" != --* ]]; do
        excludes+=("$1")
        shift
      done
    else
      exts+=("$1")
      shift
    fi
  done

  if (( ${#exts[@]} == 0 )); then
    echo "loc_by_ext: missing file extension" >&2
    return 1
  fi

  for ext in "${exts[@]}"; do
    if [[ "$ext" == -* ]]; then
      echo "loc_by_ext: unknown option: $ext" >&2
      echo "Try: loc_by_ext --help" >&2
      return 1
    fi

    clean_ext="${ext#.}"

    # Build find's prune expression
    local -a find_args
    find_args=(.)

    if (( ${#excludes[@]} )); then
      find_args+=( '(' )
      local dir first=1
      for dir in "${excludes[@]}"; do
        (( first )) || find_args+=( -o )
        find_args+=( -type d -name "$dir" )
        first=0
      done
      find_args+=( ')' -prune -o )
    fi

    find_args+=( -type f -name "*.${clean_ext}" -exec cat {} + )

    count=$(find "${find_args[@]}" 2>/dev/null | wc -l | tr -d ' ')
    printf '%s: %s lines\n' "$clean_ext" "$count"
  done
}

loc_by_ext gd --exclude addons .godot .git android tests demo mesh img audio product_images
