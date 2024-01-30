#!/bin/bash



# Modify this line to QUORUM="" for final. No quorum should be specified
QUORUM="--quorum=5"

# Change the next line to select branch. Acceptable values are "dev" and "release"
RELEASE_TYPE="release"
# Change the next line to update the download URL
URL="https://build.xahau.tech/"
# Do not change below this line unless you know what you're doing
BASE_DIR=/opt/xahaud
USER=xahaud
PROGRAM=xahaud
BIN_DIR=$BASE_DIR/bin
DL_DIR=$BASE_DIR/downloads
DB_DIR=$BASE_DIR/db
ETC_DIR=$BASE_DIR/etc
LOG_DIR=$BASE_DIR/log
SCRIPT_LOG_FILE=$LOG_DIR/update.log
SERVICE_NAME="$PROGRAM.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
CONFIG_FILE="$ETC_DIR/$PROGRAM.cfg"
VALIDATORS_FILE="$ETC_DIR/validators-xahau.txt"

if [ -z "$(find "$BASE_DIR" -mindepth 1 -type f -size +0c -print -quit)" ] && [ -z "$(find "$DIRECTORY" -mindepth 1 -type d -empty -print -quit)" ]; then
  NOBASE=true
else
  NOBASE=false
fi

# For systemd
EXEC_COMMAND="ExecStart=$BIN_DIR/$PROGRAM $QUORUM --net --silent --conf $ETC_DIR/$PROGRAM.cfg"

# Function to log messages to the log file
log() {
  if [[ "$FIRST_RUN" == true ]]; then
    echo $1
  else
    echo $1  
    echo "$(date +"%Y-%m-%d %H:%M:%S") $1" >> "$SCRIPT_LOG_FILE"
  fi
}


clean() {
  systemctl stop $SERVICE_NAME
  systemctl disable $SERVICE_NAME
  rm $SERVICE_FILE
  systemctl daemon-reload
  userdel $USER
  rm -rf $BASE_DIR
  #rm -rf $LOG_DIR
}

#remove next line
#clean
#exit 0

[[ $EUID -ne 0 ]] && echo "This script must be run as root" && exit 1


if ! command -v gpg >/dev/null || ! command -v curl >/dev/null; then
  echo "Error: One or more of the required dependencies (gpg, curl) is not installed. Please install the missing dependencies and try again."
  exit 1
fi

if pgrep -x "xahaud" >/dev/null; then
  xahaud_pid=$(pgrep xahaud)
  xahaud_path=$(readlink -f /proc/$xahaud_pid/exe)
  if [ "$xahaud_path" = "/opt/xahaud/bin/xahaud" ]; then
    echo "xahaud is running in the expected location (/opt/xahaud/bin/xahaud) with PID: $xahaud_pid."
  else
    echo "xahaud is running with PID: $xahaud_pid, but not in the expected location. It is running from: $xahaud_path"
    exit 1
  fi
else
  echo "xahaud is not running. Continuing with installation"

fi



if [ $(id -u $USER > /dev/null 2>&1) ] || [ -f "$BASE_DIR/.firstrun" ]; then
  FIRST_RUN=false  
else  
  FIRST_RUN=true
fi

if ! id "$USER" >/dev/null 2>&1; then
  log "Creating user $USER..."
  useradd --system --no-create-home --shell /bin/false "$USER" &> /dev/null
fi

if [[ "$FIRST_RUN" == true ]]; then
  
  log "Creating directories..."
  log "$PROGRAM base directory is $BASE_DIR"
  if [ ! -d "$BASE_DIR" ]; then
    mkdir "$BASE_DIR"
  fi

  if [ ! -d "$DL_DIR" ]; then
    mkdir "$DL_DIR"
  fi

  if [ ! -d "$BIN_DIR" ]; then
    mkdir "$BIN_DIR"
  fi

  if [ ! -d "$ETC_DIR" ]; then
    mkdir "$ETC_DIR"
  fi

  if [ ! -d "$DB_DIR" ]; then
    mkdir "$DB_DIR"
  fi

  if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
  fi
  
  touch $BASE_DIR/.firstrun
  touch $SCRIPT_LOG_FILE
  chown -R $USER:$USER $BASE_DIR
  cp "$0" /usr/local/bin/.
  echo "This script has been copied to /usr/local/bin and can be invoked without a path."
fi

log "Fetching latest version of $PROGRAM..."
filenames=$(curl --silent "${URL}" | grep -Eo '>[^<]+<' | sed -e 's/^>//' -e 's/<$//' | grep -E '^\S+\+[0-9]{2,3}$' | grep -E $RELEASE_TYPE)

update_and_restart_service() {
  log "Stopping $SERVICE_NAME..."
  systemctl stop $SERVICE_NAME

  log "Backing up current binary to xahaud.old..."
  if [ -f "$BIN_DIR/$PROGRAM" ]; then
    mv "$BIN_DIR/$PROGRAM" "$BIN_DIR/$PROGRAM.old"
  fi

  log "Moving new version to $BIN_DIR/$PROGRAM..."
  if [ -f "$DL_DIR/$latest_file" ]; then
    mv "$DL_DIR/$latest_file" "$BIN_DIR/$PROGRAM"
    chmod +x "$BIN_DIR/$PROGRAM"
  else
    log "Error: Downloaded file not found."
    exit 1
  fi

  log "Restarting $SERVICE_NAME..."
  systemctl restart $SERVICE_NAME
}

# If files were found, sort them and download the latest one if it hasn't already been downloaded
if [[ -n $filenames ]]; then
  existing_binary=$(find $DL_DIR -executable -type f -size +50M|rev|cut -d "/" -f 1|rev)
  if [[ -n $existing_binary ]]; then
    if [[ "$latest_file" < "$existing_binary" ]]; then
      latest_file=$(echo "${filenames}" | sort -Vr | head -n 1)
    else
      latest_file=$(echo "${existing_binary}" | sort -Vr | head -n 1)
      log "$latest_file is binary, executable, gt 50M, in cache, we use it"
    fi
  else
    latest_file=$(echo "${filenames}" | sort -Vr | head -n 1)
    log "$latest_file is the latest available for download"
  fi

  if [[ -f "$DL_DIR/$latest_file" ]]; then
    log "File already downloaded: $latest_file"
    update_and_restart_service
  else
    log "Downloading latest file: ${latest_file} to $DL_DIR"
    curl --silent --fail "${URL}${latest_file}" -o "$DL_DIR/$latest_file"
    update_and_restart_service
  fi
else
  log "No files of type $RELEASE_TYPE found"
  exit 1
fi
