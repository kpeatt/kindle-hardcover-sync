#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"

{
  echo "====================================="
  echo "Test started: $(date)"
  echo "DIR: $DIR"
  echo "HTML exists: $([ -f "$DIR/html/dialog.html" ] && echo yes || echo no)"
  echo "lipc-set-prop: $(command -v lipc-set-prop || echo MISSING)"
  echo "lipc-get-prop: $(command -v lipc-get-prop || echo MISSING)"
} >> "$LOG"

eips -m "Firing test dialog..."

rm -f /tmp/hc_dialog_reply

PARAMS='{"name":"../../../../mnt/us/extensions/kindle-hardcover-sync/html/dialog","clientParams":{"title":"Test Dialog","message":"If you see this, Pillow customDialog works. Tap a button to test the reply channel.","buttons":[{"label":"A","id":"answer_a"},{"label":"B","id":"answer_b"}]}}'

echo "Calling lipc-set-prop with:" >> "$LOG"
echo "$PARAMS" >> "$LOG"

lipc-set-prop com.lab126.pillow customDialog "$PARAMS" 2>> "$LOG"
RC=$?
echo "lipc-set-prop exit: $RC" >> "$LOG"

# Poll up to 60s for reply
i=0
while [ $i -lt 60 ]; do
  if [ -f /tmp/hc_dialog_reply ]; then
    REPLY=$(cat /tmp/hc_dialog_reply)
    echo "Got reply: $REPLY" >> "$LOG"
    eips -m "Reply: $REPLY"
    rm -f /tmp/hc_dialog_reply
    exit 0
  fi
  sleep 1
  i=$((i + 1))
done

echo "Timed out waiting for reply" >> "$LOG"
eips -m "TIMEOUT - no reply. Check $LOG"
