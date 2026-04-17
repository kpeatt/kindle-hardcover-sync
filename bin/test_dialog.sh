#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
EIPS=/usr/sbin/eips
PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML_DIR=/mnt/us/extensions/kindle-hardcover-sync/html
MSGLOG=/var/log/messages

$EIPS -m "Test: tap button B (middle)"
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

  MSG_START_BYTES=$(wc -c < "$MSGLOG" 2>/dev/null || echo 0)

  echo "### Firing hc_dialog with 3 buttons (A B C) — tap B (middle) ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Button Index Test","message":"Tap B (the middle button).","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"},{"label":"C","id":"c"}]}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"

  BUTTON_IDX=""
  i=0
  while [ $i -lt 20 ]; do
    BUTTON_IDX=$(tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null | grep -o "button-press:target=hc_dialog,button=[0-9]*" | head -n 1 | sed 's/.*button=//')
    [ -n "$BUTTON_IDX" ] && break
    sleep 1
    i=$((i + 1))
    echo "poll $i/20 ..." >> "$LOG"
  done

  if [ -n "$BUTTON_IDX" ]; then
    echo "BUTTON INDEX DETECTED: $BUTTON_IDX" >> "$LOG"
  else
    echo "No button-press log line found within 20s" >> "$LOG"
  fi

  echo "" >> "$LOG"
  echo "### relevant /var/log/messages lines ###" >> "$LOG"
  tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null | grep -iE "button|pillow.*hc_dialog|HC_" | head -n 30 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
