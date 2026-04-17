#!/bin/sh

# =========================================================
# CONFIGURATION
# =========================================================
DIR="$( cd "$( dirname "$0" )/.." && pwd )"
TOKEN_FILE="$DIR/hardcover_token.txt"
CACHE_FILE="$DIR/hc_cache.txt"
DEBUG_LOG="$DIR/sync_debug.log"
DB_PATH="/var/local/cc.db"
MODE="${1:-manual}"

# Read token from file and strip any whitespace/newlines/carriage returns
if [ -f "$TOKEN_FILE" ]; then
    HC_TOKEN=$(cat "$TOKEN_FILE" | tr -d ' \t\n\r')
elif [ -f "/mnt/us/hardcover_token.txt" ]; then
    HC_TOKEN=$(cat "/mnt/us/hardcover_token.txt" | tr -d ' \t\n\r')
else
    HC_TOKEN=""
fi

gql_request() {
  curl -s -X POST https://api.hardcover.app/v1/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $HC_TOKEN" \
    -d "$1"
}

log_debug() {
  echo "-----------------------------------" >> "$DEBUG_LOG"
  echo "Timestamp: $(date)" >> "$DEBUG_LOG"
  echo "$1" >> "$DEBUG_LOG"
}

# Show a Pillow customDialog and print the clicked button's id on stdout.
# $1: clientParams JSON (object with title, message, buttons[])
# Returns empty string on timeout (5 min).
show_dialog() {
  rm -f /tmp/hc_dialog_reply
  lipc-set-prop com.lab126.pillow customDialog "{\"name\":\"../../../../mnt/us/extensions/kindle-hardcover-sync/html/dialog\",\"clientParams\":$1}"

  i=0
  while [ $i -lt 300 ]; do
    if [ -f /tmp/hc_dialog_reply ]; then
      cat /tmp/hc_dialog_reply
      rm -f /tmp/hc_dialog_reply
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

on_run() {
    if [ -z "$HC_TOKEN" ]; then
        if [ "$MODE" = "manual" ]; then eips -m "❌ Error: Missing Hardcover API Token!"; fi
        return 1
    fi

    if [ "$MODE" = "manual" ]; then eips -m "🔍 Reading Kindle Database..."; fi
    
    # Safely copy the database to avoid "database locked" errors
    DB_COPY="/tmp/cc_copy.db"
    cp "$DB_PATH" "$DB_COPY"
    
    # Extract column names robustly (Kindle's busybox grep doesn't always support -o)
    COLS=$(sqlite3 "$DB_COPY" "PRAGMA table_info(Entries);")
    
    if echo "$COLS" | grep -q "|p_title|"; then
        # Old schema (<5.16)
        TITLE_COL="p_title"
        AUTHOR_COL="p_author"
        ASIN_COL="p_asin"
        ACCESS_COL="p_lastAccess"
        CDE_TYPE_COL="p_type"
    else
        # New schema (5.16+)
        TITLE_COL=$(echo "$COLS" | awk -F'|' '{print $2}' | grep '^p_titles_0_' | head -n 1)
        AUTHOR_COL=$(echo "$COLS" | awk -F'|' '{print $2}' | grep '^p_credits_0_' | head -n 1)
        ACCESS_COL=$(echo "$COLS" | awk -F'|' '{print $2}' | grep '^p_lastAccess' | head -n 1)
        ASIN_COL="p_cdeKey"
        CDE_TYPE_COL="p_cdeType"
        
        # Fallbacks just in case
        [ -z "$TITLE_COL" ] && TITLE_COL="p_titles_0_name"
        [ -z "$AUTHOR_COL" ] && AUTHOR_COL="p_credits_0_name"
        [ -z "$ACCESS_COL" ] && ACCESS_COL="p_lastAccessTime"
    fi

    QUERY="SELECT $TITLE_COL, $AUTHOR_COL, p_percentFinished, $ASIN_COL FROM Entries WHERE ($CDE_TYPE_COL = 'EBOK' OR $CDE_TYPE_COL = 'PDOC') AND p_percentFinished > 0 ORDER BY $ACCESS_COL DESC LIMIT 1;"
    
    BOOK_DATA=$(sqlite3 "$DB_COPY" "$QUERY")
    
    # Clean up the copy
    rm "$DB_COPY"
    
    if [ -z "$BOOK_DATA" ]; then
        if [ "$MODE" = "manual" ]; then eips -m "❌ Error: No recent books found."; fi
        log_debug "Error: No recent books found in database."
        return 1
    fi

    TITLE=$(echo "$BOOK_DATA" | awk -F'|' '{print $1}')
    AUTHOR=$(echo "$BOOK_DATA" | awk -F'|' '{print $2}')
    PROGRESS=$(echo "$BOOK_DATA" | awk -F'|' '{print $3}')
    ASIN=$(echo "$BOOK_DATA" | awk -F'|' '{print $4}')

    CLEAN_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9 ]//g')
    CLEAN_AUTHOR=$(echo "$AUTHOR" | sed 's/[^a-zA-Z0-9 ]//g' | awk '{print $1}')
    SHORT_TITLE=$(echo "$CLEAN_TITLE" | awk '{print $1" "$2}')

    # =========================================================
    # CACHE CHECK
    # =========================================================
    CACHED_MATCH=$(grep "^$ASIN|" "$CACHE_FILE" 2>/dev/null | head -n 1)

    if [ "$MODE" = "auto_check" ]; then
        if [ -n "$CACHED_MATCH" ]; then
            return 0 # Already tracked or explicitly ignored
        fi
        
        # Pop up dialog asking to track the new book
        ASK_PARAMS='{"title":"New Book Detected","message":"Track progress for '"$SHORT_TITLE"' on Hardcover?","buttons":[{"label":"Yes","id":"yes"},{"label":"No","id":"no"}]}'
        ANS=$(show_dialog "$ASK_PARAMS")

        if [ "$ANS" != "yes" ]; then
            # Cache it as IGNORE so we never ask again
            echo "$ASIN|IGNORE|IGNORE|0" >> "$CACHE_FILE"
            return 0
        fi
        
        # If Yes, we let the script fall through to do the network search and cache the ID right now.
        if [ "$MODE" = "manual" ]; then eips -m "🌐 Linking to Hardcover..."; fi
    fi

    if [ -n "$CACHED_MATCH" ]; then
        if [ "$MODE" = "manual" ]; then eips -m "⚡ Found book in local cache!"; fi
        
        HC_BOOK_ID=$(echo "$CACHED_MATCH" | awk -F'|' '{print $2}')
        if [ "$HC_BOOK_ID" = "IGNORE" ]; then
            if [ "$MODE" = "manual" ]; then eips -m "⏭️ Tracking disabled for this book."; fi
            return 0 # User chose not to track this book
        fi
        
        HC_TITLE=$(echo "$CACHED_MATCH" | awk -F'|' '{print $3}')
        HC_PAGES=$(echo "$CACHED_MATCH" | awk -F'|' '{print $4}')
    else
        if [ "$MODE" = "auto_sync" ]; then
            # Book was closed, but it's not in cache. They probably ignored the 'auto_check' dialog. 
            # We ignore it to avoid unwanted background Wi-Fi usage.
            return 0
        fi

        # Need to search network. Ensure Wi-Fi is on.
        WIFI_STATE=$(lipc-get-prop com.lab126.wifid cmState)
        if [ "$WIFI_STATE" != "CONNECTED" ]; then
            if [ "$MODE" = "manual" ]; then eips -m "📶 Connecting Wi-Fi..."; fi
            lipc-set-prop com.lab126.wifid enable 1
            sleep 8
        fi

        if [ "$MODE" = "manual" ]; then eips -m "🌐 Searching Hardcover (Exact Match)..."; fi

        SEARCH_QUERY="{\"query\": \"query FindBook { books(where: { _or: [ { identifiers: { identifier: { _eq: \\\"$ASIN\\\" } } }, { title: { _eq: \\\"$CLEAN_TITLE\\\" } }, { title: { _eq: \\\"$SHORT_TITLE\\\" } } ] }, limit: 1) { id title pages } }\"}"
        SEARCH_RESPONSE=$(gql_request "$SEARCH_QUERY")
        
        HC_BOOK_ID=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
        HC_TITLE=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')
        HC_PAGES=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"pages":\([0-9]*\).*/\1/p')

        # If exact match fails, fallback to Hardcover's custom fuzzy search action
        if [ -z "$HC_BOOK_ID" ]; then
            if [ "$MODE" = "manual" ]; then eips -m "🌐 Falling back to Fuzzy Search..."; fi
            
            FUZZY_QUERY="{\"query\": \"query FuzzySearch { search(query: \\\"$SHORT_TITLE $CLEAN_AUTHOR\\\", query_type: Book, per_page: 1, page: 1) { results } }\"}"
            FUZZY_RESPONSE=$(gql_request "$FUZZY_QUERY")
            
            HC_BOOK_ID=$(echo "$FUZZY_RESPONSE" | grep -o '\\"id\\":\\"[0-9]*\\"' | head -n 1 | awk -F'"' '{print $6}')
            if [ -z "$HC_BOOK_ID" ]; then
                HC_BOOK_ID=$(echo "$FUZZY_RESPONSE" | grep -o '"id":"[0-9]*"' | head -n 1 | awk -F'"' '{print $4}')
            fi

            HC_TITLE=$(echo "$FUZZY_RESPONSE" | grep -o '\\"title\\":\\"[^\\]*\\"' | head -n 1 | awk -F'"' '{print $6}')
            if [ -z "$HC_TITLE" ]; then
                HC_TITLE=$(echo "$FUZZY_RESPONSE" | grep -o '"title":"[^"]*"' | head -n 1 | awk -F'"' '{print $4}')
            fi
            
            HC_PAGES=$(echo "$FUZZY_RESPONSE" | grep -o '\\"pages\\":[0-9]*' | head -n 1 | awk -F':' '{print $2}')
            if [ -z "$HC_PAGES" ]; then
                HC_PAGES=$(echo "$FUZZY_RESPONSE" | grep -o '"pages":[0-9]*' | head -n 1 | awk -F':' '{print $2}')
            fi
            
            SEARCH_RESPONSE="Exact: $SEARCH_RESPONSE | Fuzzy: $FUZZY_RESPONSE"
        fi

        if [ -z "$HC_BOOK_ID" ]; then
            if [ "$MODE" = "manual" ]; then eips -m "❌ Error: Could not find book on Hardcover."; fi
            DEBUG_INFO=$(cat <<EOF
Error: Book not found.
Kindle Title: '$TITLE'
Kindle Author: '$AUTHOR'
Kindle ASIN: '$ASIN'
Clean Title Search: '$CLEAN_TITLE'
Clean Author Search: '$CLEAN_AUTHOR'
Search Query: $SEARCH_QUERY
API Response: $SEARCH_RESPONSE
EOF
)
            log_debug "$DEBUG_INFO"
            return 1
        fi

        # =========================================================
        # CONFIDENCE CHECK
        # =========================================================
        CONFIDENT=0
        if echo "$SEARCH_RESPONSE" | grep -q "\"$ASIN\""; then CONFIDENT=1; fi
        
        KINDLE_TITLE_LOWER=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
        HC_TITLE_LOWER=$(echo "$HC_TITLE" | tr '[:upper:]' '[:lower:]')
        if [ "$KINDLE_TITLE_LOWER" = "$HC_TITLE_LOWER" ]; then CONFIDENT=1; fi

        if [ "$CONFIDENT" -eq 0 ]; then
            CONFIRM_PARAMS='{"title":"Low Confidence Match","message":"Kindle says: '$SHORT_TITLE'\nHardcover says: '$HC_TITLE'\n\nIs this correct?","buttons":[{"label":"Yes","id":"yes"},{"label":"No","id":"no"}]}'
            CONFIRM_ANS=$(show_dialog "$CONFIRM_PARAMS")

            if [ "$CONFIRM_ANS" != "yes" ]; then
                if [ "$MODE" = "manual" ]; then eips -m "Cancelled."; fi
                return 1
            fi
        fi

        # Save to cache
        echo "$ASIN|$HC_BOOK_ID|$HC_TITLE|$HC_PAGES" >> "$CACHE_FILE"
    fi

    # If this was just the auto_check daemon, we're done after caching.
    if [ "$MODE" = "auto_check" ]; then
        return 0
    fi

    # =========================================================
    # FINISHED & RATING CHECK
    # =========================================================
    STATUS_ID=2
    RATING_MUTATION=""

    INT_PROGRESS=${PROGRESS%.*}
    if [ "$INT_PROGRESS" -ge 99 ]; then
        STATUS_ID=3 # Read
        
        RATING_PARAMS='{"title":"Book Finished!","message":"What is your Hardcover star rating?","buttons":[{"label":"1","id":"r1"},{"label":"2","id":"r2"},{"label":"3","id":"r3"},{"label":"4","id":"r4"},{"label":"5","id":"r5"},{"label":"Skip","id":"r_skip"}]}'
        RATING_ANS=$(show_dialog "$RATING_PARAMS")
        RATING_VAL=$(echo "$RATING_ANS" | sed -n 's/^r\([1-5]\)$/\1/p')
        if [ -n "$RATING_VAL" ]; then
            RATING_MUTATION=", rating: $RATING_VAL"
            if [ "$MODE" = "manual" ]; then eips -m "⭐ Rating: $RATING_VAL Stars"; fi
        fi
    fi

    # Ensure Wi-Fi is on before sending data
    WIFI_STATE=$(lipc-get-prop com.lab126.wifid cmState)
    if [ "$WIFI_STATE" != "CONNECTED" ]; then
        lipc-set-prop com.lab126.wifid enable 1
        sleep 8
    fi

    # =========================================================
    # GET OR CREATE USER_BOOK_ID & READ_ID
    # =========================================================
    USER_BOOK_QUERY="{\"query\": \"query { me { user_books(where: { book_id: { _eq: $HC_BOOK_ID } }) { id user_book_reads(order_by: {started_at: desc}, limit: 1) { id started_at } } } }\"}"
    USER_BOOK_RESPONSE=$(gql_request "$USER_BOOK_QUERY")
    
    USER_BOOK_ID=$(echo "$USER_BOOK_RESPONSE" | sed -n 's/.*"user_books":\[{"id":\([0-9]*\).*/\1/p')

    if [ -z "$USER_BOOK_ID" ]; then
        CREATE_UB_MUT="{\"query\": \"mutation { insert_user_book(object: {book_id: $HC_BOOK_ID, status_id: $STATUS_ID $RATING_MUTATION}) { error user_book { id } } }\"}"
        CREATE_UB_RES=$(gql_request "$CREATE_UB_MUT")
        USER_BOOK_ID=$(echo "$CREATE_UB_RES" | sed -n 's/.*"user_book":{"id":\([0-9]*\)}.*/\1/p')
        READ_ID=""
        STARTED_AT=""
    else
        READ_ID=$(echo "$USER_BOOK_RESPONSE" | sed -n 's/.*"user_book_reads":\[{"id":\([0-9]*\).*/\1/p')
        STARTED_AT=$(echo "$USER_BOOK_RESPONSE" | sed -n 's/.*"started_at":"\([^"]*\)".*/\1/p')
    fi

    if [ -z "$USER_BOOK_ID" ]; then
        if [ "$MODE" = "manual" ]; then eips -m "❌ Error: Could not verify shelf entry."; fi
        return 1
    fi

    # =========================================================
    # UPLOAD PROGRESS
    # =========================================================
    if [ -z "$HC_PAGES" ] || [ "$HC_PAGES" = "null" ]; then
        HC_PAGES=100
    fi
    
    if [ "$INT_PROGRESS" -ge 99 ]; then
        CALCULATED_PAGES=$HC_PAGES
    else
        CALCULATED_PAGES=$(awk "BEGIN {print int($PROGRESS * $HC_PAGES / 100)}")
    fi

    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [ -n "$READ_ID" ]; then
        if [ -z "$STARTED_AT" ] || [ "$STARTED_AT" = "null" ]; then
            STARTED_AT=$(date +%Y-%m-%d)
        fi
        STARTED_STR=", started_at: \\\"$STARTED_AT\\\""
        UPDATE_MUTATION="{\"query\": \"mutation { update_user_book(id: $USER_BOOK_ID, object: {status_id: $STATUS_ID $RATING_MUTATION}) { error } update_user_book_read(id: $READ_ID, object: {progress_pages: $CALCULATED_PAGES $STARTED_STR}) { error } insert_reading_journal(object: {book_id: $HC_BOOK_ID, event: \\\"progress_updated\\\", action_at: \\\"$TIMESTAMP\\\", privacy_setting_id: 1, tags: [], metadata: {progress_pages: $CALCULATED_PAGES, progress: $PROGRESS}}) { reading_journal { id } } }\"}"
    else
        TODAY=$(date +%Y-%m-%d)
        UPDATE_MUTATION="{\"query\": \"mutation { update_user_book(id: $USER_BOOK_ID, object: {status_id: $STATUS_ID $RATING_MUTATION}) { error } insert_user_book_read(user_book_id: $USER_BOOK_ID, user_book_read: {progress_pages: $CALCULATED_PAGES, started_at: \\\"$TODAY\\\"}) { error } insert_reading_journal(object: {book_id: $HC_BOOK_ID, event: \\\"progress_updated\\\", action_at: \\\"$TIMESTAMP\\\", privacy_setting_id: 1, tags: [], metadata: {progress_pages: $CALCULATED_PAGES, progress: $PROGRESS}}) { reading_journal { id } } }\"}"
    fi

    if [ "$MODE" = "manual" ]; then eips -m "📤 Uploading progress ($PROGRESS%)..."; fi
    UPDATE_RESPONSE=$(gql_request "$UPDATE_MUTATION")

    if echo "$UPDATE_RESPONSE" | grep -q '"error":null'; then
        if [ "$MODE" = "manual" ]; then eips -m "✅ Successfully Synced!"; fi
    else
        if [ "$MODE" = "manual" ]; then eips -m "❌ Sync failed. Check debug log."; fi
        DEBUG_INFO=$(cat <<EOF
Update Failed.
Mutation: $UPDATE_MUTATION
API Response: $UPDATE_RESPONSE
EOF
)
        log_debug "$DEBUG_INFO"
    fi
}

on_run