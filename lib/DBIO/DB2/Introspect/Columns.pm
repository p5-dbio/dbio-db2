package DBIO::DB2::Introspect::Columns;
# ABSTRACT: Introspect DB2 columns
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches column metadata via C<SYSCAT.COLUMNS>. Primary-key membership
is determined via C<SYSCAT.KEYCOLUSE> joined with C<SYSCAT.TABCONST>.

=cut

=method fetch

    my $columns = DBIO::DB2::Introspect::Columns->fetch($dbh, $schema, $tables);

Given the tables hashref from L<DBIO::DB2::Introspect::Tables>,
returns a hashref keyed by table name. Each value is an arrayref of
column hashrefs in C<COLNO> order with keys:
C<column_name>, C<data_type>, C<not_null>, C<default_value>,
C<is_pk>, C<pk_position>, C<size>.

=cut

sub fetch {
  my ($class, $dbh, $schema, $tables) = @_;
  my %columns;

  # Pull all columns for the schema in one go.
  my $col_sth = $dbh->prepare(q{
    SELECT colname, tabname, colno, typename, nullable, default,
           length, scale
    FROM syscat.columns
    WHERE tabschema = ?
    ORDER BY tabname, colno
  });
  $col_sth->execute($schema);

  while (my $row = $col_sth->fetchrow_hashref) {
    next unless exists $tables->{ $row->{tabname} };
    my $type = $row->{typename};
    my $size = $row->{length};
    $size .= ",$row->{scale}" if defined $row->{scale} && $row->{scale} > 0;
    push @{ $columns{ $row->{tabname} } }, {
      column_name   => $row->{colname},
      data_type     => $type,
      not_null      => (lc($row->{nullable} // 'Y') eq 'N') ? 1 : 0,
      default_value => $row->{default},
      is_pk         => 0,
      pk_position   => 0,
      size          => $size // undef,
    };
  }

  # Primary-key membership.
  my $pk_sth = $dbh->prepare(q{
    SELECT kcu.tabname, kcu.colname, kcu.colseq
    FROM syscat.keycoluse kcu
    JOIN syscat.tabconst tc
      ON kcu.constname = tc.constname
        AND kcu.tabschema = tc.tabschema
        AND kcu.tabname = tc.tabname
    WHERE tc.tabschema = ?
      AND tc.type = 'P'
    ORDER BY kcu.tabname, kcu.colseq
  });
  $pk_sth->execute($schema);

  while (my $row = $pk_sth->fetchrow_hashref) {
    my $list = $columns{ $row->{tabname} } or next;
    for my $col (@$list) {
      if ($col->{column_name} eq $row->{colname}) {
        $col->{is_pk}       = 1;
        $col->{pk_position} = $row->{colseq} || 1;
        last;
      }
    }
  }

  return \%columns;
}

1;
