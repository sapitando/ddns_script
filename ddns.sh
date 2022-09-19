#!/bin/sh
# DDNS script for DynV6
# IPv6 only

show_date() {
  date +"[%d.%m.%y %H:%M:%S]"
}

# Setting files
DATA_FILE=~/.ddns/data
LOG_FILE=~/.ddns/log

# Generate "data" and "log" files if not found
[ ! -f "$LOG_FILE" ] && printf "\033[30;46m>DDNS script...\033[m\n" >"$LOG_FILE"
if [ ! -f "$DATA_FILE" ]; then
  printf "ipv6=\nupdated=\nnot_updated=\n" >"$DATA_FILE"
else
  # Get current ip for comparison and check if there were failed updades
  LAST_IPV6=$(grep -Pom 1 '(?<=^ipv6=).*' "$DATA_FILE")
  NOT_UPDATED=$(grep -Pom 1 '(?<=^not_updated=).*' "$DATA_FILE")
fi

# Get current ipv6 if available
IPV6=$(ip -6 addr show scope global | grep -Pom 1 '([0-9a-f]{0,4}[:/]){8}\d{2,3}')
[ -z "$IPV6" ] && {
  EXIT_CODE=$((EXIT_CODE + 1))
  printf "%s [+%s] \033[91mipv6 address\033[m not found\n" "$(show_date)" "$EXIT_CODE" >>"$LOG_FILE"
}

# Check if wget or curl binaries are available
COMMAND_BIN=$({ command -v wget && printf " -qO -";} || { command -v curl && printf " -fsS";})
[ -z "$COMMAND_BIN" ] && {
  EXIT_CODE=$((EXIT_CODE + 1))
  printf "%s [+%s] binaries \033[91mwget\033[m and \033[91mcurl\033[m not found\n" "$(show_date)" "$EXIT_CODE" >>"$LOG_FILE"
}

# Check if arguments are correct
[ "$#" -eq 0 ] && {
  EXIT_CODE=$((EXIT_CODE + 1))
  printf "%s [+%s] no \033[91margument\033[m passed\n" "$(show_date)" "$EXIT_CODE" >>"$LOG_FILE"
}
for FILE in "$@"; do
  [ ! -f "$FILE" ] && {
    EXIT_CODE=$((EXIT_CODE + 1))
    printf "%s [+%s] file \033[91m%s\033[m not found\n" "$(show_date)" "$EXIT_CODE" "$FILE" >>"$LOG_FILE"
  }
done

# Exit if there are errors
[ -n "$EXIT_CODE" ] && {
  printf "%s \033[91m%s\033[m error(s) found\n" "$(show_date)" "$EXIT_CODE" >>"$LOG_FILE"
  printf "\033[30;101mExiting script...\033[m\n" >>"$LOG_FILE"
  exit "$EXIT_CODE"
}

# Check if updates it's needed
if [ "$IPV6" = "$LAST_IPV6" ]; then
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
    # Skip update if it's not necessary
    [ "$DOMAIN_STATUS" = "updated" ] && [ "$IPV6_STATUS" = "unchanged" ] && continue
    TOKEN=$(printf "%s" "$LINE" | cut -d '*' -f 2)
    EXIT_DATA=$(
      $COMMAND_BIN 'https://ipv6.dynv6.com/api/update?zone='"${DOMAIN}"'&ipv6='"${IPV6}"'&token='"${TOKEN}"
      printf "*%s" "$?"
    )
    # SERVER_MESSAGE=$(printf "%s" "$EXIT_DATA" | cut -d '*' -f 1);
    COMMAND_BIN_EXIT_CODE=$(printf "%s" "$EXIT_DATA" | cut -d '*' -f 2)
    if [ "$COMMAND_BIN_EXIT_CODE" -eq 0 ]; then
      [ "$DOMAIN_STATUS" = "not_updated" ] && {
        sed -i '/^not_updated=/ s/'"$REGEX_DOMAIN "'//' "$DATA_FILE"
        sed -i 's/^updated=/updated='"$DOMAIN "'/' "$DATA_FILE"
      }
      [ -z "$DOMAIN_STATUS" ] && sed -i 's/^updated=/updated='"$DOMAIN "'/' "$DATA_FILE"
      printf "%s \033[92m%s\033[m updated\n" "$(show_date)" "$DOMAIN" >>"$LOG_FILE"
    else
      EXIT_CODE=$((EXIT_CODE + 1))
      [ "$DOMAIN_STATUS" = "updated" ] && {
        sed -i '/^updated=/ s/'"$REGEX_DOMAIN "'//' "$DATA_FILE"
        sed -i 's/^not_updated=/not_updated='"$DOMAIN "'/' "$DATA_FILE"
      }
      [ -z "$DOMAIN_STATUS" ] && sed -i 's/^not_updated=/not_updated='"$DOMAIN "'/' "$DATA_FILE"
      printf "%s [+%s] \033[91m%s\033[m not updated, code %s\n" "$(show_date)" "$EXIT_CODE" "$DOMAIN" "$COMMAND_BIN_EXIT_CODE" >>"$LOG_FILE"
    fi
  done
done
