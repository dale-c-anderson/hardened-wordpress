#!/bin/bash -ue


function main() {
  set_variables
  check_prerequisites
  show_disclaimer
  place_htaccess_files
  disallow_file_edit
  info "All done. You should now run fix-wordpress-permissions.sh"
}

function set_variables() {
  # If you're not running the script from your web root, export the value of WWWROOT before running this script.
  : "${WWWROOT:="$PWD"}"
  WP_CONFIG="${WWWROOT}/wp-config.php"
  WP_CONTENT="${WWWROOT}/wp-content"
  WP_UPLOADS="${WP_CONTENT}/uploads"
  REPO_SRC="https://raw.githubusercontent.com/dale-c-anderson/hardened-wordpress/master/wwwroot"
}

function check_prerequisites() {
  require_wp_structure
  require_script "curl"
  require_script "diff"
}

function show_disclaimer() {
  DISCLAIMER="This script is intended to remove Wordpress's ability to modify itself. This includes removing the ability to automatically update, removing the ability to update themes / modules from the admin section, and removing the ability to edit any files via the admin section."
  if is_interactive_shell; then
    confirm "$DISCLAIMER Enter 'y' to continue, or anything else to abort: "
  else
    info "$DISCLAIMER"
  fi
}

function place_htaccess_files() {
  for DIR in / /wp-admin/ /wp-content/ /wp-includes/; do
    SRC="${REPO_SRC}${DIR}.htaccess"
    DEST="${WWWROOT}${DIR}.htaccess"
    download "${SRC}" "${DEST}"
  done
}

function download() {
  SRC="${1}"
  DEST="${2}"
  back_up "${DEST}"
  curl --silent "${SRC}" > "${DEST}"
  info "${SRC} -> ${DEST}"
}

function is_interactive_shell() {
  if [ -t 1 ] ; then 
    true
  else
    false
  fi
}

function disallow_file_edit() {
  DEFINE_DISALLOW="define('DISALLOW_FILE_EDIT', true);"
  if grep "^${DEFINE_DISALLOW}" "${WP_CONFIG}"; then
    : # It's already present.
  else
    back_up "${WP_CONFIG}"
    echo "${DEFINE_DISALLOW}" >> "${WP_CONFIG}"
  fi
}

function confirm () {
  echo -n "$@"
  read -r CONFIRMATION
  if [[ "${CONFIRMATION}" != 'y' ]]; then
    echo "Aborting."
    false
  fi
}

function back_up() {
  WHAT="$1"
  BACKUPS="$HOME/backups"
  test -d "${BACKUPS}" || (umask 077 && mkdir -v "${BACKUPS}")
  if test -e "$WHAT"; then
    BAKFILE="${BACKUPS}/$(basename "${WHAT}").$(date +%s).tar"
    info "Backing up '${WHAT}' to '${BAKFILE}'"
    if test -e "$BAKFILE"; then
      tar --append --file "$BAKFILE" "$WHAT"
    else
      (umask 077 && tar --create --file "$BAKFILE" "$WHAT")
    fi
  fi
}

function require_wp_structure() {
  ERRORS=0
  test -w "$WP_CONFIG" || {
    err "WP_CONFIG does not exist or is not writable: $WP_CONFIG"
    ERRORS=$((ERRORS + 1))
  }
  test -w "$WP_CONTENT" || {
    err "WP_CONTENT does not exist or is not writable: $WP_CONTENT"
    ERRORS=$((ERRORS + 1))
  }
  test -w "$WP_UPLOADS" || {
    err "WP_UPLOADS does not exist or is not writable: $WP_UPLOADS"
    ERRORS=$((ERRORS + 1))
  }
  if [ "$ERRORS" -gt 0 ]; then
    abort
  fi
}


function require_script () {
  type "$1" > /dev/null  2>&1 || {
    err "The following is not installed or not in path: $1"
    abort
  }
}

function require_package () {
  type "$1" > /dev/null  2>&1 || {
    apt-get -y install "$1" || yum -y install "$1"
  }
}

function require_root() {
  if [ $EUID -ne 0 ]; then
    err "This script must be run as root."
    abort
  fi
}

function fatal () {
  bold_feedback "Fatal" "$@"
}

function err () {
  bold_feedback "Err" "$@"
}

function info () {
  cerr "$@"
}

function debug () {
  #cerr "$@"  # Uncomment for debugging.
  true  # Bash functions can't be empty.
}

function bold_feedback () {
  BOLD=$(tput bold)
  UNBOLD=$(tput sgr0)
  cerr "${BOLD}${1}:${UNBOLD} ${2}"
}

function abort () {
  cerr "Aborting."
  exit 1
}

function cerr() {
  >&2 echo "$@"
}

main "$@"
