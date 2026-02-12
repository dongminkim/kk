# kk plugin utility functions

# Debug output function
# Controlled by KK_DEBUG environment variable
debug() {
  if [[ $KK_DEBUG -gt 0 ]]; then
    echo "🚥 $@" 1>&2
  fi
}

# Convert BSD LSCOLORS format to ANSI color codes
# Used on macOS/BSD systems
_kk_bsd_to_ansi() {
  local foreground=$1 background=$2 foreground_ansi background_ansi

  case $foreground in
    a) foreground_ansi=30;;
    b) foreground_ansi=31;;
    c) foreground_ansi=32;;
    d) foreground_ansi=33;;
    e) foreground_ansi=34;;
    f) foreground_ansi=35;;
    g) foreground_ansi=36;;
    h) foreground_ansi=37;;
    x) foreground_ansi=0;;
  esac

  case $background in
    a) background_ansi=40;;
    b) background_ansi=41;;
    c) background_ansi=42;;
    d) background_ansi=43;;
    e) background_ansi=44;;
    f) background_ansi=45;;
    g) background_ansi=46;;
    h) background_ansi=47;;
    x) background_ansi=0;;
  esac

  printf "%s;%s" $background_ansi $foreground_ansi
}

# Initialize local options for kk function
# Sets common options to avoid side effects
_kk_init_locals() {
  # Stop stat failing when a directory contains either no files or no hidden files
  # Track if we accidentally create a new global variable
  setopt local_options null_glob typeset_silent no_auto_pushd nomarkdirs
}

# vim: set ts=2 sw=2 ft=zsh et :
