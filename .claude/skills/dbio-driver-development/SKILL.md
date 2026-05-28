---
name: dbio-driver-development
description: "How to develop a DBIO database driver: registry, storage class, SQLMaker, capabilities, async, Cake integration — developer guide"
user-invocable: false
allowed-tools: Read, Grep, Glob
model: sonnet
---

# DBIO Driver Development

DBIO drivers are separate CPAN distributions binding DBIO to one DB engine.

## Architecture

```
User → DBIO::Schema → Driver Registry (DSN auto-detect)
                    → Storage class → SQLMaker → Capability system
```

| Family | Base | Protocol | Returns |
|--------|------|----------|---------|
| DBI-based (Pg, SQLite, MySQL) | `DBIO::Storage::DBI` | DBD | blocking |
| Async (PostgreSQL::Async) | `DBIO::Storage::Async` | libpq (EV::Pg) | Future |

## Registry & Auto-Detection

Storage classes register at load time:

```perl
package DBIO::PostgreSQL::Storage;
use base 'DBIO::Storage::DBI';

__PACKAGE__->register_driver('Pg' => __PACKAGE__);
```

Flow on first DB op (lazy):
1. `$schema->connect('dbi:Pg:dbname=myapp')`
2. `_determine_driver()` extracts DBD name (`Pg`) from DSN
3. Registry lookup → `DBIO::PostgreSQL::Storage`
4. Reblesses storage object, calls `_rebless()` hook

Manual override via Schema component (skips detection):

```perl
sub connection {
  my $self = shift;
  $self->storage_type('+DBIO::PostgreSQL::Storage');
  return $self->next::method(@_);
}
```

## Driver Structure

Up to 4 components per distribution.

### 1. Schema Component `DBIO::DriverName`

User-facing entry. Loads the storage class.

```perl
package DBIO::DriverName;
# ABSTRACT: DriverName support for DBIO
use base 'DBIO::Schema';

sub connection {
  my $self = shift;
  $self->storage_type('+DBIO::DriverName::Storage');
  return $self->next::method(@_);
}

1;
```

### 2. Storage Class `DBIO::DriverName::Storage` — required

```perl
package DBIO::DriverName::Storage;
# ABSTRACT: Storage for DriverName databases
use base 'DBIO::Storage::DBI';

__PACKAGE__->register_driver('DriverName' => __PACKAGE__);

# Class-data defaults
__PACKAGE__->sql_quote_char('"');
__PACKAGE__->datetime_parser_type('DateTime::Format::DriverName');
__PACKAGE__->sql_maker_class('DBIO::DriverName::SQLMaker');  # if custom

# Tier 1 capability (force on/off)
__PACKAGE__->_use_multicolumn_in(1);
__PACKAGE__->_use_insert_returning(1);

sub _rebless { ... }           # post-detection init
sub last_insert_id { ... }     # auto-increment retrieval
sub sqlt_type { 'DriverName' } # SQL::Translator name

# Optional: savepoints
sub _svp_begin { ... }
sub _svp_release { ... }
sub _svp_rollback { ... }

sub with_deferred_fk_checks { ... }   # FK deferral if supported
sub connect_call_set_encoding { ... } # connect-time setup
sub bind_attribute_by_data_type { ... }

1;
```

### 3. SQLMaker `DBIO::DriverName::SQLMaker` — optional

Override SQL dialect or add operators via `special_ops`.

```perl
package DBIO::DriverName::SQLMaker;
# ABSTRACT: SQL dialect for DriverName
use base 'DBIO::SQLMaker';

sub _lock_select { '' }   # e.g. SQLite has no SELECT ... FOR UPDATE

sub new {
  my $class = shift;
  my %opts = ref $_[0] eq 'HASH' ? %{$_[0]} : @_;
  push @{ $opts{special_ops} }, {
    regex   => qr/^my_op$/i,
    handler => '_where_op_my_op',
  };
  $class->next::method(\%opts);
}

sub _where_op_my_op {
  my ($self, $col, $op, $val) = @_;
  my $quoted = $self->_quote($col);
  return ("$quoted MY_OP ?", $val);
}

1;
```

`special_ops` handler signature: `($self, $col_unquoted, $op, $val)` — quote yourself, return `($sql, @bind)`. The `regex` matches the **operator key** inside `{ op => val }`, not the field.

Examples:

| Driver | SQLMaker adds |
|--------|---------------|
| PostgreSQL | JSONB operators (`@>`, `?`, `@?`, ...) via `special_ops` |
| SQLite | disables `SELECT ... FOR UPDATE` |
| Oracle | `CONNECT BY`, `PRIOR`, identifier shortening, `RETURNING INTO` |

### 4. Result Component `DBIO::DriverName::Result` — optional

DB-specific column/table features for Result classes.

```perl
__PACKAGE__->load_components('DriverName::Result');
```

## Capability System (2-tier)

```perl
# Tier 1: Force (class data set in driver)
__PACKAGE__->_use_insert_returning(1);
__PACKAGE__->_use_multicolumn_in(1);

# Tier 2: Detect at runtime (only if Tier 1 undef)
sub _determine_supports_insert_returning {
  return shift->_server_info->{normalized_dbms_version} >= 8.002 ? 1 : 0;
}
```

Result cached in `_supports_*` (computed once).

```perl
# SQLite: multicolumn IN since 3.14
sub _determine_supports_multicolumn_in {
  ( shift->_server_info->{normalized_dbms_version} < '3.014' ) ? 0 : 1
}
```

## Key Storage Methods

| Method | Purpose | Override? |
|--------|---------|-----------|
| `register_driver()` | auto-detect registry | yes (at load) |
| `_rebless()` | post-detect init hook | optional |
| `last_insert_id()` | autoincrement | usually |
| `sqlt_type()` | SQL::Translator name | yes |
| `_svp_*()` | savepoints | if DB supports |
| `with_deferred_fk_checks()` | defer FK | if DB supports |
| `connect_call_*()` | connect-time setup | optional |
| `bind_attribute_by_data_type()` | DBI bind per type | optional |
| `datetime_parser_type` | DateTime parser | class data |
| `sql_quote_char` | identifier quote | class data |
| `sql_maker_class` | custom SQLMaker | class data |
| `cake_defaults()` | Cake flags (`-Pg` etc) | optional |

### cake_defaults()

Optional. Driver flags for `DBIO::Cake`. Activated by `use DBIO::Cake '-Pg'`.

```perl
sub cake_defaults {
  return (
    inflate_jsonb     => 1,   # jsonb only (leaves json() free)
    inflate_datetime  => 1,
    retrieve_defaults => 1,   # PG generates UUIDs, serials, NOW()
  );
}
```

Cake looks up via `DBIO::Storage::DBI->driver_storage_class($name)`.

Inherited for free: connection/disconnection, SQL gen via SQLMaker, txn_*, insert/update/delete/select, handle caching, prepared statements, DBH attrs.

## AccessBroker

All drivers support AccessBroker. Pass broker to `Schema->connect($broker)` instead of raw DSN. **Full broker interface lives in dbio-core skill.**

Storage detects via `_is_access_broker_connect_info([$broker])` (true if single blessed). Then:
1. `set_access_broker($broker, 'write')` attaches
2. `_current_dbi_connect_info($mode)` → `current_access_broker_connect_info($mode)`
3. Broker returns HASHREF, Storage normalizes
4. Connection proceeds with broker credentials

Rotating creds: storage re-fetches on next connect. Async pools refresh via `_conninfo_provider` calling `current_connect_info_for_storage($storage, $mode)`.

## Async Drivers

Bypass DBI, native async protocol.

| Aspect | DBI | Async |
|--------|-----|-------|
| Base | `DBIO::Storage::DBI` | `DBIO::Storage::Async` |
| Protocol | DBD | native (EV::Pg/libpq, EV::MariaDB) |
| Returns | blocking | Future |
| Connection | single DBH | pool |
| Batching | no | pipeline (multi queries/round-trip) |

Required methods:

```perl
package DBIO::DriverName::Async::Storage;
use base 'DBIO::Storage::Async';

sub future_class { 'Future' }   # event-loop-specific
sub pool { ... }                 # → Future
sub select_async { ... }         # → Future
sub select_single_async { ... }
```

Implemented:
- **DBIO::PostgreSQL::Async** (EV::Pg, libpq): LISTEN/NOTIFY, COPY IN/OUT, pipeline (≤64 in-flight), txn pinning. Sync methods block via `->get` on Future.
- **DBIO::MySQL::Async** (EV::MariaDB): pipeline (≤64), txn pinning, sync via `->get`.

## Distribution Layout

```
DBIO-DriverName/
  lib/DBIO/DriverName.pm           # Schema component
  lib/DBIO/DriverName/Storage.pm   # Storage (required)
  lib/DBIO/DriverName/SQLMaker.pm  # SQL dialect (optional)
  lib/DBIO/DriverName/Result.pm    # Result comp (optional)
  t/00-load.t                      # load tests (no DB)
  t/20-sqlmaker.t                  # SQL gen (no DB)
  t/10-integration.t               # needs live DB
  dist.ini                         # [@DBIO]
  cpanfile
  .proverc                         # -Ilib -I../dbio/lib
```

## Naming

| Part | Pattern | Example |
|------|---------|---------|
| Dist | `DBIO-DriverName` | `DBIO-PostgreSQL` |
| Schema | `DBIO::DriverName` | `DBIO::PostgreSQL` |
| Storage | `DBIO::DriverName::Storage` | `DBIO::PostgreSQL::Storage` |
| SQLMaker | `DBIO::DriverName::SQLMaker` | `DBIO::PostgreSQL::SQLMaker` |
| DBD | `DBD::X` | `DBD::Pg`, `DBD::mysql` |
| Async | `DBIO::DriverName::Async` | `DBIO::PostgreSQL::Async` |

## Testing

- Offline tests (no DB): SQLMaker SQL gen, module loading. Always required.
- Integration tests: live DB via env vars (see driver `CLAUDE.md` or `t/`).
- `.proverc` adds `-I../dbio/lib` automatically.

```perl
# Offline SQLMaker test:
my $schema = DBIO::Test->init_schema(
  no_deploy    => 1,
  storage_type => 'DBIO::DriverName::Storage',
);
is_same_sql_bind( $rs->search(...)->as_query, $expected_sql, \@bind, 'desc' );
```

## Build

```ini
name = DBIO-DriverName

[@DBIO]
```
