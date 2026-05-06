package DBIO::DB2::Introspect::Indexes;
# ABSTRACT: Introspect DB2 indexes
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches index metadata via C<SYSCAT.INDEXES> and C<SYSCAT.INDEXCOLUSE>.
Primary-key and unique constraint-backed indexes are included.

=cut

=method fetch

    my $indexes = DBIO::DB2::Introspect::Indexes->fetch($dbh, $schema, $tables);

Returns a hashref keyed by table name, each value a hashref keyed by
index name with: C<index_name>, C<is_unique>, C<columns> (arrayref).

=cut

sub fetch {
  my ($class, $dbh, $schema, $tables) = @_;
  my %indexes;

  my $sth = $dbh->prepare(q{
    SELECT indname, tabname, unique_rule, colcount
    FROM syscat.indexes
    WHERE indschema = ?
    ORDER BY tabname, indname
  });
  $sth->execute($schema);

  while (my $row = $sth->fetchrow_hashref) {
    next unless exists $tables->{ $row->{tabname} };
    my $is_unique = (lc($row->{unique_rule} // '') eq 'Y') ? 1 : 0;
    $indexes{ $row->{tabname} }{ $row->{indname} } = {
      index_name => $row->{indname},
      is_unique  => $is_unique,
      columns    => [],
    };
  }

  # Resolve column names for each index via SYSCAT.INDEXCOLUSE
  my $col_sth = $dbh->prepare(q{
    SELECT indname, tabname, colname, colseq
    FROM syscat.indexcoluse
    WHERE indschema = ?
    ORDER BY tabname, indname, colseq
  });
  $col_sth->execute($schema);

  while (my $row = $col_sth->fetchrow_hashref) {
    next unless exists $indexes{ $row->{tabname} }{ $row->{indname} };
    push @{ $indexes{ $row->{tabname} }{ $row->{indname} }{columns} }, $row->{colname};
  }

  return \%indexes;
}

1;
