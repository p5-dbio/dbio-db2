package DBIO::DB2::Diff;
# ABSTRACT: Compare two introspected DB2 models
our $VERSION = '0.900000';

use strict;
use warnings;

use base 'DBIO::Diff::Base';

use DBIO::DB2::Diff::Table;
use DBIO::DB2::Diff::Column;
use DBIO::DB2::Diff::Index;

=head1 DESCRIPTION

C<DBIO::DB2::Diff> compares two introspected DB2 models (produced
by L<DBIO::DB2::Introspect>) and emits a list of structured diff
operations that can be rendered to SQL or a human-readable summary.

    my $diff = DBIO::DB2::Diff->new(
        source => $current_model,
        target => $desired_model,
    );

    if ($diff->has_changes) {
        print $diff->as_sql;
        print $diff->summary;
    }

Operations are emitted in dependency order: tables, then columns, then
indexes. Drops come last for each layer.

=cut

sub _build_operations {
  my ($self) = @_;
  my @ops;

  push @ops, DBIO::DB2::Diff::Table->diff(
    $self->source->{tables}, $self->target->{tables},
    $self->target->{columns}, $self->target->{foreign_keys},
  );
  push @ops, DBIO::DB2::Diff::Column->diff(
    $self->source->{columns}, $self->target->{columns},
    $self->source->{tables},  $self->target->{tables},
  );
  push @ops, DBIO::DB2::Diff::Index->diff(
    $self->source->{indexes}, $self->target->{indexes},
  );

  return \@ops;
}

1;
