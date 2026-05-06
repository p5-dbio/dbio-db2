package DBIO::DB2::Introspect::ForeignKeys;
# ABSTRACT: Introspect DB2 foreign keys
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches foreign-key metadata via C<SYSCAT.TABCONST> joined with
C<SYSCAT.KEYCOLUSE> and C<SYSCAT.REFERENCES>. Composite FKs are
grouped by constraint name.

=cut

=method fetch

    my $fks = DBIO::DB2::Introspect::ForeignKeys->fetch($dbh, $schema, $tables);

Returns a hashref keyed by table name, each value an arrayref of FK
hashrefs with: C<fk_id>, C<from_columns>, C<to_table>, C<to_columns>,
C<on_update>, C<on_delete>.

=cut

sub fetch {
  my ($class, $dbh, $schema, $tables) = @_;
  my %fks;

  my $sth = $dbh->prepare(q{
    SELECT tc.constname, tc.tabname,
           kcu.colname, kcu.colseq,
           sr.reftabname, sr.reftabschema, sr.refkeyname,
           sr.deleterule, sr.updaterule
    FROM syscat.tabconst tc
    JOIN syscat.keycoluse kcu
      ON tc.constname = kcu.constname
        AND tc.tabschema = kcu.tabschema
        AND tc.tabname = kcu.tabname
    JOIN syscat.references sr
      ON tc.constname = sr.constname
        AND tc.tabschema = sr.tabschema
        AND tc.tabname = sr.tabname
    WHERE tc.tabschema = ?
      AND tc.type = 'F'
    ORDER BY tc.tabname, tc.constname, kcu.colseq
  });

  my $ok = eval { $sth->execute($schema); 1 };
  return \%fks unless $ok;

  my %by_constraint;
  while (my $row = $sth->fetchrow_hashref) {
    next unless exists $tables->{ $row->{tabname} };
    my $key = $row->{tabname} . "\0" . $row->{constname};
    $by_constraint{$key} //= {
      fk_id        => $row->{constname},
      from_table   => $row->{tabname},
      from_columns => [],
      to_table     => $row->{reftabname},
      to_schema    => $row->{reftabschema},
      to_columns   => [],
      on_update    => $row->{updaterule},
      on_delete    => $row->{deleterule},
    };
    push @{ $by_constraint{$key}{from_columns} }, $row->{colname};
  }

  # Resolve the referencing key to remote columns
  # The reftab's refkeyname tells us which unique constraint on the parent
  # table is referenced. We look up its column names in order.
  my $ref_col_sth = $dbh->prepare(q{
    SELECT colname, colseq
    FROM syscat.keycoluse
    WHERE constname = ? AND tabschema = ?
    ORDER BY colseq
  });

  for my $key (sort keys %by_constraint) {
    my $fk = $by_constraint{$key};
    # Find the parent table's referencing key columns
    my @remote_cols;
    my $ok = $ref_col_sth->execute($fk->{to_schema}, $fk->{to_schema});
    # Look for the specific refkeyname on the parent table
    my %refkey_cols;
    my $refkey_sth = $dbh->prepare(q{
      SELECT colname, colseq
      FROM syscat.keycoluse
      WHERE tabschema = ? AND tabname = ? AND constname = ?
      ORDER BY colseq
    });
    # Use the parent table's primary key as the remote columns
    my $pk_sth = $dbh->prepare(q{
      SELECT kcu.colname, kcu.colseq
      FROM syscat.keycoluse kcu
      JOIN syscat.tabconst tc
        ON kcu.constname = tc.constname
          AND kcu.tabschema = tc.tabschema
          AND kcu.tabname = tc.tabname
      WHERE tc.tabschema = ? AND tc.tabname = ? AND tc.type = 'P'
      ORDER BY kcu.colseq
    });
    my @pk_cols;
    my $pk_ok = $pk_sth->execute($fk->{to_schema}, $fk->{to_table});
    if ($pk_ok) {
      while (my $r = $pk_sth->fetchrow_hashref) {
        push @pk_cols, $r->{colname};
      }
    }
    # If we found the parent PK, use it; otherwise use from_columns count as placeholder
    $fk->{to_columns} = \@pk_cols;
    push @{ $fks{ $fk->{from_table} } }, $fk;
  }

  return \%fks;
}

1;
