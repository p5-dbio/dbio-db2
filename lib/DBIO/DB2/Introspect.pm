package DBIO::DB2::Introspect;
# ABSTRACT: Introspect a DB2 database via SYSCAT + information_schema

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

=head1 NORMALIZED CONTRACT

The methods below implement the L<DBIO::Introspect::Base> contract used by
L<DBIO::Generate> as a high-fidelity source. They are thin reads of the native
model built by C<_build_model> -- no extra database round-trips. Table keys are
the bare DB2 table names (the keys of C<< model->{tables} >>).

=method table_keys

=cut

sub table_keys {
  my ($self) = @_;
  return [ sort keys %{ $self->model->{tables} || {} } ];
}

=method table_columns

=cut

sub table_columns {
  my ($self, $table_key) = @_;
  # model columns are fetched ORDER BY colno, so array order is column order
  return [ map { $_->{column_name} } @{ $self->model->{columns}{$table_key} || [] } ];
}

=method table_columns_info

=cut

sub table_columns_info {
  my ($self, $table_key) = @_;
  my %info;

  for my $col (@{ $self->model->{columns}{$table_key} || [] }) {
    my $name  = $col->{column_name};
    my $entry = {
      data_type   => $col->{data_type},
      is_nullable => $col->{not_null} ? 0 : 1,
    };
    $entry->{size} = $col->{size} if defined $col->{size};
    $entry->{default_value} = $col->{default_value}
      if defined $col->{default_value};
    $info{$name} = $entry;
  }

  return \%info;
}

=method table_pk_info

=cut

sub table_pk_info {
  my ($self, $table_key) = @_;
  return [
    map  { $_->{column_name} }
    sort { $a->{pk_position} <=> $b->{pk_position} }
    grep { $_->{is_pk} }
    @{ $self->model->{columns}{$table_key} || [] }
  ];
}

=method table_uniq_info

Unique constraint-backed indexes, excluding the one that backs the primary key
(identified by matching the PK column set).

=cut

sub table_uniq_info {
  my ($self, $table_key) = @_;

  my $pk_key  = join "\0", @{ $self->table_pk_info($table_key) };
  my $indexes = $self->model->{indexes}{$table_key} || {};
  my @uniqs;

  for my $name (sort keys %$indexes) {
    my $index = $indexes->{$name};
    next unless $index->{is_unique};
    my @cols = @{ $index->{columns} || [] };
    next unless @cols;
    next if join("\0", @cols) eq $pk_key;   # this is the PK index, not a uniq
    push @uniqs, [ $name => [ @cols ] ];
  }

  return \@uniqs;
}

=method table_fk_info

=cut

sub table_fk_info {
  my ($self, $table_key) = @_;

  return [
    map {
      {
        _constraint_name => $_->{fk_id},
        local_columns    => [ @{ $_->{from_columns} || [] } ],
        remote_columns   => [ @{ $_->{to_columns}   || [] } ],
        remote_schema    => $_->{to_schema},
        remote_table     => $_->{to_table},
        attrs            => {
          on_delete => $_->{on_delete},
          on_update => $_->{on_update},
        },
      }
    } @{ $self->model->{foreign_keys}{$table_key} || [] }
  ];
}

=method table_is_view

=cut

sub table_is_view {
  my ($self, $table_key) = @_;
  my $table = $self->model->{tables}{$table_key} || {};
  return ($table->{kind} || '') eq 'view' ? 1 : 0;
}

1;
