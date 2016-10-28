#!/bin/bash -ue

# ----------------------------------------
# Sets safe wordpress permissions so the site is less prone to being hacked.
# To be used in conjunction with harden-wordpress.sh
# ----------------------------------------

function main() {
  set_variables
  check_prerequisites 
  get_owner
  get_group
  fix_permissions
}

# ----------------------------------------
# Main functions
# ----------------------------------------

function set_variables() {
  # If you're not running the script from your web root, export the value of WWWROOT before running this script.
  : "${WWWROOT:="$PWD"}"

  WP_CONFIG="${WWWROOT}/wp-config.php"
  WP_CONTENT="${WWWROOT}/wp-content"
  WP_UPLOADS="${WP_CONTENT}/uploads"

  CORRECT_OWNER="_WILL_BE_SET_BY_get_owner_FUNCTION"
  CORRECT_GROUP="_WILL_BE_SET_BY_get_group_FUNCTION"
}

function check_prerequisites() {
  require_root
  require_wp_structure
  require_script "/usr/bin/stat"
  require_script "/usr/bin/id"
}

function get_owner() {
  GUESSED_HOME_OWNER="$(guess_home_dir_owner)"
  echo -n "Who is the correct owner of this wordpress install? [${GUESSED_HOME_OWNER}]: "
  read -r HOME_OWNER
  if test -z "$HOME_OWNER"; then
    HOME_OWNER="$GUESSED_HOME_OWNER"
  fi
  verify_user "$HOME_OWNER"
  CORRECT_OWNER="$HOME_OWNER"
}

function get_group() {
  GUESSED_UPLOADS_OWNER="$(guess_group_owner)"
  echo -n "Who is the correct PHP process owner? [${GUESSED_UPLOADS_OWNER}]: "
  read -r UPLOADS_OWNER
  if test -z "$UPLOADS_OWNER"; then
    UPLOADS_OWNER="$GUESSED_UPLOADS_OWNER"
  fi
  verify_group "$UPLOADS_OWNER"
  CORRECT_GROUP="$UPLOADS_OWNER"
}

function fix_permissions() {
  
  # @TODO: Make option to do 644/755/2755 or 640/750/2755.
  
  confirm "Ready to reset all permissions and ownership in ${WWWROOT}? Enter 'y' to continue, anything else to abort: " || abort

  info "Resetting file permissions on ${WWWROOT}"
  find "${WWWROOT}" -type f -exec chmod 644 {} \;

  info "Resetting directory permissions on ${WWWROOT}"
  find "${WWWROOT}" -type d -exec chmod 755 {} \;

  info "Resetting ownership on ${WWWROOT}"
  chown -R "$CORRECT_OWNER:" "${WWWROOT}"

  info "Resetting ownership on ${WP_UPLOADS}"
  chown -R "$CORRECT_OWNER:$CORRECT_GROUP" "${WP_UPLOADS}"

  info "Giving ${CORRECT_GROUP} write access to ${WP_UPLOADS}"
  chmod -R g+w "${WP_UPLOADS}"

  info "Applying setgid bit to directories of ${WP_UPLOADS}"
  find "${WP_UPLOADS}" -type d -exec chmod 2755 {} \;

  info "All done."

}


# ----------------------------------------
# Supporting functions
# ----------------------------------------


function guess_group_owner() {
  FALLBACK_GROUP="$(stat -c '%G' "${WP_UPLOADS}")"
  if [[ "$FALLBACK_GROUP" == "$CORRECT_OWNER" ]]; then
    info "guess_group_owner(): Current group owner of ${WP_UPLOADS} is ${FALLBACK_GROUP}; this is likely incorrect. Setting fallback default to blank."
    FALLBACK_GROUP=""
  fi

  if test -e "/etc/nginx/sites-enabled"; then
    # debian style
    VHOSTFILE="$(grep -l "$PWD" /etc/nginx/sites-enabled/*)"
    DEFAULT_GROUP="www-data"
  elif test -e "/etc/apache2/sites-enabled"; then
    # debian style
    VHOSTFILE="$(grep -l "$PWD" /etc/apache2/sites-enabled/*)"
    DEFAULT_GROUP="www-data"
  elif test -e "/etc/nginx/conf.d"; then
    # red hat style
    VHOSTFILE="$(grep -l "$PWD" /etc/nginx/conf.d/*)"
    DEFAULT_GROUP="apache"
  elif test -e "/etc/httpd/conf.d"; then
    # red hat style
    VHOSTFILE="$(grep -l "$PWD" /etc/httpd/conf.d/*)"
    DEFAULT_GROUP="apache"
  else
    info "guess_group_owner(): Could not find a virtual host configuration directory. Falling back to default."
    echo -n "${FALLBACK_GROUP}"
    return
  fi

  if test -z "$VHOSTFILE"; then
    debug "guess_group_owner(): Could not locate any virtual host configuration containing ${PWD}. Falling back to default."
    echo -n "${FALLBACK_GROUP}"
    return
  fi

  GREP_RESULT="$(grep \.sock "$VHOSTFILE")"
  if test -z "$GREP_RESULT"; then
    debug "guess_group_owner(): No mention of a php fpm unix socket file in ${VHOSTFILE} - falling back to standard web group for this OS."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  # This is super brittle, and will probably only work for my own setups.
  PHP_SOCKFILE="$(echo "$GREP_RESULT"|grep -v '[[:space:]]*#' |sed 's/fastcgi_pass unix://'|sed 's/;//'|tr -d ' ' | head -1)"

  if test -z "$PHP_SOCKFILE"; then
    debug "guess_group_owner(): Failed to grep the php-fpm.sock file. Falling back to standard web group for this OS, which is very likely NOT what you need."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  FPM_POOL="$(grep -irl "$PHP_SOCKFILE" /etc/php*)"

  if test -z "${FPM_POOL}"; then
    debug "guess_group_owner(): Failed to determine which FPM pool the socket file came from. Falling back to standard web group for this OS, which is very likely NOT what you need."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  GROUP_OWNER="$(grep ^group "$FPM_POOL")"
  if test -z "${FPM_POOL}"; then
    debug "guess_group_owner(): Failed to grep group owner from ${FPM_POOL} - falling back to standard web group for this OS, which is almost definitely NOT what you need."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  # FINALLY!
  echo -n "$GROUP_OWNER" |sed 's/^group//'|sed 's/=//' | tr -d ' '
  
}



function guess_home_dir_owner() {
  FALLBACK_OWNER="$(stat -c '%U' "${WWWROOT}")"
  if ! tree_root_is_named_home; then
    echo -n "${FALLBACK_OWNER}"
    return
  fi
  if ! home_dir_name_matches_owner_name; then
    echo -n "${FALLBACK_OWNER}"
    return
  fi
  echo -n "${OWNER}"
}



function tree_root_is_named_home() {
  # Delimiter = /
  #    / home / jack / www / project / wwwroot / ...
  # f1 / f2   / f3   / f4  / f5      / f6      / ...
  DIR_PART="$(echo "$PWD"|cut -d "/" -f2)"
  if [[ "$DIR_PART" == "home" ]]; then
    true
  else
    false
  fi
}

function home_dir_name_matches_owner_name() {
  # Delimiter = /
  #    / home / jack / www / project / wwwroot / ...
  # f1 / f2   / f3   / f4  / f5      / f6      / ...
  DIR_USER="$(echo "$PWD"|cut -d "/" -f3)"
  OWNER="$(stat -c '%U' "/home/${DIR_USER}")"
  if [[ "${OWNER}" == "${DIR_USER}" ]]; then
    true
  else
    false
  fi
}


function verify_user() {
  USERNAME="$1"
  if /usr/bin/id -u "${USERNAME}" > /dev/null; then
    true
  else
    abort
  fi
}

function verify_group() {
  GROUPNAME="$1"
  if /usr/bin/id -g "${GROUPNAME}" > /dev/null; then
    true
  else
    abort
  fi
}

# ----------------------------------------
# ----------------------------------------
# ----------------------------------------
# ----------------------------------------
# ----------------------------------------

function download() {
  SRC="${1}"
  DEST="${2}"
  back_up "${DEST}"
  curl --silent "${SRC}" > "${DEST}"
  info "${SRC} -> ${DEST}"
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
  if test -e "$WHAT"; then
    cp -av "$WHAT" "$WHAT.$(date +%s).bak"
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

# ----------------------------------------
# Supporting functions
# ----------------------------------------


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
  cerr "$@"  # Uncomment for debugging.
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


# ----------------------------------------
# Nothing happens until this line is read.
# ----------------------------------------

main "$@"
