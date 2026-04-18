#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
LIPC_GET=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML_DIR=/mnt/us/extensions/kindle-hardcover-sync/html
MSGLOG=/var/log/messages

$EIPS -m "Tap A when dialog opens"
(
  sleep 4

  {
    echo "====================================="
    echo "Test started: $(date)"
  } >> "$LOG"

  mntroot rw >> "$LOG" 2>&1
  rm -f "$PILLOW_DIR/hc_dialog.html"
  ln -sf "$SRC_HTML_DIR/dialog.html" "$PILLOW_DIR/hc_dialog.html"
  mntroot ro >> "$LOG" 2>&1

  echo "### interrogatePillowHash BEFORE firing ###" >> "$LOG"
  $LIPC_GET -h com.lab126.pillow interrogatePillowHash >> "$LOG" 2>&1
  echo "---" >> "$LOG"

  echo "### Firing hc_dialog — tap A ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Interrogate Test","message":"Tap A.","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"}]}}' \
    >> "$LOG" 2>&1

  # Wait briefly for dialog to initialize
  sleep 3

  # Pre-interrogate: test if we can read ANYTHING from the pillow
  echo "" >> "$LOG"
  echo "### interrogatePillow: window.location.href ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow interrogatePillow \
    '{"pillowId":"hc-dialog","function":"return window.location.href;"}' >> "$LOG" 2>&1
  sleep 1
  echo "hash readback:" >> "$LOG"
  $LIPC_GET -h com.lab126.pillow interrogatePillowHash >> "$LOG" 2>&1
  echo "---" >> "$LOG"

  echo "" >> "$LOG"
  echo "### interrogatePillow: simple literal ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow interrogatePillow \
    '{"pillowId":"hc-dialog","function":"return 42;"}' >> "$LOG" 2>&1
  sleep 1
  echo "hash readback:" >> "$LOG"
  $LIPC_GET -h com.lab126.pillow interrogatePillowHash >> "$LOG" 2>&1
  echo "---" >> "$LOG"

  echo "" >> "$LOG"
  echo "### Poll for hcReply via interrogate ###" >> "$LOG"

  REPLY=""
  i=0
  while [ $i -lt 25 ]; do
    $LIPC_SET com.lab126.pillow interrogatePillow \
      '{"pillowId":"hc-dialog","function":"return (window.hcReply || \"\");"}' >/dev/null 2>&1
    sleep 1
    H=$($LIPC_GET -h com.lab126.pillow interrogatePillowHash 2>/dev/null)
    echo "poll $i: $H" >> "$LOG"
    # Look for a non-empty reply
    if echo "$H" | grep -qE '(a|b|c|yes|no)"[^"]*$'; then
      REPLY="$H"
      break
    fi
    i=$((i + 1))
  done

  echo "" >> "$LOG"
  echo "FINAL REPLY: ${REPLY:-NONE}" >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
