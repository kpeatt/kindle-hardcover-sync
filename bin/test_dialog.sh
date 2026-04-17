#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
LOG="$DIR/test_dialog.log"
LIPC_SET=/usr/bin/lipc-set-prop
LIPC_GET=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
PILLOW_DIR=/usr/share/webkit-1.0/pillow
SRC_HTML_DIR=/mnt/us/extensions/kindle-hardcover-sync/html
MSGLOG=/var/log/messages

$EIPS -m "Tap B (middle) when dialog opens"
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

  MSG_START_BYTES=$(wc -c < "$MSGLOG" 2>/dev/null || echo 0)

  echo "### Firing hc_dialog (A B C) — tap B ###" >> "$LOG"
  $LIPC_SET com.lab126.pillow customDialog \
    '{"name":"hc_dialog","clientParams":{"title":"Title Reply Test","message":"Tap B (middle).","buttons":[{"label":"A","id":"a"},{"label":"B","id":"b"},{"label":"C","id":"c"}]}}' \
    >> "$LOG" 2>&1
  echo "exit: $?" >> "$LOG"

  REPLY=""
  i=0
  while [ $i -lt 20 ]; do
    # Check messages for HCR:<id> (WindowTitle.addParam) or HCREPLY_<id>_ (setWindowTitle)
    REPLY=$(tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null \
      | grep -oE "HCR:[a-z]+|HCREPLY_[a-z]+_" | head -n 1)
    [ -n "$REPLY" ] && break

    # Fallback: interrogate the pillow for window.hcReply
    $LIPC_SET com.lab126.pillow interrogatePillow \
      '{"pillowId":"hc-dialog","function":"return (window.hcReply||null);"}' > /dev/null 2>&1
    INTERROGATE=$($LIPC_GET -h com.lab126.pillow interrogatePillowHash 2>/dev/null | head -n 3 | tr '\n' ' ')
    if [ -n "$INTERROGATE" ] && echo "$INTERROGATE" | grep -q '"'; then
      REPLY="interrogate:$INTERROGATE"
      break
    fi

    sleep 1
    i=$((i + 1))
    echo "poll $i/20 ..." >> "$LOG"
  done

  if [ -n "$REPLY" ]; then
    echo "REPLY: $REPLY" >> "$LOG"
  else
    echo "No reply via any channel" >> "$LOG"
  fi

  echo "" >> "$LOG"
  echo "### relevant /var/log/messages lines ###" >> "$LOG"
  tail -c +$((MSG_START_BYTES + 1)) "$MSGLOG" 2>/dev/null \
    | grep -iE "HCR|HCREPLY|winmgr.*hc-dialog|pillow.*hc_dialog|interrogate" \
    | head -n 40 >> "$LOG"

  echo "" >> "$LOG"
  echo "Test complete at $(date)" >> "$LOG"
  $EIPS -m "Done. See test_dialog.log"
) &

exit 0
