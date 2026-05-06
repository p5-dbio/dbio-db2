package DBIO::DB2::DDL;
# ABSTRACT: Generate DB2 DDL from DBIO Result classes
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

C<DBIO::DB2::DDL> generates a DB2 DDL script from a L<DBIO::Schema>
class hierarchy. It is the desired-state side of the test-deploy-and-
compare strategy used by L<DBIO::DB2::Deploy>.

    my $ddl = DBIO::DB2::DDL->install_ddl($schema_class_or_instance);

The output is plain SQL, suitable for executing one statement at a time
against a fresh DB2 database. Emits C<CREATE TABLE> (inline columns,
primary key, unique, foreign keys) and C<CREATE INDEX>.

=cut

=method install_ddl

    my $ddl = DBIO::DB2::DDL->install_ddl($schema);

Returns the full installation DDL as a single string.

=cut

sub install_ddl {
  my ($class, $schema) = @_;

  my @stmts;
  my %seen_table;

  for my $source_name (_topo_sort_sources($schema)) {
    my $source       = $schema->source($source_name);
    my $result_class = $source->result_class;
    my $table_name   = _resolve_table_name($source->name);

    next unless defined $table_name;
    next if $seen_table{$table_name}++;

    my @col_defs;
    my %is_pk;
    my @pk_cols = $source->primary_columns;
    @is_pk{@pk_cols} = (1) x @pk_cols;

    for my $col_name ($source->columns) {
      my $info = $source->column_info($col_name);
      my $type = _db2_column_type($info);

      my $def = sprintf '  %s %s', _quote_ident($col_name), $type;

      $def .= ' NOT NULL' if defined $info->{is_nullable} && !$info->{is_nullable};

      if ($info->{is_auto_increment}) {
        # DB2 uses GENERATED ALWAYS AS IDENTITY for auto-increment
        $def .= ' GENERATED ALWAYS AS IDENTITY (START WITH 1, INCREMENT BY 1)';
      }
      elsif (defined $info->{default_value}) {
        my $dv = $info->{default_value};
        if (ref $dv eq 'SCALAR') {
          $def .= " DEFAULT $$dv";
        } else {
          $def .= " DEFAULT '$dv'";
        }
      }

      push @col_defs, $def;
    }

    if (@pk_cols) {
      push @col_defs, sprintf '  PRIMARY KEY (%s)',
        join(', ', map { _quote_ident($_) } @pk_cols);
    }

    push @stmts, sprintf "CREATE TABLE %s (\n%s\n);",
      _quote_ident($table_name), join(",\n", @col_defs);

    # Standalone indexes
    if ($result_class->can('db2_indexes')) {
      my $indexes = $result_class->db2_indexes;
      for my $idx_name (sort keys %$indexes) {
        my $idx = $indexes->{$idx_name};
        my $unique = $idx->{unique} ? 'UNIQUE ' : '';
        my $columns = join ', ',
          map { _quote_ident($_) } @{ $idx->{columns} // [] };
        my $sql = sprintf 'CREATE %sINDEX %s ON %s (%s)',
          $unique, _quote_ident($idx_name),
          _quote_ident($table_name), $columns;
        push @stmts, "$sql;";
      }
    }
  }

  return join "\n\n", @stmts;
}

sub _resolve_table_name {
  my ($name) = @_;
  return $name unless ref $name;
  return undef unless ref $name eq 'SCALAR';
  my $v = $$name;
  return undef unless defined $v;
  return $v if $v =~ /\A\w+\z/;
  return undef;
}

sub _topo_sort_sources {
  my ($schema) = @_;

  my %deps;
  my %by_table;
  my @sources = sort $schema->sources;

  for my $name (@sources) {
    my $s = $schema->source($name);
    my $t = _resolve_table_name($s->name);
    next unless defined $t;
    $by_table{$t} //= $name;
  }

  for my $name (@sources) {
    my $s = $schema->source($name);
    next unless defined _resolve_table_name($s->name);
    $deps{$name} ||= {};
    for my $rel ($s->relationships) {
      my $info = $s->relationship_info($rel);
      next unless $info && $info->{attrs}
               && $info->{attrs}{is_foreign_key_constraint};
      my $foreign = $info->{class};
      my $fs = eval { $schema->source($foreign) }
            // eval { $schema->source($foreign =~ s/.*:://r) };
      next unless $fs;
      my $ft = _resolve_table_name($fs->name);
      next unless defined $ft;
      my $owner = $by_table{$ft};
      next unless $owner;
      next if $owner eq $name;
      $deps{$name}{$owner} = 1;
    }
  }

  my @out;
  my %visited;
  my $visit;
  $visit = sub {
    my ($n) = @_;
    return if $visited{$n}++;
    for my $d (sort keys %{ $deps{$n} || {} }) {
      $visit->($d);
    }
    push @out, $n;
  };
  $visit->($_) for @sources;
  return @out;
}

sub _db2_column_type {
  my ($info) = @_;
  my $type = $info->{data_type} // 'VARCHAR';

  return $type if $type =~ /\(.+\)$/;

  my %type_map = (
    tinyint   => 'SMALLINT',
    smallint  => 'SMALLINT',
    int       => 'INTEGER',
    integer   => 'INTEGER',
    bigint    => 'BIGINT',
    serial    => 'INTEGER',
    bigserial => 'BIGINT',
    real      => 'REAL',
    float     => 'FLOAT',
    double    => 'DOUBLE PRECISION',
    'double precision' => 'DOUBLE PRECISION',
    numeric   => 'DECIMAL',
    decimal   => 'DECIMAL',
    text      => 'VARCHAR',
    varchar   => 'VARCHAR',
    char      => 'CHAR',
    clob      => 'CLOB',
    boolean   => 'SMALLINT',
    bool      => 'SMALLINT',
    blob      => 'BLOB',
    binary    => 'BLOB',
    varbinary => 'VARBINARY',
    date      => 'DATE',
    time      => 'TIME',
    datetime  => 'TIMESTAMP',
    timestamp => 'TIMESTAMP',
    timestamptz => 'TIMESTAMP',
    'timestamp with time zone' => 'TIMESTAMP',
    interval  => 'INTERVAL',
    uuid      => 'CHAR(16)',
    json      => 'VARCHAR',
  );

  return $type_map{ lc $type } // uc $type;
}

sub _quote_ident {
  my ($name) = @_;
  return $name if $name =~ /^[a-z_][a-z0-9_]*$/i;
  $name =~ s/"/""/g;
  return qq{"$name"};
}

1;
