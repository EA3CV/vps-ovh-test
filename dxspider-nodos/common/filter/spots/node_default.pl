bless( {
  sort => 'spots',
  name => 'node_default.pl',
  filter9 => {
    reject => {
      user => 'info db and info wpm and info cq',
      code => sub { "DUMMY" },
      asc => '($r->[3]=~/db/i) && ($r->[3]=~/wpm/i) && ($r->[3]=~/cq/i)'
    }
  }
}, 'Filter' )
