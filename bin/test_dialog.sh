#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
EIPS=/usr/sbin/eips
MSGLOG=/var/log/messages

SYMLINK=/usr/share/webkit-1.0/pillow/hc_dialog
SYMLINK_TARGET=/mnt/us/extensions/kindle-hardcover-sync/html

capture_msg_tail() {
  echo "--- $1 ---" >> "$LOG"
  grep -iE "pillow|webkit|custom|html" "$MSGLOG" 2>/dev/null | tail -n 20 >> "$LOG"
  echo "--- end ---" >> "$LOG"
}

$EIPS -m "Test running in 4s..."
(
  sleep 4

  {
    echo "====================================="
    echo "Test started: $(date)"
    echo "HTML source: $SYMLINK_TARGET/dialog.html ($([ -f "$SYMLINK_TARGET/dialog.html" ] && echo present || echo MISSING))"
  } >> "$LOG"

  # Step 1: mount rootfs rw
  echo "" >> "$LOG"
  echo "--- mntroot rw ---" >> "$LOG"
  mntroot rw >> "$LOG" 2>&1
  echo "mntroot rw exit: $?" >> "$LOG"

  # Step 2: install/refresh symlink
  echo "" >> "$LOG"
  echo "--- symlink setup ---" >> "$LOG"
  echo "before: $(ls -la "$SYMLINK" 2>&1)" >> "$LOG"
  rm -rf "$SYMLINK" 2>> "$LOG"
  ln -sf "$SYMLINK_TARGET" "$SYMLINK" >> "$LOG" 2>&1
  echo "ln exit: $?" >> "$LOG"
  echo "after: $(ls -la "$SYMLINK" 2>&1)" >> "$LOG"
  echo "resolves to dialog.html: $([ -f "$SYMLINK/dialog.html" ] && echo yes || echo no)" >> "$LOG"

  # Step 3: mntroot ro
  echo "" >> "$LOG"
  echo "--- mntroot ro ---" >> "$LOG"
  mntroot ro >> "$LOG" 2>&1
  echo "mntroot ro exit: $?" >> "$LOG"

  capture_msg_tail "before customDialog"

  # Step 4: fire customDialog using non-traversal path via symlink
  PARAMS='{"name":"hc_dialog/dialog","clientParams":{"title":"Hardcover Sync","message":"If you see this, the symlink route works! Tap a button.","buttons":[{"label":"A","id":"answer_a"},{"label":"B","id":"answer_b"}]}}'
  {
    echo ""
    echo "--- firing customDialog via symlink at $(date) ---"
    echo "PARAMS: $PARAMS"
  } >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog "$PARAMS" >> "$LOG" 2>&1
  echo "customDialog exit: $?" >> "$LOG"

  sleep 3
  capture_msg_tail "after customDialog"

  # Wait for reply
  rm -f /tmp/hc_dialog_reply
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
  [ $i -ge 30 ] && echo "No reply received (timeout)" >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
