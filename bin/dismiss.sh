#!/bin/sh
# Force-dismiss any stuck Pillow dialog by toggling Pillow off/on.
/usr/sbin/eips -m "Dismissing dialogs..."
/usr/bin/lipc-set-prop com.lab126.pillow disableEnablePillow 0 2>/dev/null
sleep 1
/usr/bin/lipc-set-prop com.lab126.pillow disableEnablePillow 1 2>/dev/null
/usr/sbin/eips -m "Done."
