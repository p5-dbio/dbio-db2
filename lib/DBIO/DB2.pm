package DBIO::DB2;
# ABSTRACT: IBM DB2-specific schema management for DBIO

use strict;
use warnings;

use base 'DBIO';

sub connection {
  my ($self, @info) = @_;
  $self->storage_type('+DBIO::DB2::Storage');
  return $self->next::method(@info);
}

1;
