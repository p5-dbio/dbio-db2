use strict;
use warnings;
use Test::More;

my @modules = qw(
  DBIO::DB2
  DBIO::DB2::Storage
  DBIO::DB2::SQLMaker
  DBIO::DB2::Type
  DBIO::DB2::DDL
  DBIO::DB2::Diff
  DBIO::DB2::Introspect
  DBIO::DB2::Deploy
);

plan tests => scalar @modules;

for my $mod (@modules) {
  use_ok($mod);
}
