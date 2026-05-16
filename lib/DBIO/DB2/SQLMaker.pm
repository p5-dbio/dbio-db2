package DBIO::DB2::SQLMaker;
# ABSTRACT: SQL dialect for IBM DB2
our $VERSION = '0.900000';

use strict;
use warnings;

use base 'DBIO::SQLMaker::ClassicExtensions';

=head1 DESCRIPTION

DB2-specific SQL dialect. Uses C<ROW_NUMBER() OVER()> for DB2 5.4+ and
C<FETCH FIRST n ROWS ONLY> for older versions via the C<apply_limit> method.

=cut

sub apply_limit {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  # DB2 5.4+ uses ROW_NUMBER() OVER() for offset support
  # Older DB2 uses FETCH FIRST n ROWS ONLY (no offset support, requires subquery)
  if ($offset) {
    return $self->_RowNumberOver($sql, $rs_attrs, $rows, $offset);
  }
  return $self->_FetchFirst($sql, $rs_attrs, $rows, $offset);
}

1;