package DBIO::DB2;
# ABSTRACT: IBM DB2-specific schema management for DBIO

use strict;
use warnings;

use base 'DBIO';

=head1 SYNOPSIS

    my $schema = MySchema->connect($dsn, $user, $pass);
    # Storage is automatically set to DBIO::DB2::Storage

=head1 DESCRIPTION

This class is a thin L<DBIO> subclass that automatically sets the storage
class to L<DBIO::DB2::Storage> when a connection is established. Load it
into your schema instead of the base L<DBIO> class when connecting to IBM
DB2 databases.

=cut

sub connection {
  my ($self, @info) = @_;
  $self->storage_type('+DBIO::DB2::Storage');
  return $self->next::method(@info);
}

=method connection

    $schema->connection($dsn, $user, $pass, \%attrs);

Sets the storage type to L<DBIO::DB2::Storage> before delegating to the
parent C<connection> method.

=cut

=head1 SEE ALSO

=over

=item * L<DBIO::DB2::Storage> - DB2 storage implementation

=item * L<DBIO> - Base ORM class

=back

=cut

1;
