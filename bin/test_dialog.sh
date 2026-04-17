#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
LIPC_GET=/usr/bin/lipc-get-prop
LIPC_PROBE=/usr/bin/lipc-probe
EIPS=/usr/sbin/eips
MSGLOG=/var/log/messages

capture_msg_tail() {
  echo "--- $1: /var/log/messages tail ---" >> "$LOG"
  grep -iE "pillow|webkit|custom|html" "$MSGLOG" 2>/dev/null | tail -n 20 >> "$LOG"
  echo "--- end ---" >> "$LOG"
}

try_prop() {
  desc="$1"; prop="$2"; value="$3"
  {
    echo ""
    echo "### $desc ###"
    echo "prop: $prop"
    echo "value: $value"
    echo "time: $(date)"
  } >> "$LOG"
  $LIPC_SET com.lab126.pillow "$prop" "$value" >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 2
  capture_msg_tail "after $prop"
}

$EIPS -m "Test running in 4s..."
(
  sleep 4

  {
    echo "====================================="
    echo "Test started: $(date)"
    echo "HTML: $DIR/html/dialog.html ($([ -f "$DIR/html/dialog.html" ] && echo present || echo MISSING))"
    echo ""
    echo "--- probe com.lab126.pillow ---"
    $LIPC_PROBE -- com.lab126.pillow 2>&1 | head -n 80
    echo "--- end probe ---"
  } >> "$LOG" 2>&1

  capture_msg_tail "before tests"

  # Test 1: dismissChrome — simple "can we affect Pillow at all" check
  try_prop "dismissChrome (hide status bar for 2s)" dismissChrome 1

  # Test 2: pillowAlert — simplest Pillow alert mechanism
  try_prop "pillowAlert (simple string)" pillowAlert "Hardcover test alert"

  # Test 3: pillowAlert with JSON
  try_prop "pillowAlert (JSON)" pillowAlert '{"title":"Hardcover","msg":"alert body","timeout":5}'

  # Test 4: customDialog, 4-dot traversal (current)
  try_prop "customDialog 4-dot" customDialog '{"name":"../../../../mnt/us/extensions/kindle-hardcover-sync/html/dialog","clientParams":{"title":"T","message":"dots=4","buttons":[{"label":"OK","id":"ok"}]}}'

  # Test 5: customDialog, 6-dot traversal (WinterBreak style)
  try_prop "customDialog 6-dot" customDialog '{"name":"../../../../../../mnt/us/extensions/kindle-hardcover-sync/html/dialog","clientParams":{"title":"T","message":"dots=6","buttons":[{"label":"OK","id":"ok"}]}}'

  # Test 6: customDialog with absolute-style path
  try_prop "customDialog absolute" customDialog '{"name":"/mnt/us/extensions/kindle-hardcover-sync/html/dialog","clientParams":{"title":"T","message":"abs","buttons":[{"label":"OK","id":"ok"}]}}'

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"

  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
