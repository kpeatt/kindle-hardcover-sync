#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
LIPC_WAIT=/usr/bin/lipc-wait-event
EIPS=/usr/sbin/eips
PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML_DIR=/mnt/us/extensions/kindle-hardcover-sync/html
MSGLOG=/var/log/messages

$EIPS -m "Test running in 4s..."
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

  rm -f /tmp/hc_dialog_reply /tmp/hc_lipc_reply
  $LIPC_WAIT -s 0 com.lab126.pillow debugInfo > /tmp/hc_lipc_reply 2>&1 &
  WAIT_PID=$!

  MSG_START_BYTES=$(wc -c < "$MSGLOG" 2>/dev/null || echo 0)

  echo "### Firing hc_dialog ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Reply Test","message":"Tap A or B.","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"}]}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  $EIPS -m "Dialog fired. Tap A or B."

  FOUND=""
  i=0
  while [ $i -lt 20 ]; do
    if [ -f /tmp/hc_dialog_reply ]; then FOUND="sendEvent-file=$(cat /tmp/hc_dialog_reply)"; break; fi
    if [ -s /tmp/hc_lipc_reply ]; then FOUND="debugInfo-lipc=$(cat /tmp/hc_lipc_reply)"; break; fi
    HC_LINE=$(tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null | grep -o "HC_REPLY:[a-z_]*" | head -n 1)
    [ -n "$HC_LINE" ] && { FOUND="logDbg-messages=$HC_LINE"; break; }
    sleep 1
    i=$((i + 1))
    # Stream progress so the log is readable even if user unplugs early
    echo "poll $i/20 ..." >> "$LOG"
  done
  kill $WAIT_PID 2>/dev/null
  wait 2>/dev/null

  if [ -n "$FOUND" ]; then
    echo "REPLY RECEIVED: $FOUND" >> "$LOG"
  else
    echo "No reply via any channel (timeout 20s)" >> "$LOG"
  fi

  echo "" >> "$LOG"
  echo "### NEW /var/log/messages lines since test start ###" >> "$LOG"
  tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null | grep -iE "HC_|pillow|webkit|dialog|nativeBridge" | head -n 80 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
