#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
EIPS=/usr/sbin/eips
MSGLOG=/var/log/messages

PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML=/mnt/us/extensions/kindle-hardcover-sync/html/dialog.html

capture_msg_tail() {
  echo "--- msg tail: $1 ---" >> "$LOG"
  tail -n 50 "$MSGLOG" 2>/dev/null | grep -iE "pillow|webkit|custom|html|dialog|window" >> "$LOG"
  echo "--- end ---" >> "$LOG"
}

$EIPS -m "Test running in 4s..."
(
  sleep 4

  {
    echo "====================================="
    echo "Test started: $(date)"
  } >> "$LOG"

  # Install symlinks: top-level file AND directory-based
  mntroot rw >> "$LOG" 2>&1
  rm -f "$PILLOW_DIR/hc_dialog.html" "$PILLOW_DIR/hc_dialog"
  ln -sf "$SRC_HTML" "$PILLOW_DIR/hc_dialog.html"
  ln -sf "$(dirname "$SRC_HTML")" "$PILLOW_DIR/hc_dialog"
  echo "symlinks after setup:" >> "$LOG"
  ls -la "$PILLOW_DIR/hc_dialog" "$PILLOW_DIR/hc_dialog.html" >> "$LOG" 2>&1
  mntroot ro >> "$LOG" 2>&1

  # Also crank pillow log level for visibility
  $LIPC_SET com.lab126.pillow logLevel debug >> "$LOG" 2>&1
  echo "logLevel set exit: $?" >> "$LOG"

  capture_msg_tail "before tests"

  # Attempt 1: customDialog, top-level name (no subdir)
  echo "" >> "$LOG"
  echo "### A1: customDialog name=hc_dialog (top-level file) ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Top-Level","message":"A1","buttons":[{"label":"A","id":"a"}]}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 4
  capture_msg_tail "after A1"

  # Attempt 2: customDialog, subdir path
  echo "" >> "$LOG"
  echo "### A2: customDialog name=hc_dialog/dialog (subdir) ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog/dialog","clientParams":{"title":"Subdir","message":"A2","buttons":[{"label":"A","id":"a"}]}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 4
  capture_msg_tail "after A2"

  # Attempt 3: interrogatePillow injection — ask an existing pillow to show our dialog
  echo "" >> "$LOG"
  echo "### A3: interrogatePillow (inject showDialog into default_status_bar) ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow interrogatePillow \
    '{"pillowId":"default_status_bar","function":"if(typeof nativeBridge!==\"undefined\"&&nativeBridge.showDialog){nativeBridge.showDialog(\"hc_dialog\",{title:\"Inject\",msg:\"A3\",buttons:[{label:\"A\",id:\"a\"}]});}"}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 4
  capture_msg_tail "after A3"

  # Attempt 4: what pillows currently exist — query interrogatePillowHash
  echo "" >> "$LOG"
  echo "### A4: interrogatePillowHash (list pillows) ###" >> "$LOG"
  /usr/bin/lipc-get-prop com.lab126.pillow interrogatePillowHash >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"

  # Attempt 5: list actual pillow dir contents to confirm file placement
  echo "" >> "$LOG"
  echo "### A5: /usr/share/webkit-1.0/pillow/ listing ###" >> "$LOG"
  ls -la "$PILLOW_DIR" 2>&1 | head -n 40 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
