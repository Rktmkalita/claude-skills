---
name: sql-migration-repo-explorer
description: >
  Method for exploring an unfamiliar database repo whose schema lives in incremental SQL migration
  scripts and stored-procedure packages, cross-checked against the live data dictionary. Use when
  asked "where is table X defined", "which stored procedure writes this table", "does this
  column exist", "which schema/database service owns this table", "why does my query return no
  rows", "has this table/package changed recently", or "where does this value come from". Covers
  Oracle (ALL_*/DBA_* views) and PostgreSQL (information_schema / pg_catalog).
---

# SQL Migration Repo Explorer

A method for finding tables, columns, views, types and stored procedures in a database repo that is
organised as migration scripts rather than one file per object, and for tracing what reads or writes
them. It does not try to list every table. The live data dictionary is the complete source; the repo
tells you who wrote what and why.

---

## How to find a table or stored procedure (read first)

The repo tree is **not a catalogue**. Do not expect a complete table list from it, because:

1. **The schema is cumulative.** Table structure is spread across incremental migration scripts
   (CREATE/ALTER TABLE, types, grants, synonyms). The current shape of a table is the result of
   every script that touched it, in order. Stored procedures typically live in package or function
   files, and views in their own files.
2. **Some objects are owned elsewhere.** Objects created by other repos or teams appear here only as
   grants or synonyms, if at all.
3. **Search tooling can miss things.** Code search (hosted or local) can fail on large or unusual
   files, so an empty result is weak evidence.

**So, to find something:**

- **For the definitive list of what EXISTS** (schemas, tables, columns, packages, views, types,
  synonyms), query the **live data dictionary**, not the repo. See
  `references/data-dictionary-queries.md`. The database is complete and current; the repo is not.
- **To find WHERE a table is read or written, or what a procedure does**, search the repo
  thoroughly and in several forms:
  - the bare identifier, the `package.procedure` form, and partial tokens;
  - likely paths directly (package/function directory, migration directory, views directory);
  - the text of large package bodies, after opening them, for the procedure name and for
    `INSERT` / `UPDATE` / `DELETE` / `MERGE` against the table;
  - the calling application repos: their DAO / repository classes name the procedures and tables
    they call, which is often the fastest way to discover a procedure name.
- **Treat every negative search as a possible false negative.** Confirm by another route (a second
  search form, the data dictionary's dependency and source views) before concluding an object does
  not exist.

---

## 1. Schemas and database services

Objects may be split across several database services, instances or databases.

- **Querying the wrong service returns zero rows, not an error.** An empty result can mean "you are
  connected to the wrong place", not "no data". Confirm which service owns the object before
  trusting an empty result.
- **Synonyms and grants hide the owner.** A name visible from one schema may physically live in
  another, exposed through a synonym (Oracle) or a view / `search_path` (PostgreSQL) and made
  accessible by a grant. Resolve the real owner through the data dictionary (synonym views,
  dependency views) before tracing writes.
- **Map datasources to services from app config.** The calling applications' datasource
  configuration (per-environment properties / YAML, JDBC URLs, connection names) tells you which
  service and schema each app talks to. Record the mapping as you confirm it.

Keep a small table of confirmed mappings as you go:

| Service / database | Schema(s) | Examples of what lives here | Confirmed via |
|---|---|---|---|
| `<service>` | `APP_SCHEMA` | `<tables, packages>` | `<config file / dictionary query>` |

---

## 2. Repo layout and conventions

Identify, for this repo:

| Location | Contents |
|---|---|
| migration directory | Incremental DDL: CREATE/ALTER TABLE, types, grants, synonyms. Note the naming scheme (ticket prefix, version number, timestamp) because it gives the order. |
| package / function directory | Stored procedures: specs (signatures) and bodies (logic). |
| views directory | View definitions. |

Naming conventions worth checking for:

- **Audit / history suffix** (for example `*_AU`): a shadow table that records changes to a base
  table. When tracing "did X change in a time window", look for the base table's history table first.
- **Alias suffixes or prefixes** that mark a synonym or view exposed in one schema for a table owned
  in another.
- **Audit parameters** on writer procedures (for example `p_user_id`, `p_action`): the procedure
  itself decides whether they land in a history table or only stamp the current row. Read the body
  to find out which.

---

## 3. Tracing a domain end to end

Use this recipe for any table or value:

1. Find the table in the data dictionary; confirm the owning schema and service.
2. Resolve synonyms and grants so you know the real owner.
3. Find the procedure that writes it: search the repo thoroughly (multiple forms), and cross-check
   with the dictionary's dependency and source views.
4. Check for a history / audit table for the base table.
5. Cross-check from the calling app's DAO classes which procedure each code path calls.

---

## 4. Finding things — quick recipes

- **What schemas/tables exist?** → `references/data-dictionary-queries.md` (live DB queries).
- **Which procedure writes table X?** → search the repo for `X` in several forms, check for its
  history table, and cross-check from the calling app DAOs and the dictionary's dependency/source views.
- **What does package / function P do?** → open the spec (signatures) first, then the body; in a
  large body, search the text for the procedure name and for `INSERT` / `UPDATE` / `DELETE`.
- **Is name N a synonym?** → Oracle: `SELECT * FROM all_synonyms WHERE synonym_name = 'N';`
  (PostgreSQL has no synonyms; check views and `search_path`.)

---

## 5. Drift check and refresh

Notes you keep about a repo (service mappings, traced domains) drift. Before relying on them:

1. **Drift check the repo.** Compare against the commit you last verified:
   ```bash
   git log --oneline <baseline_commit>..HEAD -- <migrations-dir> <packages-dir> <views-dir>
   git log --oneline -10 -- <path/to/file>     # recent history of one object's file
   ```
   Scan the titles for structural changes (tables, types, grants, synonyms, views). Data-only
   commits (reference-data loads, rate updates) are usually not structural.
2. **Refresh the live catalogue** if you have a DB session: re-run the queries in
   `references/data-dictionary-queries.md`, and optionally snapshot the results to a notes file
   stamped with the date and the service/schema they came from.
3. **Confirm any unverified items** in your notes against the column views, and update them.
4. **Record the new baseline** commit and date in your notes.

---

## Reference files

- `references/data-dictionary-queries.md` — SQL to list every schema, table, column, procedure,
  view, type and synonym from the live database (Oracle, with PostgreSQL equivalents).
