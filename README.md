# DBIO::DB2

IBM DB2 database driver for DBIO (fork of DBIx::Class).

## Supports

- desired-state deployment via test-deploy-and-compare (L<DBIO::DB2::Deploy>)
- native introspection (L<DBIO::DB2::Introspect>)
- native diff (L<DBIO::DB2::Diff>)
- native DDL generation (L<DBIO::DB2::DDL>)

## Usage

    package MyApp::DB;
    use base 'DBIO::Schema';
    __PACKAGE__->load_components('DB2');

    my $schema = MyApp::DB->connect('dbi:DB2:database=myapp');

## Requirements

- Perl 5.36+
- DBD::DB2
- DBIO core

## Testing

    prove -l t/

Requires a running DB2 instance. Set C<DBIO_TEST_DB2_DSN>,
C<DBIO_TEST_DB2_USER>, and C<DBIO_TEST_DB2_PASS>.

## See Also

L<DBIO::Introspect::Base>, L<DBIO::Diff::Base>

## Repository

L<https://github.com/p5-dbio/dbio-db2>
