# CLAUDE.md -- DBIO::DB2

## Project Vision

IBM DB2-specific storage for DBIO (the DBIx::Class fork, see ../dbio/).

**Status**: Active development. Storage extracted from DBIO core.

## Namespace

- `DBIO::DB2` — DB2 schema component
- `DBIO::DB2::Storage` — DB2 storage (replaces DBIx::Class::Storage::DBI::DB2)

## Build System

Uses Dist::Zilla with `[@DBIO]` plugin bundle. PodWeaver with `=attr` and `=method` collectors.
