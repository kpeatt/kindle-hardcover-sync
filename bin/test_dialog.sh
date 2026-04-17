#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
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

  mntroot rw >> "$LOG" 2>&1
  rm -f "$PILLOW_DIR/hc_hello.html" "$PILLOW_DIR/hc_dialog.html"
  ln -sf "$SRC_HTML_DIR/hello.html" "$PILLOW_DIR/hc_hello.html"
  ln -sf "$SRC_HTML_DIR/dialog.html" "$PILLOW_DIR/hc_dialog.html"
  ls -la "$PILLOW_DIR/hc_hello.html" "$PILLOW_DIR/hc_dialog.html" >> "$LOG" 2>&1
  mntroot ro >> "$LOG" 2>&1

  # Test 1: hello.html — should show HELLO KYLE, auto-dismiss in 15s
  echo "" >> "$LOG"
  echo "### T1: hc_hello (should render and self-dismiss) ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog '{"name":"hc_hello","clientParams":{}}' >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"

  # Wait for hello to dismiss itself
  sleep 18

  # Test 2: dialog.html with real clientParams — should show buttons, capture reply
  echo "" >> "$LOG"
  echo "### T2: hc_dialog (with clientParams, wait for tap) ###" >> "$LOG"
  rm -f /tmp/hc_dialog_reply
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Dialog Test","message":"Tap A or B to test the reply channel.","buttons":[{"label":"A","id":"answer_a"},{"label":"B","id":"answer_b"}]}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"

  # Poll for reply
  i=0
  while [ $i -lt 30 ]; do
    if [ -f /tmp/hc_dialog_reply ]; then
      echo "Reply: $(cat /tmp/hc_dialog_reply)" >> "$LOG"
      rm -f /tmp/hc_dialog_reply
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  [ $i -ge 30 ] && echo "Dialog reply timed out (no tap or reply channel broken)" >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
