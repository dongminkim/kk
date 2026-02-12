# kk plugin sort configuration

# Build zsh glob qualifier string for sorting
# Returns the appropriate glob qualifier based on KK_OPTS
_kk_build_sort_glob() {
  # case is like a mnemonic for sort order:
  # lower-case for standard, upper-case for descending
  local S_ORD="o" R_ORD="O" SPEC="n"  # default: by name

  # translate ls options to glob-qualifiers,
  # ignoring "--sort" prefix of long-args form
  case ${KK_OPTS[sort]:#--sort} in
    -U|none)                     SPEC="N";;
    -t|time)                     SPEC="m";;
    -c|ctime|status)             SPEC="c";;
    -u|atime|access|use)         SPEC="a";;
    # reverse default order for sort by size
    -S|size) S_ORD="O" R_ORD="o" SPEC="L";;
  esac

  local SORT_GLOB
  if [[ "${KK_OPTS[sort_reverse]}" == "" ]]; then
    SORT_GLOB="${S_ORD}${SPEC}"
  else
    SORT_GLOB="${R_ORD}${SPEC}"
  fi

  if [[ "${KK_OPTS[group_directories]}" != "" ]]; then
    SORT_GLOB="oe:[[ -d \$REPLY ]];REPLY=\$?:$SORT_GLOB"
  fi

  echo "$SORT_GLOB"
}

# vim: set ts=2 sw=2 ft=zsh et :
