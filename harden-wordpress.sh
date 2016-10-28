#!/bin/bash -ue


function main() {
  set_variables
  check_prerequisites
  echo "This script is intended to remove Wordpress's ability to modify itself. This includes removing the ability to automatically update, removing the ability to update themes and modules from the admin section, and removing the ability to edit any files via the admin section."
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
  require_script "/usr/bin/curl"
  require_script "/usr/bin/cmp"
  require_script "/usr/bin/tee"
}

function place_htaccess_files() {
  for DIR in / /wp-admin/ /wp-content/ /wp-includes/; do
    local TEMPFILE="$(mktemp)"
    local SRC="${REPO_SRC}${DIR}.htaccess"
    local DEST="${WWWROOT}${DIR}.htaccess"
    download "$SRC" "$TEMPFILE"
    MOVE=0
    if test -e "${DEST}"; then
      if cmp -s "$TEMPFILE" "$DEST"; then
        info "Skipping $DEST (already hardened)"
      else
        if confirm "Replace ${DEST}? (a backup will be made) [y/N]: "; then
          MOVE=1
        fi
      fi
    else
      MOVE=1
    fi
    if [ $MOVE -eq 1 ]; then
      back_up_in_place "${DEST}"
      mv -v "${TEMPFILE}" "${DEST}"
      chmod 644 "${DEST}" # If we dont do this, the web server won't be able to read it.
    else
      rm "${TEMPFILE}"
    fi
  done
}

function download() {
  local SRC="${1}"
  local DEST="${2}"
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
  if grep --quiet "^${DEFINE_DISALLOW}" "${WP_CONFIG}"; then
    info "Wp-config.php already disallows file editing."
  else
    if confirm "Add DEFINE_DISALLOW to wp-config.php? (a backup will be made) [y/N]: "; then
      back_up_to_home "${WP_CONFIG}"
      echo "${DEFINE_DISALLOW}" >> "${WP_CONFIG}"
      info "\"${DEFINE_DISALLOW}\" >> ${WP_CONFIG}"
    fi
  fi
}

function confirm () {
  echo -n "$@"
  read -r CONFIRMATION
  if [[ "${CONFIRMATION}" == 'y' ]]; then
    true
  else
    false
  fi
}

function back_up_to_home() {
  local WHAT="$1"
  local BACKUPS="$HOME/backups"
  test -d "${BACKUPS}" || (umask 077 && mkdir -v "${BACKUPS}")
  if test -e "$WHAT"; then
    local BAKFILE="${BACKUPS}/$(basename "${WHAT}").$(date +%s).tar"
    info "Backing up '${WHAT}' to '${BAKFILE}'"
    if test -e "$BAKFILE"; then
      tar --append --file "$BAKFILE" "$WHAT"
    else
      (umask 077 && tar --create --file "$BAKFILE" "$WHAT")
    fi
  fi
}

function back_up_in_place() {
  local WHAT="$1"
  if test -e "$WHAT"; then
    # It only makes sense to back up the file if actually exists!
    local BAKFILE="${WHAT}.$(date +%s.%N)~"
    cp -av "$WHAT" "$BAKFILE"
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
  local WHAT="$1"
  type "$WHAT" > /dev/null  2>&1 || {
    err "The following is not installed or not in path: $WHAT"
    abort
  }
}

function require_package () {
  local WHAT="$1"
  type "$WHAT" > /dev/null  2>&1 || {
    apt-get -y install "$WHAT" || yum -y install "$WHAT"
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
