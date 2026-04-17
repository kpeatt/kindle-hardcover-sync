#!/bin/sh

echo "test_dialog.sh started at $(date)" > /tmp/hc_test_started 2>&1

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
LIPC_GET=/usr/bin/lipc-get-prop
LIPC_PROBE=/usr/bin/lipc-probe
EIPS=/usr/sbin/eips

{
  echo "====================================="
  echo "Test started: $(date)"
  echo "PWD: $(pwd)"
  echo "DIR: $DIR"
  echo "HTML: $DIR/html/dialog.html ($([ -f "$DIR/html/dialog.html" ] && echo present || echo MISSING))"
  echo ""
  echo "--- probe com.lab126.pillow ---"
  $LIPC_PROBE -- com.lab126.pillow 2>&1 | head -n 80
  echo "--- end probe ---"
} >> "$LOG" 2>&1

$EIPS -m "Test firing in 4s..."
# Detach from KUAL so the dialog fires AFTER KUAL finishes closing.
(
  sleep 4

  rm -f /tmp/hc_dialog_reply

  PARAMS='{"name":"../../../../mnt/us/extensions/kindle-hardcover-sync/html/dialog","clientParams":{"title":"Test Dialog","message":"If you see this, Pillow customDialog works. Tap a button.","buttons":[{"label":"A","id":"answer_a"},{"label":"B","id":"answer_b"}]}}'

  {
    echo ""
    echo "--- firing customDialog at $(date) ---"
    echo "PARAMS: $PARAMS"
  } >> "$LOG"

  $LIPC_SET com.lab126.pillow customDialog "$PARAMS" >> "$LOG" 2>&1
  echo "customDialog exit: $?" >> "$LOG"

  # Also dump what pillow currently reports as the dialog state
  echo "customDialog read-back: $($LIPC_GET com.lab126.pillow customDialog 2>&1)" >> "$LOG"

  # Wait up to 30s for reply, then capture tail of /var/log/messages for anything pillow-related
  i=0
  while [ $i -lt 30 ]; do
    if [ -f /tmp/hc_dialog_reply ]; then
      echo "Got reply: $(cat /tmp/hc_dialog_reply)" >> "$LOG"
      rm -f /tmp/hc_dialog_reply
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  if [ $i -ge 30 ]; then
    echo "Timed out waiting for reply" >> "$LOG"
  fi

  {
    echo ""
    echo "--- tail /var/log/messages (pillow/webkit/html) ---"
    grep -iE "pillow|webkit|customDialog|html/dialog" /var/log/messages 2>/dev/null | tail -n 40
    echo "--- end tail ---"
  } >> "$LOG"

  $EIPS -m "Test complete. See test_dialog.log"
) &

# Return quickly so KUAL closes cleanly.
exit 0
