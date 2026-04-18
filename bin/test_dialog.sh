#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
LIPC_WAIT=/usr/bin/lipc-wait-event
LIPC_PROBE=/usr/bin/lipc-probe
EIPS=/usr/sbin/eips
PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML_DIR=/mnt/us/extensions/kindle-hardcover-sync/html
MSGLOG=/var/log/messages

$EIPS -m "Tap A when dialog opens"
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

  # Probe the sources we're about to try
  for src in com.lab126.keyboard com.lab126.browser com.lab126.winmgr; do
    echo "" >> "$LOG"
    echo "### probe $src ###" >> "$LOG"
    $LIPC_PROBE -- $src 2>&1 | head -n 15 >> "$LOG"
  done

  # Start subscribers on every candidate
  rm -f /tmp/hc_kb_open /tmp/hc_kb_close /tmp/hc_browser /tmp/hc_winmgr
  $LIPC_WAIT -s 0 com.lab126.keyboard open   > /tmp/hc_kb_open   2>&1 &
  KB_O=$!
  $LIPC_WAIT -s 0 com.lab126.keyboard close  > /tmp/hc_kb_close  2>&1 &
  KB_C=$!
  $LIPC_WAIT -s 0 com.lab126.browser data    > /tmp/hc_browser   2>&1 &
  BR=$!
  $LIPC_WAIT -s 0 com.lab126.winmgr  data    > /tmp/hc_winmgr    2>&1 &
  WM=$!

  MSG_START_BYTES=$(wc -c < "$MSGLOG" 2>/dev/null || echo 0)

  echo "" >> "$LOG"
  echo "### Firing hc_dialog — tap A ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Channel Test","message":"Tap A.","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"}]}}' \
    >> "$LOG" 2>&1

  # Wait for tap + writes
  sleep 12

  # Kill subscribers
  for p in $KB_O $KB_C $BR $WM; do kill $p 2>/dev/null; done
  wait 2>/dev/null

  echo "" >> "$LOG"
  for f in /tmp/hc_kb_open /tmp/hc_kb_close /tmp/hc_browser /tmp/hc_winmgr; do
    echo "### $f ###" >> "$LOG"
    cat "$f" >> "$LOG" 2>&1
    echo "" >> "$LOG"
  done

  echo "### msg log lines with hc: or hc_dialog or lipc-set-string ###" >> "$LOG"
  tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null \
    | grep -iE "hc:|hc_dialog|lipc-set-string|permissionDenied|lipcErr" | head -n 40 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
