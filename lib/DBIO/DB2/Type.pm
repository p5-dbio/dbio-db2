package DBIO::DB2::Type;
# ABSTRACT: DB2 column type utilities

use strict;
use warnings;

use Exporter 'import';

our @EXPORT_OK = qw(_db2_column_type);

sub _db2_column_type {
  my ($info, $size) = @_;

  # Support both hashref form (DDL.pm) and ($type, $size) form (Diff modules)
  if (ref $info eq 'HASH') {
    $size = $info->{size};
    $info = $info->{data_type};
  }

  my $type = $info // 'VARCHAR';

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

  my $mapped = $type_map{ lc $type } // uc $type;
  return $mapped unless defined $size && length $size;
  return "$mapped($size)";
}

1;