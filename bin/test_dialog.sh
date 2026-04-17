#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
EIPS=/usr/sbin/eips
MSGLOG=/var/log/messages
PILLOW_DIR=/usr/share/webkit-1.0/pillow

capture_msg_tail() {
  echo "--- msg tail: $1 ---" >> "$LOG"
  tail -n 30 "$MSGLOG" 2>/dev/null >> "$LOG"
  echo "--- end ---" >> "$LOG"
}

$EIPS -m "Test running in 4s..."
(
  sleep 4

  {
    echo "====================================="
    echo "Test started: $(date)"
  } >> "$LOG"

  capture_msg_tail "before tests"

  # Attempt 1: trigger Amazon's OWN sample_custom_dialog — if this doesn't render,
  # customDialog is dead on this firmware regardless of our HTML.
  echo "" >> "$LOG"
  echo "### A1: customDialog name=sample_custom_dialog (Amazon's own sample) ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"sample_custom_dialog","clientParams":{}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 5
  capture_msg_tail "after A1"

  # Attempt 2: trigger the light_dialog (another stock dialog)
  echo "" >> "$LOG"
  echo "### A2: customDialog name=light_dialog ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"light_dialog","clientParams":{}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 5
  capture_msg_tail "after A2"

  # Attempt 3: trigger simple_alert (likely corresponds to pillowAlert)
  echo "" >> "$LOG"
  echo "### A3: customDialog name=simple_alert ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"simple_alert","clientParams":{"title":"T","message":"M"}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 5
  capture_msg_tail "after A3"

  # Dump reference HTML contents so we can see how Amazon does it
  echo "" >> "$LOG"
  echo "### sample_custom_dialog.html ###" >> "$LOG"
  cat "$PILLOW_DIR/sample_custom_dialog.html" >> "$LOG" 2>&1

  echo "" >> "$LOG"
  echo "### simple_alert.html ###" >> "$LOG"
  cat "$PILLOW_DIR/simple_alert.html" >> "$LOG" 2>&1

  echo "" >> "$LOG"
  echo "### light_dialog.html ###" >> "$LOG"
  cat "$PILLOW_DIR/light_dialog.html" >> "$LOG" 2>&1

  # Also dump javascripts/ listing and sample JS if present
  echo "" >> "$LOG"
  echo "### javascripts/ listing ###" >> "$LOG"
  ls -la "$PILLOW_DIR/javascripts/" 2>&1 | head -n 50 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
