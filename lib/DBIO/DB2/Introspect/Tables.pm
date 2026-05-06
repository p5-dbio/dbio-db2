package DBIO::DB2::Introspect::Tables;
# ABSTRACT: Introspect DB2 tables and views
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches DB2 table and view metadata via C<SYSCAT.TABLES>.

=cut

=method fetch

    my $tables = DBIO::DB2::Introspect::Tables->fetch($dbh, $schema);

Returns a hashref keyed by table name. Each value has: C<table_name>,
C<kind> (C<table> or C<view>), C<schema>.

=cut

sub fetch {
  my ($class, $dbh, $schema) = @_;

  my $sth = $dbh->prepare(q{
    SELECT tabname, tabtype, tabschema
    FROM syscat.tables
    WHERE tabschema = ?
      AND tabname NOT LIKE 'EX%'
    ORDER BY tabname
  });
  $sth->execute($schema);

  my %tables;
  while (my $row = $sth->fetchrow_hashref) {
    my $type = lc($row->{tabtype} // '');
    my $kind = $type =~ /view/ ? 'view' : 'table';
    $tables{ $row->{tabname} } = {
      table_name => $row->{tabname},
      kind       => $kind,
      schema     => $row->{tabschema},
    };
  }

  return \%tables;
}

1;
