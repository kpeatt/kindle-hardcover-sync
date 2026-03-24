#!/bin/sh
# Name: Sync to Hardcover
# Author: System
# UseHooks

# =========================================================
# CONFIGURATION
# =========================================================
HC_TOKEN="YOUR_HARDCOVER_TOKEN_HERE"
DB_PATH="/var/local/cc.db"
DEBUG_LOG="/mnt/us/documents/sync_debug.log"

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

on_run() {
    echo "🔍 Reading Kindle Database..."
    
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

    QUERY="SELECT $TITLE_COL, $AUTHOR_COL, p_percentFinished, $ASIN_COL FROM Entries WHERE $CDE_TYPE_COL = 'EBOK' AND p_percentFinished > 0 ORDER BY $ACCESS_COL DESC LIMIT 1;"
    
    BOOK_DATA=$(sqlite3 "$DB_COPY" "$QUERY")
    
    # Clean up the copy
    rm "$DB_COPY"
    
    if [ -z "$BOOK_DATA" ]; then
        echo "❌ Error: No recent books found."
        log_debug "Error: No recent books found in database."
        return 1
    fi

    TITLE=$(echo "$BOOK_DATA" | awk -F'|' '{print $1}')
    AUTHOR=$(echo "$BOOK_DATA" | awk -F'|' '{print $2}')
    PROGRESS=$(echo "$BOOK_DATA" | awk -F'|' '{print $3}')
    ASIN=$(echo "$BOOK_DATA" | awk -F'|' '{print $4}')

    CLEAN_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9 ]//g')
    CLEAN_AUTHOR=$(echo "$AUTHOR" | sed 's/[^a-zA-Z0-9 ]//g' | awk '{print $1}')

    WIFI_STATE=$(lipc-get-prop com.lab126.wifid cmState)
    if [ "$WIFI_STATE" != "CONNECTED" ]; then
        echo "📶 Connecting Wi-Fi..."
        lipc-set-prop com.lab126.wifid enable 1
        sleep 8
    fi

    echo "🌐 Searching Hardcover..."

    # Notice we are now explicitly asking Hardcover to return the `title` as well as the `id`
    SEARCH_QUERY=$(cat <<EOF
{
  "query": "query FindBook { 
    books(
      where: { 
        _or: [ 
          { identifiers: { identifier: { _eq: \"$ASIN\" } } }, 
          { 
            _and: [
              { title: { _ilike: \"%${CLEAN_TITLE}%\" } },
              { contributions: { author: { name: { _ilike: \"%${CLEAN_AUTHOR}%\" } } } }
            ]
          } 
        ] 
      }, 
      limit: 1
    ) { 
      id 
      title
    } 
  }"
}
EOF
)

    SEARCH_RESPONSE=$(gql_request "$SEARCH_QUERY")
    
    HC_BOOK_ID=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
    # Extract the Hardcover title string
    HC_TITLE=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')

    if [ -z "$HC_BOOK_ID" ]; then
        echo "❌ Error: Could not find book on Hardcover."
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
        echo "Debug info saved to documents/sync_debug.log"
        return 1
    fi

    # =========================================================
    # CONFIDENCE CHECK
    # =========================================================
    CONFIDENT=0
    
    # Check 1: Did we get a direct ASIN match in the JSON payload?
    if echo "$SEARCH_RESPONSE" | grep -q "\"$ASIN\""; then
        CONFIDENT=1
    fi

    # Check 2: Are the titles completely identical (case-insensitive)?
    KINDLE_TITLE_LOWER=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
    HC_TITLE_LOWER=$(echo "$HC_TITLE" | tr '[:upper:]' '[:lower:]')
    
    if [ "$KINDLE_TITLE_LOWER" = "$HC_TITLE_LOWER" ]; then
        CONFIDENT=1
    fi

    # If we are not confident, ask the user to confirm via touch
    if [ "$CONFIDENT" -eq 0 ]; then
        echo "⚠️ Low Confidence Match."
        echo "Kindle says: $TITLE"
        echo "Hardcover found: $HC_TITLE"
        echo ""
        echo "👉 TAP ANYWHERE ON THE SCREEN TO CONFIRM"
        echo "👉 PRESS THE POWER BUTTON TO CANCEL"
        
        # waitforkey pauses the shell script until a physical event occurs (screen tap or button press)
        waitforkey
        
        # If the user presses the power button, the screen turns off and the LIPC state changes.
        # We check if the screen just went to sleep. If so, abort.
        POWER_STATE=$(lipc-get-prop com.lab126.powerd state)
        if [ "$POWER_STATE" = "screenSaver" ] || [ "$POWER_STATE" = "suspended" ]; then
            echo "Cancelled."
            return 1
        fi
    else
        echo "🔗 Confident Match: $HC_TITLE"
    fi

    # =========================================================
    # UPLOAD PROGRESS
    # =========================================================
    UPDATE_MUTATION=$(cat <<EOF
{
  "query": "mutation UpdateProgress {
    upsert_user_book_reads(
      object: { 
        book_id: $HC_BOOK_ID, 
        progress_percentage: $PROGRESS,
        status_id: 2
      },
      on_conflict: { 
        constraint: user_book_reads_user_id_book_id_key, 
        update_columns: [progress_percentage, status_id] 
      }
    ) {
      id
    }
  }"
}
EOF
)

    echo "📤 Uploading progress ($PROGRESS%)..."
    UPDATE_RESPONSE=$(gql_request "$UPDATE_MUTATION")

    if echo "$UPDATE_RESPONSE" | grep -q "id"; then
        echo "✅ Successfully Synced!"
    else
        echo "❌ Sync failed. API Error."
    fi
}