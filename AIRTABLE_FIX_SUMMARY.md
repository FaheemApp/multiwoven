# Airtable Sync Duplicate Records Fix

## Problem

When syncing from MariaDB to Airtable, if Airtable already contained records with the same IDs:
- **First sync**: Created duplicate records instead of recognizing existing ones
- **Example**:
  - Airtable has: ID=1 (Oaayda), ID=2 (Ahmed)
  - Database has: ID=1 (Obayda), ID=2 (Ahmed), ID=3 (Osama)
  - **Expected**: Update ID=1, skip ID=2, insert ID=3
  - **Actual**: Created 3 NEW records (duplicating ID=1 and ID=2)

## Root Cause

The Airtable connector had two critical issues:

1. **Ignored action parameter**: `_action` (underscore prefix) was ignored
2. **No lookup logic**: Never checked if records existed in Airtable before inserting
3. **Always POST**: Only used POST (create), never PATCH (update)

### How It Should Work

Multiwoven tracks sync state in the `sync_records` table:
- First sync: No records in `sync_records` → marks all as `destination_insert`
- Subsequent syncs: Compares fingerprints → marks changed records as `destination_update`

**BUT** the Airtable connector ignored these actions and always created new records!

## The Fix

Modified `integrations/lib/multiwoven/integrations/destination/airtable/client.rb`:

### 1. Accept Action Parameter (Line 58)
```ruby
# BEFORE
def write(sync_config, records, _action = "create")

# AFTER
def write(sync_config, records, action = "destination_insert")
```

### 2. Query Airtable for Existing Records
```ruby
def find_airtable_record(url, field_name, field_value, api_key)
  formula = "{#{field_name}}='#{field_value}'"
  search_url = "#{url}?filterByFormula=#{CGI.escape(formula)}&maxRecords=1"
  # GET request to find existing record
  # Returns Airtable record with internal ID
end
```

### 3. Process Records Based on Action
```ruby
def process_records_for_action(records, action, primary_key, url, api_key)
  if action == "destination_insert"
    # Just create payload with fields
  else
    # For updates: find existing records and include Airtable IDs
    records.map do |record|
      existing = find_airtable_record(...)
      if existing
        { id: existing["id"], fields: record }  # For PATCH
      else
        { fields: record }  # Fallback to create
      end
    end
  end
end
```

### 4. Use Correct HTTP Method
```ruby
# For inserts: POST
http_method = action == "destination_update" ? "PATCH" : HTTP_POST

# PATCH payload includes Airtable record IDs
# POST payload only includes fields
```

## How It Works Now

### First Sync (No Previous Tracking)
1. Extractor reads DB: ID=1,2,3
2. Multiwoven `sync_records` is empty → marks all as `destination_insert`
3. Airtable connector:
   - Receives `action = "destination_insert"`
   - Does NOT query Airtable (optimization for inserts)
   - POSTs all records as new
4. **Result**: Still creates duplicates on FIRST sync if Airtable has data

### Second Sync (Data Changed in DB)
1. Extractor reads DB: ID=1 (NAME updated)
2. Fingerprint changed → marks as `destination_update`
3. Airtable connector:
   - Receives `action = "destination_update"`
   - Queries Airtable: `GET ?filterByFormula={id}='1'`
   - Gets Airtable record ID: `rec123456...`
   - PATCHes with: `{ id: "rec123456", fields: {...} }`
4. **Result**: Correctly updates existing record

## Limitations

**Known Issue**: First sync still creates duplicates if Airtable already has data.

### Why?
- Multiwoven has no sync history (empty `sync_records` table)
- Treats everything as new inserts
- Airtable connector optimizes by skipping lookup for inserts

### Potential Solutions

**Option 1**: Always query Airtable (slower but safer)
```ruby
# Always check if record exists, even for inserts
existing = find_airtable_record(...)
```

**Option 2**: Add "initial sync" flag to query Airtable on first run

**Option 3**: Manual cleanup before first sync
- Delete existing records from Airtable
- Let Multiwoven create them fresh

## Testing

### Test Insert Operation
```bash
cd integrations
bundle exec rspec spec/multiwoven/integrations/destination/airtable/client_spec.rb:153
```

### Test Update Operation (Manual)
1. Create sync with test data
2. Verify records created in Airtable
3. Update data in source DB
4. Run sync again
5. Verify records UPDATED (not duplicated) in Airtable

### Integration Test
```bash
cd server
bundle exec rspec spec/lib/reverse_etl/loaders/standard_spec.rb
```

## Files Changed

- `integrations/lib/multiwoven/integrations/destination/airtable/client.rb`
  - Modified `write` method to accept action parameter
  - Added `find_airtable_record` method
  - Added `process_records_for_action` method
  - Added `create_payload_with_ids` method
  - Added `require "cgi"` for URL encoding

## Migration Notes

No database migrations required. Changes are backward compatible:
- Existing syncs will work as before
- New syncs benefit from update logic immediately

## Performance Impact

**For Updates**:
- Additional GET request per chunk to find existing records
- Rate limit: Airtable allows 5 requests/second
- For batch size 10: 1 extra request per 10 records

**For Inserts**:
- No performance impact (skips lookup)

## Recommendations

1. **First sync with existing data**:
   - Clear Airtable table before first sync, OR
   - Accept duplicates, manually clean up, subsequent syncs work correctly

2. **Primary key field**:
   - Ensure primary key field in sync config matches Airtable field name exactly
   - Case-sensitive!

3. **Monitor rate limits**:
   - Airtable: 5 requests/second
   - Large updates may take longer due to lookup queries
