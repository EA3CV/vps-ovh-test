bless( {
  filter1 => {
    accept => {
      asc => '(($r->[0]>=30000 && $r->[0]<=299999))',
      code => sub { "DUMMY" },
      user => 'on vhf'
    }
  },
  filter2 => {
    accept => {
      user => 'on hf',
      asc => '(($r->[0]>=1800 && $r->[0]<=29999))',
      code => sub { "DUMMY" }
    }
  },
  sort => 'spots',
  name => 'EC5A.pl'
}, 'Filter' )
