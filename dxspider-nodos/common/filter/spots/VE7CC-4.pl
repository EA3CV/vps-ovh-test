bless( {
  filter7 => {
    reject => {
      user => ' not by_dxcc ve',
      asc => '! ($r->[6]==197)',
      code => sub { "DUMMY" }
    }
  },
  name => 'VE7CC-4.pl',
  sort => 'spots'
}, 'Filter' )
