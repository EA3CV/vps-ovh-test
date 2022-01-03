bless( {
  sort => 'spots',
  name => 'EA2CW-16.pl',
  filter2 => {
    reject => {
      code => sub { "DUMMY" },
      user => 'info ft8',
      asc => '($r->[3]=~m{ft8}i)'
    }
  },
  filter4 => {
    accept => {
      asc => '($r->[11]==14)',
      code => sub { "DUMMY" },
      user => 'by_zone 14'
    }
  },
  filter1 => {
    reject => {
      asc => '($r->[3]=~m{ft4}i)',
      code => sub { "DUMMY" },
      user => 'info ft4'
    }
  }
}, 'Filter' )
