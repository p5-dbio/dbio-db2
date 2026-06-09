use strict;
use warnings;
use Test::More;

# Offline Diff coverage -- no real DB2. Exercises the diff op classes
# directly with mock introspection models (DBIO core convention).
# Models mirror DBIO::DB2::Introspect's shape:
#   { tables, columns, indexes, foreign_keys }

use_ok 'DBIO::DB2::Diff::Table';
use_ok 'DBIO::DB2::Diff::Column';
use_ok 'DBIO::DB2::Diff::Index';
use_ok 'DBIO::DB2::Diff';

# --- Diff::Table create (PK + type mapping) ---
{
  my @ops = DBIO::DB2::Diff::Table->diff(
    {},
    { author => { table_name => 'author' } },
    {
      author => [
        { column_name => 'id',   data_type => 'integer', is_pk => 1, not_null => 0 },
        { column_name => 'name', data_type => 'varchar',  size => 255, not_null => 1 },
      ],
    },
    { author => [] },
  );
  is(scalar @ops, 1, 'one create op');
  is($ops[0]->action, 'create', 'action create');
  is($ops[0]->table_name, 'author', 'table_name');
  my $sql = $ops[0]->as_sql;
  like($sql, qr/CREATE TABLE author/,       'create table');
  like($sql, qr/id INTEGER/,                'id mapped to INTEGER');
  like($sql, qr/name VARCHAR\(255\) NOT NULL/, 'name VARCHAR(255) NOT NULL');
  like($sql, qr/PRIMARY KEY \(id\)/,        'inline PK constraint');
}

# --- Diff::Table create with FK ---
{
  my @ops = DBIO::DB2::Diff::Table->diff(
    {},
    { book => { table_name => 'book' } },
    {
      book => [
        { column_name => 'id',        data_type => 'integer', is_pk => 1 },
        { column_name => 'author_id', data_type => 'integer', not_null => 1 },
      ],
    },
    {
      book => [
        { from_columns => ['author_id'], to_table => 'author', to_columns => ['id'] },
      ],
    },
  );
  like($ops[0]->as_sql,
    qr/FOREIGN KEY \(author_id\) REFERENCES author\(id\)/, 'inline FK');
}

# --- Diff::Table multi-column PK ---
{
  my @ops = DBIO::DB2::Diff::Table->diff(
    {},
    { mtm => { table_name => 'mtm' } },
    {
      mtm => [
        { column_name => 'a', data_type => 'integer', is_pk => 1 },
        { column_name => 'b', data_type => 'integer', is_pk => 1 },
      ],
    },
    {},
  );
  like($ops[0]->as_sql, qr/PRIMARY KEY \(a, b\)/, 'multi-col PK as constraint');
}

# --- Diff::Table drop ---
{
  my @ops = DBIO::DB2::Diff::Table->diff(
    { gone => { table_name => 'gone' } },
    {},
  );
  is($ops[0]->action, 'drop',             'drop op');
  is($ops[0]->as_sql, 'DROP TABLE gone;', 'drop SQL');
  is($ops[0]->summary, '- table: gone',   'drop summary');
}

# --- Diff::Column add ---
{
  my @ops = DBIO::DB2::Diff::Column->diff(
    { t => [ { column_name => 'id', data_type => 'integer' } ] },
    {
      t => [
        { column_name => 'id',    data_type => 'integer' },
        { column_name => 'extra', data_type => 'varchar', not_null => 0 },
      ],
    },
    { t => {} }, { t => {} },
  );
  is(scalar @ops, 1, 'one add op');
  is($ops[0]->action, 'add', 'action add');
  is($ops[0]->as_sql, 'ALTER TABLE t ADD COLUMN extra VARCHAR;', 'add SQL');
}

# --- Diff::Column add NOT NULL with default ---
{
  my @ops = DBIO::DB2::Diff::Column->diff(
    { t => [ { column_name => 'id', data_type => 'integer' } ] },
    {
      t => [
        { column_name => 'id',   data_type => 'integer' },
        { column_name => 'flag', data_type => 'integer', not_null => 1, default_value => '0' },
      ],
    },
    { t => {} }, { t => {} },
  );
  like($ops[0]->as_sql, qr/NOT NULL DEFAULT 0/, 'NOT NULL DEFAULT in add');
}

# --- Diff::Column drop ---
{
  my @ops = DBIO::DB2::Diff::Column->diff(
    {
      t => [
        { column_name => 'id',  data_type => 'integer' },
        { column_name => 'old', data_type => 'varchar' },
      ],
    },
    { t => [ { column_name => 'id', data_type => 'integer' } ] },
    { t => {} }, { t => {} },
  );
  is($ops[0]->action, 'drop', 'drop op');
  is($ops[0]->as_sql, 'ALTER TABLE t DROP COLUMN old;', 'drop column SQL');
}

# --- Diff::Column alter type + NOT NULL (DB2 supports ALTER COLUMN) ---
{
  my @ops = DBIO::DB2::Diff::Column->diff(
    { t => [ { column_name => 'a', data_type => 'integer', not_null => 0 } ] },
    { t => [ { column_name => 'a', data_type => 'varchar', size => 50, not_null => 1 } ] },
    { t => {} }, { t => {} },
  );
  is(scalar @ops, 1,        'one alter op');
  is($ops[0]->action, 'alter', 'action alter');
  my $sql = $ops[0]->as_sql;
  like($sql, qr/ALTER TABLE t ALTER COLUMN a SET DATA TYPE VARCHAR\(50\);/, 'SET DATA TYPE');
  like($sql, qr/ALTER TABLE t ALTER COLUMN a SET NOT NULL;/,               'SET NOT NULL');
}

# --- Diff::Column alter default change + drop NOT NULL ---
{
  my @ops = DBIO::DB2::Diff::Column->diff(
    { t => [ { column_name => 'a', data_type => 'integer', not_null => 1, default_value => '1' } ] },
    { t => [ { column_name => 'a', data_type => 'integer', not_null => 0, default_value => '2' } ] },
    { t => {} }, { t => {} },
  );
  my $sql = $ops[0]->as_sql;
  like($sql, qr/ALTER COLUMN a DROP NOT NULL;/,    'DROP NOT NULL');
  like($sql, qr/ALTER COLUMN a SET DEFAULT 2;/,    'SET DEFAULT');
}

# --- Diff::Column drop DEFAULT ---
{
  my @ops = DBIO::DB2::Diff::Column->diff(
    { t => [ { column_name => 'a', data_type => 'integer', default_value => '5' } ] },
    { t => [ { column_name => 'a', data_type => 'integer' } ] },
    { t => {} }, { t => {} },
  );
  like($ops[0]->as_sql, qr/ALTER COLUMN a DROP DEFAULT;/, 'DROP DEFAULT');
}

# --- Diff::Column skips brand-new tables ---
{
  my @ops = DBIO::DB2::Diff::Column->diff(
    {},
    { newtab => [ { column_name => 'id', data_type => 'integer' } ] },
    {},          # source_tables: newtab absent -> table being created
    { newtab => {} },
  );
  is(scalar @ops, 0, 'no col ops for tables also being created');
}

# --- Diff::Index create ---
{
  my @ops = DBIO::DB2::Diff::Index->diff(
    {},
    {
      t => {
        idx_t_name => {
          index_name => 'idx_t_name',
          is_unique  => 1,
          columns    => ['name'],
        },
      },
    },
  );
  is(scalar @ops, 1, 'one index create');
  is($ops[0]->action, 'create', 'action create');
  is($ops[0]->as_sql, 'CREATE UNIQUE INDEX idx_t_name ON t (name);', 'unique index SQL');
}

# --- Diff::Index create non-unique multi-column ---
{
  my @ops = DBIO::DB2::Diff::Index->diff(
    {},
    {
      t => {
        idx_ab => { index_name => 'idx_ab', is_unique => 0, columns => ['a', 'b'] },
      },
    },
  );
  is($ops[0]->as_sql, 'CREATE INDEX idx_ab ON t (a, b);', 'non-unique multi-col index');
}

# --- Diff::Index drop ---
{
  my @ops = DBIO::DB2::Diff::Index->diff(
    { t => { gone_idx => { index_name => 'gone_idx', columns => ['x'] } } },
    {},
  );
  is($ops[0]->action, 'drop',                 'drop op');
  is($ops[0]->as_sql, 'DROP INDEX gone_idx;', 'drop index SQL');
}

# --- Diff::Index alter (drop+create pair) ---
{
  my @ops = DBIO::DB2::Diff::Index->diff(
    { t => { idx => { index_name => 'idx', columns => ['a'],      is_unique => 0 } } },
    { t => { idx => { index_name => 'idx', columns => ['a', 'b'], is_unique => 0 } } },
  );
  is(scalar @ops, 2,          'changed index produces drop+create');
  is($ops[0]->action, 'drop',   'drop first');
  is($ops[1]->action, 'create', 'create second');
}

# --- Top-level Diff orchestrator: create from empty ---
{
  my $source = {
    tables       => {},
    columns      => {},
    indexes      => {},
    foreign_keys => {},
  };
  my $target = {
    tables  => { author => { table_name => 'author' } },
    columns => {
      author => [ { column_name => 'id', data_type => 'integer', is_pk => 1 } ],
    },
    indexes      => {},
    foreign_keys => {},
  };
  my $diff = DBIO::DB2::Diff->new(source => $source, target => $target);
  ok($diff->has_changes, 'has_changes');
  like($diff->as_sql,  qr/CREATE TABLE author/, 'as_sql contains create');
  like($diff->summary, qr/\+ table: author/,    'summary contains create line');
}

# --- Top-level Diff orchestrator: dependency ordering ---
{
  # Existing table gets a new column; a new table is created; an old index dropped.
  my $source = {
    tables       => { keep => { table_name => 'keep' } },
    columns      => { keep => [ { column_name => 'id', data_type => 'integer' } ] },
    indexes      => { keep => { old_idx => { index_name => 'old_idx', columns => ['id'] } } },
    foreign_keys => {},
  };
  my $target = {
    tables  => {
      keep => { table_name => 'keep' },
      fresh => { table_name => 'fresh' },
    },
    columns => {
      keep  => [
        { column_name => 'id',  data_type => 'integer' },
        { column_name => 'note', data_type => 'varchar' },
      ],
      fresh => [ { column_name => 'id', data_type => 'integer', is_pk => 1 } ],
    },
    indexes      => {},
    foreign_keys => {},
  };
  my $diff = DBIO::DB2::Diff->new(source => $source, target => $target);
  my @ops = @{ $diff->operations };
  # tables first, then columns, then indexes
  isa_ok($ops[0],  'DBIO::DB2::Diff::Table',  'first op is a table op');
  isa_ok($ops[-1], 'DBIO::DB2::Diff::Index',  'last op is an index op');
  like($diff->as_sql, qr/CREATE TABLE fresh/,            'new table created');
  like($diff->as_sql, qr/ADD COLUMN note/,               'column added to existing table');
  like($diff->as_sql, qr/DROP INDEX old_idx/,            'stale index dropped');
}

# --- No changes ---
{
  my $model = {
    tables       => { t => { table_name => 't' } },
    columns      => { t => [ { column_name => 'id', data_type => 'integer' } ] },
    indexes      => {},
    foreign_keys => {},
  };
  my $diff = DBIO::DB2::Diff->new(source => $model, target => $model);
  ok(!$diff->has_changes, 'identical models have no changes');
  is($diff->as_sql,  '', 'empty SQL when no changes');
  is($diff->summary, '', 'empty summary when no changes');
}

done_testing;
