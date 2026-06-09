package DBIO::DB2::Deploy;
# ABSTRACT: Deploy and upgrade DB2 schemas via test-deploy-and-compare

use strict;
use warnings;

use base 'DBIO::Deploy::Base';

# Loaded without importing: only _split_statements is needed, and only here.
use DBIO::DB2::DDL;

=head1 DESCRIPTION

C<DBIO::DB2::Deploy> orchestrates schema deployment and upgrades for
DB2 using the test-deploy-and-compare strategy, parallel to
L<DBIO::SQLite::Deploy> and L<DBIO::PostgreSQL::Deploy>.

For upgrades it:

=over 4

=item 1. Introspects the live database via C<SYSCAT>

=item 2. Deploys the desired schema (from DBIO classes) into a temporary
         schema in the same DB (DB2 requires an existing database; only
         a schema can be throwaway)

=item 3. Introspects the database after deployment

=item 4. Computes the diff between the two models using L<DBIO::DB2::Diff>

=back

C<install>/C<diff>/C<apply>/C<upgrade> and the dbh/schema accessors come
from L<DBIO::Deploy::Base>; this class supplies the three class-name hooks
(L</_ddl_class>, L</_introspect_class>, L</_diff_class>), the
L</_new_introspect> factory that threads a target schema into the
introspector, and the genuinely DB2-specific L</_build_target_model> that
splices the desired schema into a throwaway C<CREATE SCHEMA> block.

    my $deploy = DBIO::DB2::Deploy->new(
        schema => MyApp::DB->connect("dbi:DB2:database=mydb"),
    );
    $deploy->install;                       # fresh
    my $diff = $deploy->diff;              # or step-by-step
    $deploy->apply($diff) if $diff->has_changes;
    $deploy->upgrade;                      # convenience

=cut

# --- class-name hooks for DBIO::Deploy::Base -------------------------------

sub _ddl_class       { 'DBIO::DB2::DDL'        }
sub _introspect_class { 'DBIO::DB2::Introspect' }
sub _diff_class      { 'DBIO::DB2::Diff'       }

=method _new_introspect

    my $intro = $self->_new_introspect($dbh);
    my $intro = $self->_new_introspect($dbh, $schema);

Factory for the introspector. The optional C<$schema> selects the DB2
schema to introspect (defaults to the introspector's own default, used
when introspecting the live C<schema()>).

=cut

sub _new_introspect {
  my ($self, $dbh, $schema) = @_;
  return $self->_introspect_class->new(
    dbh => $dbh,
    (defined $schema ? (schema => $schema) : ()),
  );
}

=method _build_target_model

    my $target_model = $self->_build_target_model;

DB2-specific target model construction:

=over 4

=item 1. C<CREATE SCHEMA _dbio_test_<pid>> in the same database

=item 2. Re-emit the install DDL with every C<CREATE/DROP TABLE/INDEX>
         statement schema-qualified to the test schema (DBIO::DB2::DDL
         does not auto-qualify)

=item 3. Introspect the test schema

=item 4. C<DROP SCHEMA> on the way out, even on failure

=back

Returns the introspected model hashref for the test schema, suitable as
the C<target> of L<DBIO::DB2::Diff>.

=cut

sub _build_target_model {
  my ($self) = @_;
  my $dbh         = $self->_dbh;
  my $test_schema = '_dbio_test_' . $$;

  $dbh->do("CREATE SCHEMA $test_schema");

  my $model = eval {
    my $ddl = $self->_ddl_class->install_ddl($self->schema);
    for my $stmt ($self->_split_qualify_ddl($ddl, $test_schema)) {
      $dbh->do($stmt);
    }
    return $self->_new_introspect($dbh, $test_schema)->model;
  };

  eval { $dbh->do("DROP SCHEMA $test_schema RESTRICT") };
  die $@ if $@ and not $model;

  return $model;
}

# Internal: rewrite CREATE/DROP TABLE/INDEX statements emitted by
# DBIO::DB2::DDL so they target $schema instead of the live one. The
# regex pass is conservative -- DBIO::DB2::DDL emits a known shape --
# so we trade a small fragility for not duplicating DDL rendering.
sub _split_qualify_ddl {
  my ($self, $ddl, $test_schema) = @_;
  require DBIO::SQL::Util;
  my @stmts = DBIO::SQL::Util::_split_statements($ddl);
  for my $stmt (@stmts) {
    next if $stmt =~ /^\s*--/;
    $stmt =~ s/\bCREATE TABLE (\w+)/CREATE TABLE $test_schema.$1/g;
    $stmt =~ s/\bDROP TABLE (\w+)/DROP TABLE $test_schema.$1/g;
    $stmt =~ s/\bCREATE INDEX (\w+) ON (\w+)/CREATE INDEX $test_schema.$1 ON $test_schema.$2/g;
    $stmt =~ s/\bDROP INDEX (\w+)/DROP INDEX $test_schema.$1/g;
  }
  return @stmts;
}

=seealso

=over 4

=item * L<DBIO::DB2> - schema component

=item * L<DBIO::DB2::DDL> - generates DDL

=item * L<DBIO::DB2::Introspect> - reads live database state

=item * L<DBIO::DB2::Diff> - compares two introspected models

=item * L<DBIO::Deploy::Base> - shared install/apply/upgrade orchestration

=back

=cut

1;
