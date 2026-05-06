# CLAUDE.md -- DBIO::DB2

## Namespace

- `DBIO::DB2` — DB2 schema component
- `DBIO::DB2::Storage` — DB2 storage (extends `DBIO::Storage::DBI`)
- `DBIO::DB2::{DDL,Deploy,Introspect,Diff}` — schema management via test-deploy-and-compare

## Usage

```perl
package MyApp::DB;
use base 'DBIO::Schema';
__PACKAGE__->load_components('DB2');

my $schema = MyApp::DB->connect('dbi:DB2:database=mydb', $user, $pass);
```

## Storage

`DBIO::DB2::Storage` extends `DBIO::Storage::DBI`:

```perl
__PACKAGE__->datetime_parser_type('DateTime::Format::DB2');
__PACKAGE__->sql_quote_char('"');
__PACKAGE__->dbio_deploy_class('DBIO::DB2::Deploy');
```

Key methods:
- `sql_name_sep` — queries `SQL_QUALIFIER_NAME_SEPARATOR` from server (default `.`)
- `_dbh_last_insert_id` — uses `IDENTITY_VAL_LOCAL()` for auto-increment retrieval
- `deploy_setup` — no-op stub (DB2 does not need tablespace pre-allocation)
- `limit_dialect` — auto-detected as `RowNumberOver` (DB2 5.4+) or `FetchFirst` (older)

## Introspection

`DBIO::DB2::Introspect` extends `DBIO::Introspect::Base`. Reads live DB state via:

- `SYSCAT.TABLES` — tables and views
- `SYSCAT.COLUMNS` — column metadata + primary key from `SYSCAT.KEYCOLUSE`/`SYSCAT.TABCONST`
- `SYSCAT.INDEXES` + `SYSCAT.INDEXCOLUSE` — index definitions
- `SYSCAT.TABCONST` + `SYSCAT.KEYCOLUSE` + `SYSCAT.REFERENCES` — foreign keys

Model shape: `{ tables, columns, indexes, foreign_keys }`.

## Diff

`DBIO::DB2::Diff` extends `DBIO::Diff::Base`. Compares two introspected models.
Operations emitted in dependency order: tables, columns, indexes.

## Deploy

`DBIO::DB2::Deploy` implements test-deploy-and-compare:

1. Introspect live DB (source)
2. Deploy desired schema to a temporary schema in the same DB
3. Introspect the temp schema (target)
4. Diff source vs target via `DBIO::DB2::Diff`

Supports `install`, `diff`, `apply`, and `upgrade`.

## DDL

`DBIO::DB2::DDL` generates DB2 DDL from DBIO result classes. Handles:
- `CREATE TABLE` with inline PK, unique constraints, and foreign keys
- `GENERATED ALWAYS AS IDENTITY` for auto-increment columns
- Topological sort for table creation order (FK dependencies)
- Index creation via `db2_indexes` method on result classes

Type mapping: PostgreSQL-style types (serial, bigserial, timestamptz) mapped to DB2 equivalents.

## Loader (legacy introspection)

`DBIO::DB2::Loader` extends `DBIO::Loader::DBI` for the old `DBIO::Loader` system.
Excludes system schemas: `SYSCAT`, `SYSIBM`, `SYSIBMADM`, `SYSPUBLIC`, `SYSSTAT`, `SYSTOOLS`.

## Foreign Keys

DB2 enforces referential integrity. FK constraints are emitted inline in `CREATE TABLE`
for new tables, and as separate `ALTER TABLE` statements in the diff for existing tables.

## Testing

Integration tests require a real DB2 instance:

```bash
export DBIO_TEST_DB2_DSN="dbi:DB2:database=mydb"
export DBIO_TEST_DB2_USER=db2admin
export DBIO_TEST_DB2_PASS=secret
prove -l t/
```

Tests:
- `t/00-load.t` — module load
- `t/10-db2.t` — storage, RNO, name_sep, limit dialect, auto-PK, populate, type_info

## Key Modules

| Module | Purpose |
|--------|---------|
| `DBIO::DB2` | Schema component |
| `DBIO::DB2::Storage` | DBI storage + driver registration |
| `DBIO::DB2::Deploy` | test-deploy-and-compare |
| `DBIO::DB2::Diff` | Compare introspected models |
| `DBIO::DB2::Introspect` | Read live DB via SYSCAT |
| `DBIO::DB2::DDL` | Generate DB2 DDL |
| `DBIO::DB2::Loader` | Legacy DBIO::Loader introspection |
