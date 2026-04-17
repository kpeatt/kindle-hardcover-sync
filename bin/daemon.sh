#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
PID_FILE="$DIR/daemon.pid"

start_daemon() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        eips -m "Hardcover Daemon is already running!"
        return
    fi

    # Run the watcher loop in the background
    (
        echo $$ > "$PID_FILE"
        
        # Monitor reader foreground/background transitions
        lipc-wait-event -m -s 0 com.lab126.appmgrd appActivating | while read line; do
            case "$line" in
                *'appActivating 1 "com.lab126.booklet.reader"'*)
                    # Book opened. Wait briefly for database to update lastAccess, then check cache
                    sleep 5
                    sh "$DIR/bin/sync.sh" auto_check
                    ;;
                *'appActivating 0 "com.lab126.booklet.reader"'*)
                    # Book closed. Trigger auto sync!
                    sh "$DIR/bin/sync.sh" auto_sync
                    ;;
            esac
        done
    ) &
    
    eips -m "Hardcover Auto-Sync Daemon Started!"
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            # Kill the background lipc-wait-event process and the while loop
            pkill -P $PID
            kill $PID
            rm "$PID_FILE"
            eips -m "Hardcover Auto-Sync Daemon Stopped."
        else
            rm "$PID_FILE"
            eips -m "Daemon was not running (stale PID)."
        fi
    else
        eips -m "Daemon is not running."
    fi
}

case "$1" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        ;;
esac