#!/bin/sh
# Name: Sync to Hardcover
# Author: System
# UseHooks

on_run() {
    # Call the main sync script from the extension folder
    if [ -f "/mnt/us/extensions/kindle-hardcover-sync/bin/sync.sh" ]; then
        sh "/mnt/us/extensions/kindle-hardcover-sync/bin/sync.sh" manual
    else
        echo "❌ Error: Extension not found."
        echo "Please ensure the kindle-hardcover-sync folder"
        echo "is installed in /mnt/us/extensions/"
        return 1
    fi
}