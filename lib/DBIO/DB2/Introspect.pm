package DBIO::DB2::Introspect;
# ABSTRACT: Introspect a DB2 database via SYSCAT + information_schema
our $VERSION = '0.900000';

use strict;
use warnings;

use base 'DBIO::Introspect::Base';

use DBIO::DB2::Introspect::Tables;
use DBIO::DB2::Introspect::Columns;
use DBIO::DB2::Introspect::Indexes;
use DBIO::DB2::Introspect::ForeignKeys;

=head1 DESCRIPTION

C<DBIO::DB2::Introspect> reads the live state of a DB2 database via
C<SYSCAT> and C<information_schema>, returning a unified model hashref.
It is the source side of the test-deploy-and-compare strategy used by
L<DBIO::DB2::Deploy>.

    my $intro = DBIO::DB2::Introspect->new(dbh => $dbh);
    my $model = $intro->model;

Model shape mirrors L<DBIO::DuckDB::Introspect>:

    {
        tables       => { $name => { ... } },
        columns      => { $table => [ { ... }, ... ] },
        indexes      => { $table => { $name => { ... } } },
        foreign_keys => { $table => [ { ... }, ... ] },
    }

=cut

sub schema { $_[0]->{schema} // 'USER' }

=attr schema

DB2 schema to introspect. Defaults to C<USER> (current user's schema).

=cut

sub _build_model {
  my ($self) = @_;
  my $dbh    = $self->dbh;
  my $schema = $self->schema;

  my $tables  = DBIO::DB2::Introspect::Tables->fetch($dbh, $schema);
  my $columns = DBIO::DB2::Introspect::Columns->fetch($dbh, $schema, $tables);
  my $indexes = DBIO::DB2::Introspect::Indexes->fetch($dbh, $schema, $tables);
  my $fks     = DBIO::DB2::Introspect::ForeignKeys->fetch($dbh, $schema, $tables);

  return {
    tables       => $tables,
    columns      => $columns,
    indexes      => $indexes,
    foreign_keys => $fks,
  };
}

1;
