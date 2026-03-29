requires 'perl', '5.020';
requires 'DBIO';
requires 'DBI';
requires 'namespace::clean';
requires 'DateTime::Format::DB2';

on test => sub {
  requires 'Test::More', '0.98';
};
