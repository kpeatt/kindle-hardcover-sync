#!/bin/sh

# Write a marker IMMEDIATELY so we can tell the script started at all.
echo "test_dialog.sh started at $(date)" > /tmp/hc_test_started 2>&1

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"

# Also write the startup marker to the extension log, before any other logic.
{
  echo "====================================="
  echo "Test started: $(date)"
  echo "PWD: $(pwd)"
  echo "0: $0"
  echo "DIR: $DIR"
  echo "PATH: $PATH"
  echo "HTML exists: $([ -f "$DIR/html/dialog.html" ] && echo yes || echo no)"
  echo "lipc-set-prop: $(command -v lipc-set-prop 2>/dev/null || echo MISSING)"
  echo "lipc-get-prop: $(command -v lipc-get-prop 2>/dev/null || echo MISSING)"
  echo "eips: $(command -v eips 2>/dev/null || echo MISSING)"
} >> "$LOG" 2>&1

# Try eips via full path in case PATH is stripped in KUAL context
if command -v eips >/dev/null 2>&1; then
  eips -m "Firing test dialog..."
elif [ -x /usr/bin/eips ]; then
  /usr/bin/eips -m "Firing test dialog..."
fi

rm -f /tmp/hc_dialog_reply

PARAMS='{"name":"../../../../mnt/us/extensions/kindle-hardcover-sync/html/dialog","clientParams":{"title":"Test Dialog","message":"If you see this, Pillow customDialog works. Tap a button.","buttons":[{"label":"A","id":"answer_a"},{"label":"B","id":"answer_b"}]}}'

echo "Calling lipc-set-prop with:" >> "$LOG"
echo "$PARAMS" >> "$LOG"

if command -v lipc-set-prop >/dev/null 2>&1; then
  lipc-set-prop com.lab126.pillow customDialog "$PARAMS" >> "$LOG" 2>&1
  RC=$?
elif [ -x /usr/bin/lipc-set-prop ]; then
  /usr/bin/lipc-set-prop com.lab126.pillow customDialog "$PARAMS" >> "$LOG" 2>&1
  RC=$?
else
  echo "lipc-set-prop not found" >> "$LOG"
  RC=127
fi
echo "lipc-set-prop exit: $RC" >> "$LOG"

# Poll up to 60s for reply
i=0
while [ $i -lt 60 ]; do
  if [ -f /tmp/hc_dialog_reply ]; then
    REPLY=$(cat /tmp/hc_dialog_reply)
    echo "Got reply: $REPLY" >> "$LOG"
    if command -v eips >/dev/null 2>&1; then
      eips -m "Reply: $REPLY"
    fi
    rm -f /tmp/hc_dialog_reply
    exit 0
  fi
  sleep 1
  i=$((i + 1))
done

echo "Timed out waiting for reply" >> "$LOG"
if command -v eips >/dev/null 2>&1; then
  eips -m "TIMEOUT - check test_dialog.log"
fi
