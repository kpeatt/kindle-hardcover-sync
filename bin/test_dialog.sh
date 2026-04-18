#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
EIPS=/usr/sbin/eips
PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML_DIR=/mnt/us/extensions/kindle-hardcover-sync/html

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

  echo "### Firing hc_dialog — tap A ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Log Channel Test","message":"Tap A.","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"}]}}' \
    >> "$LOG" 2>&1

  # Give user time to tap and the shout() calls to hit whatever log file they go to
  sleep 12

  echo "" >> "$LOG"
  echo "### scan all log-like files for HCSYNC_ tokens ###" >> "$LOG"
  # Find every readable file under common log dirs and grep for our token
  for d in /var/log /var/local/log /tmp /mnt/us/system/log; do
    [ -d "$d" ] || continue
    find "$d" -type f 2>/dev/null | while read f; do
      if grep -l "HCSYNC_" "$f" 2>/dev/null >/dev/null; then
        echo ">>> $f <<<" >> "$LOG"
        grep "HCSYNC_" "$f" 2>/dev/null | tail -n 20 >> "$LOG"
      fi
    done
  done

  echo "" >> "$LOG"
  echo "### all /var/log/*.* listing ###" >> "$LOG"
  ls -la /var/log 2>/dev/null | head -n 40 >> "$LOG"
  echo "### all /var/local/log/*.* listing ###" >> "$LOG"
  ls -la /var/local/log 2>/dev/null | head -n 40 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
