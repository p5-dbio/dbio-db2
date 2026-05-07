package DBIO::DB2::Deploy;
# ABSTRACT: Deploy and upgrade DB2 schemas via test-deploy-and-compare
our $VERSION = '0.900000';

use strict;
use warnings;

use DBI;
use DBIO::SQL::Util qw(_split_statements);
use DBIO::DB2::DDL;
use DBIO::DB2::Introspect;
use DBIO::DB2::Diff;

=head1 DESCRIPTION

C<DBIO::DB2::Deploy> orchestrates schema deployment and upgrades for
DB2 using the test-deploy-and-compare strategy, parallel to
L<DBIO::SQLite::Deploy> and L<DBIO::PostgreSQL::Deploy>.

For upgrades it:

=over 4

=item 1. Introspects the live database via C<SYSCAT>

=item 2. Deploys the desired schema (from DBIO classes) into the live DB
         (we use the live DB as the target since DB2 requires an existing DB)

=item 3. Introspects the database after deployment

=item 4. Computes the diff between the two models using L<DBIO::DB2::Diff>

=back

    my $deploy = DBIO::DB2::Deploy->new(
        schema => MyApp::DB->connect("dbi:DB2:database=mydb"),
    );
    $deploy->install;                       # fresh
    my $diff = $deploy->diff;              # or step-by-step
    $deploy->apply($diff) if $diff->has_changes;
    $deploy->upgrade;                      # convenience

=cut

sub new {
  my ($class, %args) = @_;
  bless \%args, $class;
}

sub schema { $_[0]->{schema} }

=attr schema

A connected L<DBIO::Schema> instance using the L<DBIO::DB2> component.
Required.

=cut

=method install

    $deploy->install;

Generates DDL via L<DBIO::DB2::DDL/install_ddl> and executes each
statement against the connected database. Suitable for fresh installs.

=cut

sub install {
  my ($self) = @_;
  my $ddl = DBIO::DB2::DDL->install_ddl($self->schema);
  my $dbh = $self->_dbh;
  for my $stmt (_split_statements($ddl)) {
    $dbh->do($stmt);
  }
  return 1;
}

=method diff

    my $diff = $deploy->diff;

Computes the difference between the live database and the desired state.
Introspects the live database, deploys the desired schema into a test
tablespace, introspects that, and returns a L<DBIO::DB2::Diff> object.

=cut

sub diff {
  my ($self) = @_;

  my $source_model = DBIO::DB2::Introspect->new(dbh => $self->_dbh)->model;

  # For DB2 we deploy to a temporary schema to compare against
  # We use the same DB but into a test schema
  my $test_schema = '_dbio_test_' . $$;
  my $dbh = $self->_dbh;

  # Create test schema
  $dbh->do("CREATE SCHEMA $test_schema");

  my $target_model = $self->_introspect_test_schema($test_schema);

  # Drop test schema
  $dbh->do("DROP SCHEMA $test_schema RESTRICT");

  return DBIO::DB2::Diff->new(
    source => $source_model,
    target => $target_model,
  );
}

sub _introspect_test_schema {
  my ($self, $test_schema) = @_;
  my $dbh = $self->_dbh;

  # Create test tables by executing DDL with schema prefix
  my $ddl = DBIO::DB2::DDL->install_ddl($self->schema);
  my @stmts = _split_statements($ddl);

  for my $stmt (@stmts) {
    # Add schema qualifier to table names
    $stmt =~ s/CREATE TABLE (\w+)/CREATE TABLE $test_schema.$1/g;
    $stmt =~ s/DROP TABLE (\w+)/DROP TABLE $test_schema.$1/g;
    $stmt =~ s/CREATE INDEX (\w+) ON (\w+)/CREATE INDEX $test_schema.$1 ON $test_schema.$2/g;
    $stmt =~ s/DROP INDEX (\w+)/DROP INDEX $test_schema.$1/g;
    $dbh->do($stmt);
  }

  # Now introspect the test schema
  my $intro = DBIO::DB2::Introspect->new(dbh => $dbh, schema => $test_schema);
  return $intro->model;
}

=method apply

    $deploy->apply($diff);

Applies a L<DBIO::DB2::Diff> object by executing each statement from
C<< $diff->as_sql >>. No-op if the diff has no changes.

=cut

sub apply {
  my ($self, $diff) = @_;
  return unless $diff->has_changes;
  my $dbh = $self->_dbh;
  for my $stmt (_split_statements($diff->as_sql)) {
    next if $stmt =~ /^\s*--/;
    $dbh->do($stmt);
  }
  return 1;
}

=method upgrade

    my $diff = $deploy->upgrade;

Convenience: calls L</diff> then L</apply>. Returns the diff object if
changes were applied, or C<undef> if the database was already up to date.

=cut

sub upgrade {
  my ($self) = @_;
  my $diff = $self->diff;
  return unless $diff->has_changes;
  $self->apply($diff);
  return $diff;
}

sub _dbh { $_[0]->schema->storage->dbh }

=seealso

=over 4

=item * L<DBIO::DB2> - schema component

=item * L<DBIO::DB2::DDL> - generates DDL

=item * L<DBIO::DB2::Introspect> - reads live database state

=item * L<DBIO::DB2::Diff> - compares two introspected models

=item * L<DBIO::SQLite::Deploy> - sibling implementation

=back

=cut

1;
