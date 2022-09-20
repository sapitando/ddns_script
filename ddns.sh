#!/bin/sh
# DDNS script for DynV6, IPv6 only

show_date() {
  date +"[%d.%m.%y %H:%M:%S]"
}

# Defining files path
DATA_FILE=~/.ddns/data
LOG_FILE=~/.ddns/log

# Checking DATA_FILE
if [ ! -f "$DATA_FILE" ]; then
  if [ "$(printf "%s ""$DATA_FILE" | tail -c 1)" = "/" ]; then
    printf "\033[30;107m %s > \"\033[91m%s\033[30;107m\" invalid file \033[m\n" "$(show_date)" "$DATA_FILE"
    printf "\033[30;107m %s > \033[91mexiting \033[m\n" "$(show_date)"
    exit 1
  fi
  DIR_DATA_FILE=$(printf "%s" "$DATA_FILE" | grep -Po '.*(?=/\w+[^/]$)')
  [ -n "$DIR_DATA_FILE" ] && [ ! -d "$DIR_DATA_FILE" ] && mkdir -p "$DIR_DATA_FILE" >/dev/null 2>&1
  printf "ipv6=\nlink=\nhash=\nupdated=\nnot_updated=\n" | tee "$DATA_FILE" >/dev/null 2>&1
  if [ ! -f "$DATA_FILE" ]; then
    printf "\033[30;107m %s > \"\033[91m%s\033[30;107m\" not found \033[m\n" "$(show_date)" "$DATA_FILE"
    printf "\033[30;107m %s > \033[91mexiting \033[m\n" "$(show_date)"
    exit 1
  fi
fi

# Checking LOG_FILE
if [ ! -f "$LOG_FILE" ]; then
  if [ "$(printf "%s" "$LOG_FILE" | tail -c 1)" = "/" ]; then
    printf "\033[30;107m %s > \"\033[91m%s\033[30;107m\" invalid file \033[m\n" "$(show_date)" "$LOG_FILE"
    printf "\033[30;107m %s > \033[91mexiting \033[m\n" "$(show_date)"
    exit 1
  fi
  DIR_LOG_FILE=$(printf "%s" "$LOG_FILE" | grep -Po '.*(?=/\w+[^/]$)')
  [ -n "$DIR_LOG_FILE" ] && [ ! -d "$DIR_LOG_FILE" ] && mkdir -p "$DIR_LOG_FILE" >/dev/null 2>&1
  printf "\033[30;46m>DDNS script...\033[m\n" | tee -a "$LOG_FILE" >/dev/null 2>&1
  if [ ! -f "$LOG_FILE" ]; then
    printf "\033[30;107m %s > \"\033[91m%s\033[30;107m\" not found \033[m\n" "$(show_date)" "$LOG_FILE"
    printf "\033[30;107m %s > \033[91mexiting \033[m\n" "$(show_date)"
    exit 1
  fi
fi

# Checking script arguments
if [ "$#" -eq 0 ]; then
  printf "\033[30;107m%s > invalid argument, no argument passed \033[m\n" "$(show_date)" | tee -a "$LOG_FILE"
  printf "\033[30;107m%s > \033[91mexiting \033[m\n" "$(show_date)" | tee -a "$LOG_FILE"
  exit 1
fi

# Checking for existence of argument files
for FILE in "$@"; do
  if [ ! -f "$FILE" ]; then
    printf "\033[30;107m%s > invalid argument, \033[91m%s\033[30;107m not found \033[m\n" "$(show_date)" "$FILE" | tee -a "$LOG_FILE"
    ARGUMENT_ERROR=$((ARGUMENT_ERROR + 1))
  fi
done
if [ -n "$ARGUMENT_ERROR" ]; then
  printf "\033[30;107m%s > \033[91mExiting \033[m\n" "$(show_date)" | tee -a "$LOG_FILE"
  exit 1
fi

# Checking for changes in argument files
HASH_DATA=$(grep -Pom 1 '(?<=^hash=).*' "$DATA_FILE")
HASH=$(cat "$@" | md5sum | cut -d ' ' -f 1)
if [ "$HASH_DATA" != "$HASH" ]; then
  sed -i 's/\(^hash=\).*/\1'"$HASH"'/' "$DATA_FILE"
  UPDATED=$(grep -Pom 1 '(?<=^updated=).*' "$DATA_FILE")
  sed -i 's/^updated=.*/updated=/' "$DATA_FILE"
  sed -i 's/^not_updated=/not_updated='"$UPDATED"'/' "$DATA_FILE"
fi

# Checking http client
HTTP_BIN=$({ command -v wget && printf " -qO -"; } || { command -v curl && printf " -fsS"; })
if [ -z "$HTTP_BIN" ]; then
  printf "\033[30;107m%s > HTTP client(\033[91mwget curl\033[30;107m) not found \033[m\n" "$(show_date)" | tee -a "$LOG_FILE"
  printf "\033[30;107m%s > \033[91mExiting \033[m\n" "$(show_date)" | tee -a "$LOG_FILE"
  exit 1
fi

# Checking connection status
IPV6=$(ip -6 addr show scope global | grep -Pom 1 '([0-9a-f]{0,4}[:/]){8}\d{2,3}')
LINK_STATUS=$(grep -Pom 1 '(?<=^link=).*' "$DATA_FILE")
if [ -z "$IPV6" ]; then
  [ "$LINK_STATUS" = "off" ] && exit 1
  sed -i 's/^link=.*/link=off/' "$DATA_FILE"
  sed -i 's/^ipv6=.*/ipv6=/' "$DATA_FILE"
  printf "%s \033[91mlink down\033[m\n" "$(show_date)" | tee -a "$LOG_FILE"
  exit 1
fi
[ "$LINK_STATUS" != "on" ] && sed -i 's/^link=.*/link=on/' "$DATA_FILE"

# Checking update status
IPV6_DATA=$(grep -Pom 1 '(?<=^ipv6=).*' "$DATA_FILE")
NOT_UPDATED=$(grep -Pom 1 '(?<=^not_updated=).*' "$DATA_FILE")
if [ "$IPV6" = "$IPV6_DATA" ]; then
  IPV6_STATUS="unchanged"
  [ -z "$NOT_UPDATED" ] && exit 0
else
  IPV6_STATUS="changed"
  sed -i 's|^ipv6=.*|ipv6='"$IPV6"'|' "$DATA_FILE"
  printf "%s \033[93m%s\033[m\n" "$(show_date)" "$IPV6" >>"$LOG_FILE"
fi

# Start updates
for FILE in "$@"; do
  for LINE in $(sed '/^#/d' "$FILE" | tr -s ' \t' '*'); do
    DOMAIN=$(printf "%s" "$LINE" | cut -d '*' -f 1)
    REGEX_DOMAIN=$(printf "%s" "$DOMAIN" | sed 's|\.|\\.|')
    DOMAIN_STATUS=$(grep -Pom 1 '((not_|)updated)(?=.*'"$REGEX_DOMAIN"')' "$DATA_FILE")
    # Skip update if domain is already updated
    [ "$DOMAIN_STATUS" = "updated" ] && [ "$IPV6_STATUS" = "unchanged" ] && continue
    TOKEN=$(printf "%s" "$LINE" | cut -d '*' -f 2)
    HTTP_BIN_OUTPUT=$($HTTP_BIN 'https://ipv6.dynv6.com/api/update?zone='"$DOMAIN"'&ipv6='"$IPV6"'&token='"$TOKEN"; printf "*%s" "$?")
    # SERVER_MESSAGE=$(printf "%s" "$HTTP_BIN_OUTPUT" | cut -d '*' -f 1);
    HTTP_BIN_EXIT_CODE=$(printf "%s" "$HTTP_BIN_OUTPUT" | cut -d '*' -f 2)
    if [ "$HTTP_BIN_EXIT_CODE" -eq 0 ]; then
      [ "$DOMAIN_STATUS" != "updated" ] && {
        [ "$DOMAIN_STATUS" = "not_updated" ] && sed -i '/^not_updated=/ s/'"$REGEX_DOMAIN "'//' "$DATA_FILE"
        sed -i 's/^updated=/updated='"$DOMAIN "'/' "$DATA_FILE"
      }
      printf "%s \033[92m%s\033[m updated\n" "$(show_date)" "$DOMAIN" >>"$LOG_FILE"
    else
      EXIT_CODE=$((EXIT_CODE + 1))
      [ "$DOMAIN_STATUS" != "not_updated" ] && {
        [ "$DOMAIN_STATUS" = "updated" ] && sed -i '/^updated=/ s/'"$REGEX_DOMAIN "'//' "$DATA_FILE"
        sed -i 's/^not_updated=/not_updated='"$DOMAIN "'/' "$DATA_FILE"
      }
      printf "%s [+%s] \033[91m%s\033[m not updated, code %s\n" "$(show_date)" "$EXIT_CODE" "$DOMAIN" "$HTTP_BIN_EXIT_CODE" >>"$LOG_FILE"
    fi
  done
done

# Garbage collector
NOT_UPDATED=$(grep -Pom 1 '(?<=^not_updated=).*' "$DATA_FILE")
if [ -z "$EXIT_CODE" ] && [ -n "$NOT_UPDATED" ]; then
  sed -i 's/^not_updated=.*/not_updated=/' "$DATA_FILE"
fi