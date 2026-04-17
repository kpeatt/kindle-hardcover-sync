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

  # Start a lipc-wait-event on debugInfo in background
  rm -f /tmp/hc_dialog_reply /tmp/hc_lipc_reply
  $LIPC_WAIT -s 0 com.lab126.pillow debugInfo > /tmp/hc_lipc_reply 2>&1 &
  WAIT_PID=$!

  # Record current messages position so we only grep for new lines
  MSG_START_BYTES=$(wc -c < "$MSGLOG" 2>/dev/null || echo 0)

  echo "" >> "$LOG"
  echo "### Firing hc_dialog ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Reply Test","message":"Tap A or B.","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"}]}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"

  # Poll for ANY reply channel
  FOUND=""
  i=0
  while [ $i -lt 60 ]; do
    if [ -f /tmp/hc_dialog_reply ]; then
      FOUND="sendEvent-file"
      echo "$FOUND reply: $(cat /tmp/hc_dialog_reply)" >> "$LOG"
      break
    fi
    if [ -s /tmp/hc_lipc_reply ]; then
      FOUND="debugInfo-lipc"
      echo "$FOUND reply: $(cat /tmp/hc_lipc_reply)" >> "$LOG"
      break
    fi
    # Check /var/log/messages for HC_REPLY line from logDbg
    HC_LINE=$(tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null | grep -o "HC_REPLY:[a-z_]*" | head -n 1)
    if [ -n "$HC_LINE" ]; then
      FOUND="logDbg-messages"
      echo "$FOUND reply: $HC_LINE" >> "$LOG"
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  kill $WAIT_PID 2>/dev/null
  wait 2>/dev/null

  [ -z "$FOUND" ] && echo "No reply via any channel (timeout 60s)" >> "$LOG"

  # Always dump new messages lines so we can see logDbg output even if not parsed
  echo "" >> "$LOG"
  echo "### NEW /var/log/messages lines since test start ###" >> "$LOG"
  tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null | grep -iE "HC_|pillow|webkit|dialog" | head -n 60 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
