bless( {
  filter1 => {
    accept => {
      user => 'on 7000/7200',
      asc => '(($r->[0]>=7000 && $r->[0]<=7200))',
      code => sub { "DUMMY" }
    }
  },
  name => 'EA1ATH.pl',
  sort => 'spots'
}, 'Filter' )
