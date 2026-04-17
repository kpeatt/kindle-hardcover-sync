#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
LIPC_GET=/usr/bin/lipc-get-prop
LIPC_PROBE=/usr/bin/lipc-probe
LIPC_WAIT=/usr/bin/lipc-wait-event
EIPS=/usr/sbin/eips
PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML_DIR=/mnt/us/extensions/kindle-hardcover-sync/html

$EIPS -m "Test running in 4s..."
(
  sleep 4

  {
    echo "====================================="
    echo "Test started: $(date)"
  } >> "$LOG"

  # Symlinks
  mntroot rw >> "$LOG" 2>&1
  rm -f "$PILLOW_DIR/hc_dialog.html"
  ln -sf "$SRC_HTML_DIR/dialog.html" "$PILLOW_DIR/hc_dialog.html"
  mntroot ro >> "$LOG" 2>&1

  # Probe what exists to receive a reply
  echo "" >> "$LOG"
  echo "### probe com.lab126.system ###" >> "$LOG"
  $LIPC_PROBE -- com.lab126.system 2>&1 | grep -iE "sendEvent|event" | head -n 20 >> "$LOG"
  echo "### probe com.lab126.pillow ###" >> "$LOG"
  $LIPC_PROBE -- com.lab126.pillow 2>&1 | head -n 30 >> "$LOG"

  # Start a background waiter on com.lab126.pillow property change events.
  # lipc-wait-event returns on matching property set.
  rm -f /tmp/hc_dialog_reply /tmp/hc_lipc_reply
  $LIPC_WAIT -s 0 com.lab126.pillow hcReply > /tmp/hc_lipc_reply 2>&1 &
  WAIT_PID=$!
  echo "lipc-wait-event pid: $WAIT_PID" >> "$LOG"

  # Fire the dialog with replyLipcSrc/replyProp so Amazon-pattern is exercised too
  echo "" >> "$LOG"
  echo "### Firing hc_dialog ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Reply Test","message":"Tap A or B. Multiple reply channels will be tried.","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"}],"replyLipcSrc":"com.lab126.pillow","replyProp":"hcReply"}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"

  # Poll for any reply channel to deliver
  i=0
  FOUND=""
  while [ $i -lt 60 ]; do
    if [ -f /tmp/hc_dialog_reply ]; then
      FOUND="file"
      echo "FILE reply: $(cat /tmp/hc_dialog_reply)" >> "$LOG"
      break
    fi
    if [ -s /tmp/hc_lipc_reply ]; then
      FOUND="lipc"
      echo "LIPC reply: $(cat /tmp/hc_lipc_reply)" >> "$LOG"
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  # Clean up waiter
  kill $WAIT_PID 2>/dev/null
  wait 2>/dev/null

  [ -z "$FOUND" ] && echo "No reply received via any channel (timeout)" >> "$LOG"

  # Also read back the pillow prop in case the set worked but events didn't fire
  echo "" >> "$LOG"
  echo "hcReply prop read-back: $($LIPC_GET com.lab126.pillow hcReply 2>&1)" >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
