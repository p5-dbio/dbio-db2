package DBIO::DB2::Diff::Column;
# ABSTRACT: Diff operations for DB2 columns
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Column-level diff operations for DB2. DB2 has a reasonably complete
C<ALTER TABLE> repertoire:

=over 4

=item * C<ALTER TABLE ... ADD COLUMN>

=item * C<ALTER TABLE ... DROP COLUMN>

=item * C<ALTER TABLE ... ALTER COLUMN ... SET DATA TYPE>

=item * C<ALTER TABLE ... ALTER COLUMN ... SET NOT NULL / DROP NOT NULL>

=item * C<ALTER TABLE ... ALTER COLUMN ... SET DEFAULT / DROP DEFAULT>

=back

Brand-new tables get their columns inline via L<DBIO::DB2::Diff::Table>
-- this module only sees columns of tables that exist in both models.

=cut

sub new { my ($class, %args) = @_; bless \%args, $class }

sub action      { $_[0]->{action} }
sub table_name  { $_[0]->{table_name} }
sub column_name { $_[0]->{column_name} }
sub old_info    { $_[0]->{old_info} }
sub new_info    { $_[0]->{new_info} }

=method diff

=cut

sub diff {
  my ($class, $source_cols, $target_cols, $source_tables, $target_tables) = @_;
  my @ops;

  for my $table_name (sort keys %$target_cols) {
    next unless exists $source_tables->{$table_name}
             && exists $target_tables->{$table_name};

    my %src_by_name = map { $_->{column_name} => $_ } @{ $source_cols->{$table_name} // [] };
    my %tgt_by_name = map { $_->{column_name} => $_ } @{ $target_cols->{$table_name} // [] };

    for my $col_name (sort keys %tgt_by_name) {
      my $tgt = $tgt_by_name{$col_name};

      if (!exists $src_by_name{$col_name}) {
        push @ops, $class->new(
          action      => 'add',
          table_name  => $table_name,
          column_name => $col_name,
          new_info    => $tgt,
        );
        next;
      }

      my $src = $src_by_name{$col_name};
      my $changed = 0;
      $changed = 1 if _norm_type($src->{data_type}, $src->{size})
                    ne _norm_type($tgt->{data_type}, $tgt->{size});
      $changed = 1 if ($src->{not_null} // 0) != ($tgt->{not_null} // 0);
      $changed = 1 if (defined $src->{default_value} ? $src->{default_value} : '')
                   ne (defined $tgt->{default_value} ? $tgt->{default_value} : '');

      if ($changed) {
        push @ops, $class->new(
          action      => 'alter',
          table_name  => $table_name,
          column_name => $col_name,
          old_info    => $src,
          new_info    => $tgt,
        );
      }
    }

    for my $col_name (sort keys %src_by_name) {
      next if exists $tgt_by_name{$col_name};
      push @ops, $class->new(
        action      => 'drop',
        table_name  => $table_name,
        column_name => $col_name,
        old_info    => $src_by_name{$col_name},
      );
    }
  }

  return @ops;
}

sub _norm_type {
  my ($t, $size) = @_;
  $t = uc($t // '');
  $t .= "($size)" if defined $size && length $size;
  $t =~ s/\s+/ /g;
  return $t;
}

=method as_sql

=cut

sub as_sql {
  my ($self) = @_;

  my $tbl = _quote_ident($self->table_name);
  my $col = _quote_ident($self->column_name);

  if ($self->action eq 'add') {
    my $info = $self->new_info;
    my $type = _db2_column_type($info->{data_type}, $info->{size});
    my $sql  = sprintf 'ALTER TABLE %s ADD COLUMN %s %s', $tbl, $col, $type;
    $sql .= ' NOT NULL' if $info->{not_null};
    if (defined $info->{default_value}) {
      $sql .= " DEFAULT $info->{default_value}";
    }
    return "$sql;";
  }

  if ($self->action eq 'drop') {
    return sprintf 'ALTER TABLE %s DROP COLUMN %s;', $tbl, $col;
  }

  if ($self->action eq 'alter') {
    my $old = $self->old_info;
    my $new = $self->new_info;
    my @stmts;

    if (_norm_type($old->{data_type}, $old->{size})
        ne _norm_type($new->{data_type}, $new->{size})) {
      push @stmts, sprintf 'ALTER TABLE %s ALTER COLUMN %s SET DATA TYPE %s;',
        $tbl, $col, _db2_column_type($new->{data_type}, $new->{size});
    }
    if (($old->{not_null} // 0) != ($new->{not_null} // 0)) {
      push @stmts, $new->{not_null}
        ? sprintf('ALTER TABLE %s ALTER COLUMN %s SET NOT NULL;', $tbl, $col)
        : sprintf('ALTER TABLE %s ALTER COLUMN %s DROP NOT NULL;', $tbl, $col);
    }
    my $old_d = defined $old->{default_value} ? $old->{default_value} : '';
    my $new_d = defined $new->{default_value} ? $new->{default_value} : '';
    if ($old_d ne $new_d) {
      push @stmts, length $new_d
        ? sprintf('ALTER TABLE %s ALTER COLUMN %s SET DEFAULT %s;', $tbl, $col, $new_d)
        : sprintf('ALTER TABLE %s ALTER COLUMN %s DROP DEFAULT;', $tbl, $col);
    }
    return join "\n", @stmts;
  }
}

=method summary

=cut

sub summary {
  my ($self) = @_;
  my $prefix = $self->action eq 'add' ? '+' : $self->action eq 'drop' ? '-' : '~';
  my $type = $self->new_info ? " ($self->{new_info}{data_type})" : '';
  return sprintf '  %scolumn: %s.%s%s', $prefix, $self->table_name, $self->column_name, $type;
}

sub _db2_column_type {
  my ($type, $size) = @_;
  return $type unless defined $size && length $size;
  return "$type($size)";
}

sub _quote_ident {
  my ($name) = @_;
  return $name if $name =~ /^[a-z_][a-z0-9_]*$/i;
  $name =~ s/"/""/g;
  return qq{"$name"};
}

1;
