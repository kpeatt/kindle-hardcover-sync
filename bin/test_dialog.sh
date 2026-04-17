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

  # Symlink both our dialog AND the minimal hello.html
  mntroot rw >> "$LOG" 2>&1
  rm -f "$PILLOW_DIR/hc_hello.html" "$PILLOW_DIR/hc_dialog.html"
  ln -sf "$SRC_HTML_DIR/hello.html" "$PILLOW_DIR/hc_hello.html"
  ln -sf "$SRC_HTML_DIR/dialog.html" "$PILLOW_DIR/hc_dialog.html"
  echo "symlinks:" >> "$LOG"
  ls -la "$PILLOW_DIR/hc_hello.html" "$PILLOW_DIR/hc_dialog.html" >> "$LOG" 2>&1
  mntroot ro >> "$LOG" 2>&1

  # A1: trigger the dead-simple hello.html
  echo "" >> "$LOG"
  echo "### A1: customDialog name=hc_hello (minimal HTML with visible text) ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_hello","clientParams":{}}' >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"
  sleep 6

  # Dump the relevant Amazon JS files so we can copy their pattern
  echo "" >> "$LOG"
  echo "### javascripts/pillow.js (first 200 lines) ###" >> "$LOG"
  head -n 200 "$PILLOW_DIR/javascripts/pillow.js" >> "$LOG" 2>&1

  echo "" >> "$LOG"
  echo "### javascripts/window_title.js ###" >> "$LOG"
  cat "$PILLOW_DIR/javascripts/window_title.js" >> "$LOG" 2>&1

  echo "" >> "$LOG"
  echo "### javascripts/client_params_handler.js ###" >> "$LOG"
  cat "$PILLOW_DIR/javascripts/client_params_handler.js" >> "$LOG" 2>&1

  echo "" >> "$LOG"
  echo "### javascripts/sample_custom_dialog.js ###" >> "$LOG"
  cat "$PILLOW_DIR/javascripts/sample_custom_dialog.js" >> "$LOG" 2>&1

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
