use strict;
use warnings;
use Test::More;

my @modules = qw(
  DBIO::DB2
  DBIO::DB2::Storage
  DBIO::DB2::Loader
);

plan tests => scalar @modules;

for my $mod (@modules) {
  use_ok($mod);
}
