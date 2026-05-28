---
name: dbio-perl-core
description: "DBIO project Perl conventions — module loading (use vs require), cpanfile versioning, CAG patterns, and style. Use before editing any .pm, .pl, or .t in a DBIO distribution."
user-invocable: false
allowed-tools: Read, Grep, Glob
model: sonnet
---

# DBIO Perl Core — Rules

These rules override defaults for all DBIO distributions. Non-negotiable.

## Module Loading

- **`use Module;`** at the top. Always. Every dependency is loaded at compile time.
- **`require` is forbidden as a "lazy optimization".** Never use it to shave startup. If you find yourself writing `require Foo;` inside a method body, stop. Move it to a top-level `use`.
- **`require` is allowed ONLY for true runtime plugin loading** — i.e. the class to load is determined from config/DB at runtime (e.g. `Module::Runtime::use_module($class_from_db)`). If the class name is known at write-time, `use` it.
- **`require` + `->new` directly in a controller action** is a red flag. Fix by hoisting to `use` at the top of the file.

## OOP — DBIO uses CAG, not Moo/Moose

**DBIO Core classes use Class::Accessor::Grouped (CAG).** Drivers may vary — check the specific driver lib/ directory.

### CAG Accessor Groups

DBIO has three accessor groups, each with different semantics:

**`simple`** — Instance data, stored directly in object hash:
```perl
__PACKAGE__->mk_group_accessors(simple => qw(_storage _credentials _read_index));
$self->host(1);  # → set_simple('host', 1)
```

**`inherited`** — Inheritable class data, looked up via mro:
```perl
__PACKAGE__->mk_group_accessors(inherited => qw(sql_name_sep sql_quote_char));
__PACKAGE__->sql_name_sep('.');  # set on subclass, inherited down
```

**`component_class`** — Lazy class loading with special handling:
```perl
__PACKAGE__->mk_group_accessors(component_class => qw(cursor_class resultset_class));
__PACKAGE__->cursor_class('DBIO::Cursor');  # returns class, then ->new called on it
```
DBIO overrides `get_component_class` in `DBIO::Base` to load via `ensure_class_loaded`.

### Constructor Pattern

Pure Perl constructor — **always `bless {}`**, never `bless []`, never Moo::Object:
```perl
sub new {
  my ($class, @args) = @_;
  my $self = bless {}, $class;
  $self->host($args{host}) if exists $args{host};
  return $self;
}
```

### Base Classes

**Correct:**
```perl
use base qw/DBIO::Base Class::Accessor::Grouped/;
```

**Wrong — Role::Tiny for base classes:**
```perl
use Role::Tiny;
with 'SomeRole';  # NO — CAG can't do requires()
```

Use a **base class** (not a role) when building DBIO components.

### load_components — Only for Results

`load_components` is DBIO-specific lazy loading for Result classes only:
```perl
package MyApp::Schema::Result::Artist;
use base qw/DBIO::Core/;
__PACKAGE__->load_components('InflateColumn::DateTime');
```
**Not for Storage, not for AccessBroker.**

## Singular Classes

- **`->instance`** for singleton classes (`MooseX::Singleton`, `MooX::Singleton`). Never call `->new` on a singleton.
- **`->new`** for everything else.

## DBIO CPAN Distributions — cpanfile versioning

DBIO dist.ini uses `[@DBIO]`, which sets `$VERSION` in the repo to the **next, unreleased** version. The repo is ALWAYS ahead of CPAN by one.

**Rules:**

1. **NEVER copy a `$VERSION` from a DBIO distribution repo into a `cpanfile`.** The repo version is not released. `cpanm` cannot install it. Your build will break.
2. **Check `cpanm --info Module::Name`** (or CPAN / MetaCPAN) to get the actual released version.
3. **Every DBIO-authored distribution in cpanfiles must be pinned to the latest released version on CPAN.** Not `'0'`, not some stale number — the current latest. Check with `cpanm --info` before writing the requires line.
4. **Re-check on upgrade.** When bumping, use `cpanm --info` again.

DBIO-authored examples: `DBIO::AccessBroker::*`, `DBIO::Storage::DBI`, `DBIO::SQL::Abstract`, `DBIO::Schema`, `DBIO::Core`.

Quick check:
```bash
cpanm --info Module::Name | tail -1
# → GETTY/DBIO-Module-1.234.tar.gz  ← pin to 1.234
```

## Style / Whitespace

- **2-space indentation.** Not 4. Not tabs.
- **No trailing commas** at the end of multi-line lists.

## File I/O

- **`Path::Tiny`** for every file operation. Not `File::Spec`, not bare `open`. Method-chain: `path(...)->child(...)->slurp_utf8`.

## JSON

- **`JSON::MaybeXS`** always. When encoding, set `canonical => 1, convert_blessed => 1` on the encoder object.

## DBIO Result Classes

- Column defs via **`DBIO::Candy`** or **`DBIx::Class::Candy`** — use `primary_column` / `column` macros, not `__PACKAGE__->add_column(...)`.
- **`keep_storage_value => 1`** on enum and integer columns that shouldn't be inflated/deflated.
- **`\'NOW()'`** (literal scalar ref) for DB-side timestamp defaults.

## Testing

- Core tests MUST use `DBIO::Test::Storage` (fake storage). Never `dbi:SQLite` or any real database.
- Driver tests: `DBIO_TEST_<DRIVER>_DSN`, `DBIO_TEST_<DRIVER>_USER`, `DBIO_TEST_<DRIVER>_PASS`.
- Optional deps skip via `BEGIN { eval { require Moo; 1 } or plan skip_all => 'Moo not installed' }`. List in cpanfile as `suggests`, never `requires`.

## Forbidden / Anti-patterns

- ❌ `require Foo` inside a method to "speed up startup"
- ❌ Using `$VERSION` from a DBIO repo as the cpanfile requirement
- ❌ Moo/Moose for core DBIO classes (use CAG)
- ❌ `bless []` — always `bless {}`
- ❌ 4-space indent in new Perl files
- ❌ `File::Spec` in new code
- ❌ `Data::Dumper` in shipped code (use `DDP` / `Data::Printer` for debug, strip before commit)
- ❌ Role::Tiny for base class composition (use `use base`)

## When in doubt

Grep an existing DBIO driver (`~/dev/perl/dbio-dev/dbio-postgresql/lib/`, `~/dev/perl/dbio-dev/dbio-mysql/lib/`) for how the pattern is used there.
