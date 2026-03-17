package DBIO::DB2::Storage;
# ABSTRACT: IBM DB2 support for DBIO

use strict;
use warnings;

use base qw/DBIO::Storage::DBI/;
use mro 'c3';

__PACKAGE__->register_driver('DB2' => __PACKAGE__);

__PACKAGE__->datetime_parser_type('DateTime::Format::DB2');
__PACKAGE__->sql_quote_char ('"');

=head1 DESCRIPTION

Storage driver for IBM DB2 databases. Handles autoincrement column retrieval
via C<IDENTITY_VAL_LOCAL()>, selects the appropriate SQL limit dialect
(C<RowNumberOver> for DB2 5.4 and later, C<FetchFirst> for older versions),
queries the server name separator from L<DBI>, and sets the datetime parser
to L<DateTime::Format::DB2>.

=cut

# lazy-default kind of thing
sub sql_name_sep {
  my $self = shift;

  my $v = $self->next::method(@_);

  if (! defined $v and ! @_) {
    $v = $self->next::method($self->_dbh_get_info('SQL_QUALIFIER_NAME_SEPARATOR') || '.');
  }

  return $v;
}

=method sql_name_sep

Returns the name separator character used by this DB2 server (e.g. C<.>),
queried from the server via C<SQL_QUALIFIER_NAME_SEPARATOR> on first access.

=cut

# TODO: DB2 needs a SQLMaker with apply_limit that uses RowNumberOver
# (>= 5.004) or FetchFirst (older) based on server version.

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;

  my $name_sep = $self->sql_name_sep;

  my $sth = $dbh->prepare_cached(
    # An older equivalent of 'VALUES(IDENTITY_VAL_LOCAL())', for compat
    # with ancient DB2 versions. Should work on modern DB2's as well:
    # http://publib.boulder.ibm.com/infocenter/db2luw/v8/topic/com.ibm.db2.udb.doc/admin/r0002369.htm?resultof=%22%73%79%73%64%75%6d%6d%79%31%22%20
    "SELECT IDENTITY_VAL_LOCAL() FROM sysibm${name_sep}sysdummy1",
    {},
    3
  );
  $sth->execute();

  my @res = $sth->fetchrow_array();

  return @res ? $res[0] : undef;
}

=head1 SEE ALSO

=over

=item * L<DBIO::DB2> - DB2 schema component

=item * L<DBIO::Storage::DBI> - Base DBI storage class

=back

=cut

1;
