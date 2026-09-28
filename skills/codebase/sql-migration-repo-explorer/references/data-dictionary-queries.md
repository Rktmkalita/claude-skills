# Data dictionary queries — the authoritative "all tables / schemas" source

The repo does **not** contain a reliable complete list of tables: structure is spread across
migration scripts, and some objects are owned by other repos. The **live database's data dictionary
is the only complete, current source.** Run these from a session on the relevant service. Objects
may be split across services, so run them per service, or from a session with cross-schema grants.

Replace `APP_SCHEMA` with the schema you are exploring.

---

## Oracle

If your account lacks `DBA_*` visibility, use the `ALL_*` views (what the current user can see). Use
`DBA_*` instead of `ALL_*` if you have the privilege and want everything regardless of grants.

### Schemas / owners
```sql
-- users that own objects
SELECT username FROM all_users ORDER BY username;
-- owners that actually have tables
SELECT owner, COUNT(*) AS table_count FROM all_tables GROUP BY owner ORDER BY owner;
```

### All tables (optionally per schema)
```sql
SELECT owner, table_name, num_rows, last_analyzed
FROM   all_tables
-- WHERE owner = 'APP_SCHEMA'
ORDER BY owner, table_name;
```

### Columns for a table (or whole schema)
```sql
SELECT owner, table_name, column_id, column_name, data_type, data_length, nullable
FROM   all_tab_columns
WHERE  owner = :owner
-- AND  table_name = :table          -- omit to dump the whole schema
ORDER BY owner, table_name, column_id;
```

### Packages, procedures, views, types, synonyms
```sql
-- objects by type
SELECT owner, object_type, COUNT(*) FROM all_objects
WHERE  object_type IN ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','VIEW','TYPE','SYNONYM','TABLE','TRIGGER','SEQUENCE')
GROUP BY owner, object_type ORDER BY owner, object_type;

-- procedures/functions inside packages
SELECT owner, object_name AS package_name, procedure_name
FROM   all_procedures
WHERE  object_type = 'PACKAGE' AND procedure_name IS NOT NULL
ORDER BY owner, package_name, procedure_name;

-- views and their text
SELECT owner, view_name FROM all_views ORDER BY owner, view_name;
SELECT text FROM all_views WHERE owner = :owner AND view_name = :view;   -- LONG column

-- synonyms (resolve names that point elsewhere)
SELECT owner, synonym_name, table_owner, table_name, db_link
FROM   all_synonyms ORDER BY owner, synonym_name;
```

### Find which object references a table / which procedure touches it
```sql
-- dependencies recorded by Oracle (package -> table, view -> table, etc.)
SELECT owner, name, type, referenced_owner, referenced_name, referenced_type
FROM   all_dependencies
WHERE  referenced_name = :table_name
ORDER BY owner, name;

-- brute force: search all stored source for a token (table name, column, literal)
SELECT owner, name, type, line, text
FROM   all_source
WHERE  UPPER(text) LIKE '%' || UPPER(:token) || '%'
ORDER BY owner, name, line;
```
`all_dependencies` + `all_source` together are the database-side equivalent of "search the repo for
who uses this", and they are authoritative where repo code search is unreliable.

### Audit / history tables
```sql
-- the _AU convention: find a table's history table
SELECT owner, table_name FROM all_tables
WHERE  table_name = :base_table || '_AU' OR table_name LIKE :base_table || '%_AU';
```

---

## PostgreSQL equivalents

`information_schema` views show only objects the current role has some privilege on; `pg_catalog`
shows everything in the current database. A PostgreSQL connection sees one database at a time, so
"wrong service" becomes "wrong database" here.

### Schemas
```sql
SELECT schema_name FROM information_schema.schemata ORDER BY schema_name;
```

### Tables (with row estimates and last analyze)
```sql
SELECT table_schema, table_name
FROM   information_schema.tables
WHERE  table_type = 'BASE TABLE'
-- AND  table_schema = 'app_schema'
ORDER BY table_schema, table_name;

SELECT schemaname, relname, n_live_tup, last_analyze, last_autoanalyze
FROM   pg_stat_user_tables
ORDER BY schemaname, relname;
```

### Columns
```sql
SELECT table_schema, table_name, ordinal_position, column_name, data_type,
       character_maximum_length, is_nullable
FROM   information_schema.columns
WHERE  table_schema = :schema
-- AND  table_name = :table
ORDER BY table_schema, table_name, ordinal_position;
```

### Functions / procedures and their source
```sql
SELECT routine_schema, routine_name, routine_type
FROM   information_schema.routines
WHERE  routine_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY routine_schema, routine_name;

-- full definition of one routine
SELECT pg_get_functiondef(p.oid)
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = :schema AND p.proname = :routine;
```

### Views
```sql
SELECT table_schema, table_name, view_definition
FROM   information_schema.views
WHERE  table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name;
```

### Synonyms
PostgreSQL has no synonyms. Names are resolved through `search_path` (`SHOW search_path;`), and
cross-schema aliases are usually views. Tables in other databases appear as foreign tables:
```sql
SELECT foreign_table_schema, foreign_table_name, foreign_server_name
FROM   information_schema.foreign_tables;
```

### Who references a table
```sql
-- views that use a table
SELECT view_schema, view_name
FROM   information_schema.view_table_usage
WHERE  table_schema = :schema AND table_name = :table;

-- brute force: search function/procedure bodies for a token
-- (dependencies inside PL/pgSQL bodies are not tracked by the catalog)
SELECT n.nspname, p.proname
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  p.prosrc ILIKE '%' || :token || '%'
ORDER BY n.nspname, p.proname;
```

### Triggers (writes that happen without an explicit call)
```sql
SELECT event_object_schema, event_object_table, trigger_name, event_manipulation, action_statement
FROM   information_schema.triggers
ORDER BY event_object_schema, event_object_table, trigger_name;
```

---

## Suggested snapshot workflow (optional static catalogue)

Spool the outputs of the queries above to files and save them as notes (for example
`catalogue_<schema>.md`). Re-run on refresh. Record in each snapshot the date and the
service/database and schema it came from, because they drift.
