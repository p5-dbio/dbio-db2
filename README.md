# DBIO-DB2

IBM DB2 driver distribution for DBIO.

## Scope

- Provides DB2 storage behavior: `DBIO::DB2::Storage`
- Owns DB2-specific tests from the historical DBIx::Class monolithic test layout

## Migration Notes

- `DBIx::Class::Storage::DBI::DB2` -> `DBIO::DB2::Storage`

When installed, DBIO core can autodetect DB2 DSNs and load the storage
class through `DBIO::Storage::DBI` driver registration.

## Testing

Set environment variables for integration tests:

- `DBIO_TEST_DB2_DSN`
- `DBIO_TEST_DB2_USER`
- `DBIO_TEST_DB2_PASS`
