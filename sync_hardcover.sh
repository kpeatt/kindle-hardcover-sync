#!/bin/sh
# Name: Sync to Hardcover
# Author: System
# UseHooks

# =========================================================
# CONFIGURATION
# =========================================================
TOKEN_FILE="/mnt/us/extensions/hardcover_token.txt"
DB_PATH="/var/local/cc.db"
DEBUG_LOG="/mnt/us/documents/sync_debug.log"

# Read token from file and strip any whitespace/newlines/carriage returns
if [ -f "$TOKEN_FILE" ]; then
    # Use tr to remove any spaces, tabs, newlines, and carriage returns (\r)
    HC_TOKEN=$(cat "$TOKEN_FILE" | tr -d ' \t\n\r')
elif [ -f "/mnt/us/hardcover_token.txt" ]; then
    # Fallback to root directory just in case
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

on_run() {
    if [ -z "$HC_TOKEN" ]; then
        echo "❌ Error: Missing API Token."
        echo "Please save your token in a file named:"
        echo "hardcover_token.txt"
        echo "inside the 'extensions' folder on your Kindle."
        return 1
    fi

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

    QUERY="SELECT $TITLE_COL, $AUTHOR_COL, p_percentFinished, $ASIN_COL FROM Entries WHERE ($CDE_TYPE_COL = 'EBOK' OR $CDE_TYPE_COL = 'PDOC') AND p_percentFinished > 0 ORDER BY $ACCESS_COL DESC LIMIT 1;"
    
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

    echo "🌐 Searching Hardcover (Exact Match)..."

    # Hardcover disables `_ilike` operators on their GraphQL server for performance.
    # We must use exact matching (`_eq`). Because side-loaded book titles can be messy,
    # we take just the first few words of the title to try and get a match.
    SHORT_TITLE=$(echo "$CLEAN_TITLE" | awk '{print $1" "$2}')
    
    SEARCH_QUERY="{\"query\": \"query FindBook { books(where: { _or: [ { identifiers: { identifier: { _eq: \\\"$ASIN\\\" } } }, { title: { _eq: \\\"$CLEAN_TITLE\\\" } }, { title: { _eq: \\\"$SHORT_TITLE\\\" } } ] }, limit: 1) { id title pages } }\"}"

    SEARCH_RESPONSE=$(gql_request "$SEARCH_QUERY")
    
    HC_BOOK_ID=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
    HC_TITLE=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')
    HC_PAGES=$(echo "$SEARCH_RESPONSE" | sed -n 's/.*"pages":\([0-9]*\).*/\1/p')

    # If exact match fails, fallback to Hardcover's custom fuzzy search action
    if [ -z "$HC_BOOK_ID" ]; then
        echo "🌐 Falling back to Fuzzy Search..."
        
        # Hardcover's search action takes a string and returns a stringified JSON array in `results`
        FUZZY_QUERY="{\"query\": \"query FuzzySearch { search(query: \\\"$SHORT_TITLE $CLEAN_AUTHOR\\\", query_type: Book, per_page: 1, page: 1) { results } }\"}"
        FUZZY_RESPONSE=$(gql_request "$FUZZY_QUERY")
        
        # Fuzzy search returns "id" as a string instead of an int ("id": "12345")
        # Use simple grep and awk since the JSON is stringified with slashes inside
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
    # GET OR CREATE USER_BOOK_ID & READ_ID
    # =========================================================
    echo "📚 Verifying Shelf Entry..."
    USER_BOOK_QUERY="{\"query\": \"query { me { user_books(where: { book_id: { _eq: $HC_BOOK_ID } }) { id user_book_reads(order_by: {started_at: desc}, limit: 1) { id started_at } } } }\"}"
    USER_BOOK_RESPONSE=$(gql_request "$USER_BOOK_QUERY")
    
    # Extract IDs using simple string parsing to avoid jq dependency on Kindle
    USER_BOOK_ID=$(echo "$USER_BOOK_RESPONSE" | sed -n 's/.*"user_books":\[{"id":\([0-9]*\).*/\1/p')

    if [ -z "$USER_BOOK_ID" ]; then
        echo "➕ Creating shelf entry on Hardcover..."
        CREATE_UB_MUT="{\"query\": \"mutation { insert_user_book(object: {book_id: $HC_BOOK_ID, status_id: 2}) { error user_book { id } } }\"}"
        CREATE_UB_RES=$(gql_request "$CREATE_UB_MUT")
        USER_BOOK_ID=$(echo "$CREATE_UB_RES" | sed -n 's/.*"user_book":{"id":\([0-9]*\)}.*/\1/p')
        READ_ID=""
        STARTED_AT=""
    else
        # Extract the latest read ID and started_at date (if any)
        READ_ID=$(echo "$USER_BOOK_RESPONSE" | sed -n 's/.*"user_book_reads":\[{"id":\([0-9]*\).*/\1/p')
        STARTED_AT=$(echo "$USER_BOOK_RESPONSE" | sed -n 's/.*"started_at":"\([^"]*\)".*/\1/p')
    fi

    if [ -z "$USER_BOOK_ID" ]; then
        echo "❌ Error: Could not verify shelf entry."
        DEBUG_INFO=$(cat <<EOF
Error: Could not get or create UserBook.
Book ID: $HC_BOOK_ID
Query Response: $USER_BOOK_RESPONSE
Mutation Response: $CREATE_UB_RES
EOF
)
        log_debug "$DEBUG_INFO"
        return 1
    fi

    # =========================================================
    # UPLOAD PROGRESS
    # =========================================================
    # Hardcover's backend expects progress in PAGES, not percentage.
    if [ -z "$HC_PAGES" ] || [ "$HC_PAGES" = "null" ]; then
        HC_PAGES=100
    fi
    CALCULATED_PAGES=$(awk "BEGIN {print int($PROGRESS * $HC_PAGES / 100)}")

    # Generate a UTC ISO8601 timestamp for the activity feed (Reading Journal)
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [ -n "$READ_ID" ]; then
        # Update existing read
        if [ -z "$STARTED_AT" ] || [ "$STARTED_AT" = "null" ]; then
            STARTED_AT=$(date +%Y-%m-%d)
        fi
        STARTED_STR=", started_at: \\\"$STARTED_AT\\\""
        UPDATE_MUTATION="{\"query\": \"mutation { update_user_book_read(id: $READ_ID, object: {progress_pages: $CALCULATED_PAGES $STARTED_STR}) { error } insert_reading_journal(object: {book_id: $HC_BOOK_ID, event: \\\"progress_updated\\\", action_at: \\\"$TIMESTAMP\\\", privacy_setting_id: 1, tags: [], metadata: {progress_pages: $CALCULATED_PAGES, progress: $PROGRESS}}) { reading_journal { id } } }\"}"
    else
        # Create a new read entry
        TODAY=$(date +%Y-%m-%d)
        UPDATE_MUTATION="{\"query\": \"mutation { insert_user_book_read(user_book_id: $USER_BOOK_ID, user_book_read: {progress_pages: $CALCULATED_PAGES, started_at: \\\"$TODAY\\\"}) { error } insert_reading_journal(object: {book_id: $HC_BOOK_ID, event: \\\"progress_updated\\\", action_at: \\\"$TIMESTAMP\\\", privacy_setting_id: 1, tags: [], metadata: {progress_pages: $CALCULATED_PAGES, progress: $PROGRESS}}) { reading_journal { id } } }\"}"
    fi

    echo "📤 Uploading progress ($PROGRESS% -> $CALCULATED_PAGES pages)..."
    UPDATE_RESPONSE=$(gql_request "$UPDATE_MUTATION")

    if echo "$UPDATE_RESPONSE" | grep -q '"error":null'; then
        echo "✅ Successfully Synced!"
    else
        echo "❌ Sync failed. API Error."
        DEBUG_INFO=$(cat <<EOF
Update Failed.
Mutation: $UPDATE_MUTATION
API Response: $UPDATE_RESPONSE
EOF
)
        log_debug "$DEBUG_INFO"
        echo "Debug info saved to documents/sync_debug.log"
    fi
}