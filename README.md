# DBIO::DB2

IBM DB2 database driver for DBIO (fork of DBIx::Class).

## Supports

- desired-state deployment via test-deploy-and-compare (L<DBIO::DB2::Deploy>)
- native introspection via SYSCAT (L<DBIO::DB2::Introspect>)
- native diff (L<DBIO::DB2::Diff>)
- native DDL generation (L<DBIO::DB2::DDL>)

## Usage

    package MyApp::DB;
    use base 'DBIO::Schema';
    __PACKAGE__->load_components('DB2');

    my $schema = MyApp::DB->connect('dbi:DB2:database=myapp');

DBIO core autodetects `dbi:DB2:` DSNs and loads this storage automatically.

## DB2 Features

**Types**
- `INTEGER`, `BIGINT`, `SMALLINT` — numeric types
- `VARCHAR`, `CHAR`, `CLOB` — string types
- `BLOB` — binary data
- `DATE`, `TIME`, `TIMESTAMP` — temporal types
- `DECIMAL` — fixed-point numeric

**Schema Support**
- SYSCAT for introspection (tables, columns, indexes, constraints)
- Schema-qualified table references

**Introspection (SYSCAT)**
- `SYSCAT.TABLES` — table metadata
- `SYSCAT.COLUMNS` — column metadata
- `SYSCAT.INDEXES` — index information
- `SYSCAT.TABCONST` — constraints

## Deploy

L<DBIO::DB2::Deploy> orchestrates test-deploy-and-compare:

1. Introspect live database via SYSCAT (L<DBIO::DB2::Introspect>)
2. Deploy desired schema to a temporary tablespace
3. Introspect the temporary schema the same way
4. Diff source vs target (L<DBIO::DB2::Diff>)

Install (`install_ddl`) creates fresh schema. Upgrade diffs live vs. desired.

## Testing

Requires a running DB2 instance:

```bash
export DBIO_TEST_DB2_DSN="dbi:DB2:database=myapp"
export DBIO_TEST_DB2_USER=db2inst1
export DBIO_TEST_DB2_PASS=secret
prove -l t/
```

## Requirements

- Perl 5.36+
- L<DBD::DB2|https://metacpan.org/pod/DBD::DB2>
- DBIO core

## See Also

L<DBIO::Introspect::Base>, L<DBIO::Diff::Base>, L<DBIO::Deploy>

## Repository

L<https://github.com/p5-dbio/dbio-db2>