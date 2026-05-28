---
name: dbio-perl-release
description: "Load when dist.ini contains [@DBIO] — DBIO bundle options, version strategy, PodWeaver conventions, dzil release workflow"
user-invocable: false
allowed-tools: Read, Grep, Glob
model: sonnet
---

DBIO uses `[@DBIO]` from `Dist::Zilla::PluginBundle::DBIO`. NOT `[@Author::GETTY]`.

## dist.ini

Drivers:
```ini
name = DBIO-DriverName

[@DBIO]
```
Bundle sets `author`, `license`, `copyright_holder`. No version/copyright_year.

Core (`core = 1`):
```ini
name = DBIO
copyright_year = 2005

[@DBIO]
core = 1
```
VersionFromMainModule, MakeMaker::Awesome, ExecDir; no GithubMeta.

## Version

- Drivers: git tags via `@Git::VersionManager` (first_version = 0.900000)
- Core: `$VERSION` in lib/DBIO.pm via `[VersionFromMainModule]`
Target: `1.000000` when stable.

## PodWeaver

`# ABSTRACT:` required on every .pm. `=attr name` after `has` → ATTRIBUTES. `=method name` after `sub` → METHODS. Omit NAME, VERSION, AUTHORS, COPYRIGHT (auto-generated). POD inline. Cross-refs: `L<DBIO::Module>`.

## Dependencies

In `cpanfile`, not dist.ini. Bundle uses `[Prereqs::FromCPANfile]`.

## Release

```bash
dzil build && dzil test && dzil release
```
