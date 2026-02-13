# kk plugin output formatting

# Global variable for current epoch time
typeset -g K_EPOCH

# Get file color based on file characteristics
# Arguments: is_directory is_symlink is_socket is_pipe is_executable is_block_special is_character_special has_uid_bit has_gid_bit has_sticky_bit is_writable_by_others
# Returns: ANSI color code
_kk_get_file_color() {
  local is_directory=$1
  local is_symlink=$2
  local is_socket=$3
  local is_pipe=$4
  local is_executable=$5
  local is_block_special=$6
  local is_character_special=$7
  local has_uid_bit=$8
  local has_gid_bit=$9
  local has_sticky_bit=${10}
  local is_writable_by_others=${11}

  if [[ $is_directory == 1 ]]; then
    if [[ $is_writable_by_others == 1 ]]; then
      if [[ $has_sticky_bit == 1 ]]; then
        echo "${KK_COLORS[tw]}"
        return
      fi
      echo "${KK_COLORS[ow]}"
      return
    fi
    echo "${KK_COLORS[di]}"
  elif [[ $is_symlink == 1 ]]; then
    echo "${KK_COLORS[ln]}"
  elif [[ $is_socket == 1 ]]; then
    echo "${KK_COLORS[so]}"
  elif [[ $is_pipe == 1 ]]; then
    echo "${KK_COLORS[pi]}"
  elif [[ $has_uid_bit == 1 ]]; then
    echo "${KK_COLORS[su]}"
  elif [[ $has_gid_bit == 1 ]]; then
    echo "${KK_COLORS[sg]}"
  elif [[ $is_executable == 1 ]]; then
    echo "${KK_COLORS[ex]}"
  elif [[ $is_block_special == 1 ]]; then
    echo "${KK_COLORS[bd]}"
  elif [[ $is_character_special == 1 ]]; then
    echo "${KK_COLORS[cd]}"
  else
    echo "0"
  fi
}

# Get color for file size
# Arguments: file size in bytes
# Returns: color code
_kk_get_size_color() {
  local filesize=$1
  local color=$KK_LARGE_FILE_COLOR

  for i j in ${KK_SIZELIMITS_TO_COLOR[@]}; do
    (( filesize <= i )) || continue
    color=$j
    break
  done

  echo $color
}

# Get color for file age
# Arguments: timestamp (epoch seconds)
# Returns: color code
_kk_get_age_color() {
  local timestamp=$1
  local time_diff=$(( K_EPOCH - timestamp ))
  local time_color=$KK_ANCIENT_TIME_COLOR

  for i j in ${KK_FILEAGES_TO_COLOR[@]}; do
    (( time_diff < i )) || continue
    time_color=$j
    break
  done

  echo $time_color
}

# Format date based on age
# Arguments: time_diff day month time year
# Returns: formatted date string
_kk_format_date() {
  local time_diff=$1
  local day=$2
  local month=$3
  local time=$4
  local year=$5
  local date_output

  # Format date to show year if more than 6 months since last modified
  if (( time_diff < 15724800 )); then
    date_output="${day} ${(r:5:: :)${month[0,5]}} ${time}"
  else
    date_output="${day} ${(r:6:: :)${month[0,5]}} $year"  # extra space; 4 digit year instead of 5 digit HH:MM
  fi

  # If day of month begins with zero, replace zero with space (only first character)
  date_output[1]="${date_output[1]//0/ }"

  echo "$date_output"
}

# Get repository marker for Git status
# Arguments: filename
# Returns: colored repo marker
_kk_get_repo_marker() {
  local name=$1
  local vcs_status="${KK_VCS_STATUS["$name"]}"

  if [[ "$name" != ".." ]]; then
    if [[ "${KK_VCS_STATUS["."]}" == "!!" || "${KK_VCS_STATUS[".."]}" == "!!" ]]; then
      vcs_status="!!"
    elif [[ "${KK_VCS_STATUS["."]}" == "??" ]]; then
      vcs_status="??"
    fi
  fi

  if [[ "$vcs_status" == "" ]]; then
    echo "  "  # outside repository
  elif [[ "$vcs_status" == "==" ]]; then
    echo $' \e[38;5;82m|\e[0m'  # not updated
  elif [[ "$vcs_status" == "//" ]]; then
    echo $' \e[38;5;226m+\e[0m'  # changes exist inside the directory
  elif [[ "$vcs_status" == "!!" ]]; then
    echo $' \e[38;5;238m|\e[0m'  # ignored
  elif [[ "$vcs_status" == "??" ]]; then
    echo $' \e[38;5;238m?\e[0m'  # untracked
  elif [[ "${vcs_status:1:1}" == " " ]]; then
    echo $' \e[38;5;82m+\e[0m'  # index and work tree matches
  elif [[ "${vcs_status:0:1}" == " " ]]; then
    echo $' \e[38;5;196m+\e[0m'  # work tree changed since index
  else
    echo $' \e[38;5;214m+\e[0m'  # work tree changed since index and index is updated
  fi
}

# Format a single line of output
# Arguments: statvar name
# Prints: formatted line to stdout
_kk_format_line() {
  local statvar=$1
  typeset -A sv
  sv=("${(@Pkv)statvar}")

  # We check if the result is a git repo later, so set a blank marker indication the result is not a git repo
  local REPOMARKER=""
  typeset -i IS_DIRECTORY=0
  typeset -i IS_SYMLINK=0
  typeset -i IS_SOCKET=0
  typeset -i IS_PIPE=0
  typeset -i IS_EXECUTABLE=0
  typeset -i IS_BLOCK_SPECIAL=0
  typeset -i IS_CHARACTER_SPECIAL=0
  typeset -i HAS_UID_BIT=0
  typeset -i HAS_GID_BIT=0
  typeset -i HAS_STICKY_BIT=0
  typeset -i IS_WRITABLE_BY_OTHERS=0

  local PERMISSIONS="${sv[mode]}"
  local HARDLINKCOUNT="${sv[nlink]}"
  local OWNER="${sv[uid]}"
  local GROUP="${sv[gid]}"
  local FILESIZE="${sv[size]}"
  local FILESIZE_OUT="${sz[${sv[name]}]}"
  local DATE=(${(s:^:)sv[mtime]})  # Split date on ^
  local NAME="${sv[name]}"
  local SYMLINK_TARGET="${sv[link]}"

  # Check for file types
  if [[ -d "$NAME" ]]; then IS_DIRECTORY=1; fi
  if [[ -L "$NAME" ]]; then IS_SYMLINK=1; fi
  if [[ -S "$NAME" ]]; then IS_SOCKET=1; fi
  if [[ -p "$NAME" ]]; then IS_PIPE=1; fi
  if [[ -x "$NAME" ]]; then IS_EXECUTABLE=1; fi
  if [[ -b "$NAME" ]]; then IS_BLOCK_SPECIAL=1; fi
  if [[ -c "$NAME" ]]; then IS_CHARACTER_SPECIAL=1; fi
  if [[ -u "$NAME" ]]; then HAS_UID_BIT=1; fi
  if [[ -g "$NAME" ]]; then HAS_GID_BIT=1; fi
  if [[ -k "$NAME" ]]; then HAS_STICKY_BIT=1; fi
  if [[ $PERMISSIONS[9] == 'w' ]]; then IS_WRITABLE_BY_OTHERS=1; fi

  # Pad so all the lines align - firstline gets padded the other way
  PERMISSIONS="${(r:MAX_LEN[1]:)PERMISSIONS}"
  HARDLINKCOUNT="${(l:MAX_LEN[2]:)HARDLINKCOUNT}"
  OWNER="${(l:MAX_LEN[3]:)OWNER}"
  GROUP="${(l:MAX_LEN[4]:)GROUP}"
  FILESIZE_OUT="${(l:MAX_LEN[5]:)FILESIZE_OUT}"

  # Colour the permissions
  # Colour the first character based on filetype
  local FILETYPE="${PERMISSIONS[1]}"

  # Permissions Owner
  local PER1="${PERMISSIONS[2,4]}"

  # Permissions Group
  local PER2="${PERMISSIONS[5,7]}"

  # Permissions User
  local PER3="${PERMISSIONS[8,10]}"

  local PERMISSIONS_OUTPUT="$FILETYPE$PER1$PER2$PER3"

  # Colour Owner and Group
  OWNER=$'\e[38;5;241m'"$OWNER"$'\e[0m'
  GROUP=$'\e[38;5;241m'"$GROUP"$'\e[0m'

  # Colour file weights
  local COLOR=$(_kk_get_size_color "$FILESIZE")
  FILESIZE_OUT=$'\e[38;5;'"${COLOR}m$FILESIZE_OUT"$'\e[0m'

  # Colour the date and time based on age, then format for output
  # Setup colours based on time difference
  local TIME_DIFF=$(( K_EPOCH - DATE[1] ))
  local TIME_COLOR=$(_kk_get_age_color "${DATE[1]}")

  # Format date output
  local DATE_OUTPUT=$(_kk_format_date "$TIME_DIFF" "${DATE[2]}" "${DATE[3]}" "${DATE[4]}" "${DATE[5]}")

  # Apply colour to formated date
  DATE_OUTPUT=$'\e[38;5;'"${TIME_COLOR}m${DATE_OUTPUT}"$'\e[0m'

  # Clean up name
  NAME="${${${NAME%/}##*/}//$'\e'/\\e}"

  # Colour the repomarker
  if (( ${#KK_VCS_STATUS} > 0 )); then
    REPOMARKER=$(_kk_get_repo_marker "$NAME")
  fi

  # Colour the filename
  local file_color=$(_kk_get_file_color $IS_DIRECTORY $IS_SYMLINK $IS_SOCKET \
    $IS_PIPE $IS_EXECUTABLE $IS_BLOCK_SPECIAL $IS_CHARACTER_SPECIAL \
    $HAS_UID_BIT $HAS_GID_BIT $HAS_STICKY_BIT $IS_WRITABLE_BY_OTHERS)

  if [[ $IS_DIRECTORY == 1 ]]; then
    if [[ $IS_WRITABLE_BY_OTHERS == 1 ]]; then
      if [[ $HAS_STICKY_BIT == 1 ]]; then
        NAME=$'\e['"${KK_COLORS[tw]}"'m'"$NAME"$'\e[0m'
      fi
      NAME=$'\e['"${KK_COLORS[ow]}"'m'"$NAME"$'\e[0m'
    fi
    NAME=$'\e['"${KK_COLORS[di]}"'m'"$NAME"$'\e[0m'
  elif [[ $IS_SYMLINK == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[ln]}"'m'"$NAME"$'\e[0m'
  elif [[ $IS_SOCKET == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[so]}"'m'"$NAME"$'\e[0m'
  elif [[ $IS_PIPE == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[pi]}"'m'"$NAME"$'\e[0m'
  elif [[ $HAS_UID_BIT == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[su]}"'m'"$NAME"$'\e[0m'
  elif [[ $HAS_GID_BIT == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[sg]}"'m'"$NAME"$'\e[0m'
  elif [[ $IS_EXECUTABLE == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[ex]}"'m'"$NAME"$'\e[0m'
  elif [[ $IS_BLOCK_SPECIAL == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[bd]}"'m'"$NAME"$'\e[0m'
  elif [[ $IS_CHARACTER_SPECIAL == 1 ]]; then
    NAME=$'\e['"${KK_COLORS[cd]}"'m'"$NAME"$'\e[0m'
  fi

  # Format symlink target
  if [[ $SYMLINK_TARGET != "" ]]; then
    SYMLINK_TARGET=" -> ${SYMLINK_TARGET//$'\e'/\\e}"
  fi

  # Display final result
  print -r -- "$PERMISSIONS_OUTPUT $HARDLINKCOUNT $OWNER $GROUP $FILESIZE_OUT $DATE_OUTPUT$REPOMARKER $NAME$SYMLINK_TARGET"
}

# vim: set ts=2 sw=2 ft=zsh et :
