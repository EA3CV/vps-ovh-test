#!/usr/bin/perl

require 5.16.1;
use strict;
use warnings;

use IO::Socket::INET;
use IO::Select;
use IO::File;
use Time::HiRes qw(gettimeofday tv_interval);
use Curses 1.06;
use Text::Wrap qw(wrap);
use Cwd qw(abs_path);
use File::Basename;

our $root;
our $is_win;
our $myalias;
our $mycall;
our $clusteraddr;
our $clusterport;
our $maxkhist = 100;
our $maxshist = 500;
our $foreground;
our $background;
our $mycallcolor;
our @colors;
our $data;
our $local_data;
our $macrowin;
our $macro_file = dirname(abs_path($0)) . "/macros.conf";
my $password;

$SIG{'WINCH'} = \&handle_resize;

sub handle_resize {
    endwin();
    doresize();
}

our %fn_lit_map = (
    "\e[11~" => KEY_F(1),
    "\e[12~" => KEY_F(2),
    "\e[13~" => KEY_F(3),
    "\e[14~" => KEY_F(4),
    "\e[15~" => KEY_F(5),
    "\e[17~" => KEY_F(6),
    "\e[18~" => KEY_F(7),
    "\e[19~" => KEY_F(8),
    "\e[20~" => KEY_F(9),
    "\e[21~" => KEY_F(10),
    "\e[23~" => KEY_F(11),
    "\e[24~" => KEY_F(12),
);

# Tabla de macros asignadas a teclas F1-F12
our %macros = (
    KEY_F(1)  => 'sh/dx 100',
    KEY_F(2)  => 'sh/wwv',
    KEY_F(3)  => 'set/qrz',
    KEY_F(4)  => 'sh/users',
    KEY_F(5)  => 'set/nobeep',
    KEY_F(6)  => 'sh/ann',
    KEY_F(7)  => 'musers',
    KEY_F(8)  => 'mnodes',
    KEY_F(9)  => 'summary',
    KEY_F(10) => 'sh/filter',
    KEY_F(11) => 'set/skimmer',
    KEY_F(12) => 'unset/skimmer',
);

load_macros();


$ENV{'TERM'} = 'xterm';

if ($ENV{'TERM'} =~ /(xterm|ansi)/) {
    $foreground = COLOR_WHITE();
    $background = COLOR_BLACK();
    $mycallcolor = A_BOLD|COLOR_PAIR(5);  # Abajo a la derecha después de los ------
    @colors = (
        [ '^[-A-Z0-9]+ de [-A-Z0-9]+ \d\d-\w\w\w-\d\d\d\d \d\d\d\dZ', COLOR_PAIR(0) ],
        [ '^DX de [\-A-Z0-9]+:\s+([57][01]\d\d\d\.|\d\d\d\d\d\d+.)', A_BOLD|COLOR_PAIR(5) ],
        [ '-#', A_BOLD|COLOR_PAIR(1) ],
        [ '^To', COLOR_PAIR(3) ],
        [ '^WX', COLOR_PAIR(3) ],
        [ '^(?:WWV|WCY)', A_BOLD|COLOR_PAIR(4) ],
        [ '^DX', A_BOLD|COLOR_PAIR(2) ],
        [ '^[-A-Z0-9]+ de [-A-Z0-9]+ ', COLOR_PAIR(6) ],
        [ '^(\s+List|Channel|User|Node|Buddy)\b', A_BOLD|COLOR_PAIR(4) ],
        [ '^New mail', A_BOLD|COLOR_PAIR(5) ],
    );
}

sub normalise_call {
    my ($call) = @_;
    $call =~ tr/a-z/A-Z/;
    $call =~ s/[^A-Z0-9\/-]//g;
    return $call;
}

sub ztime {
    my @t = gmtime(shift // time);
    return sprintf("%02d%02dZ", $t[2], $t[1]);  # HHMMZ
}

our $call = "";
our $node = "";
our $conn = undef;
our $lasttime = time;
our @kh = ();
our @sh = ();
our $kpos = 0;
our $inbuf = "";
our $idle = 0;
our $inscroll = 0;

my $top;
my $bot;
my $lines;
my $scr;
my $cols;
my $pagel;
my $has_colors;
our $pos;
our $lth;
our $spos = $pos = $lth = 0;

$SIG{'INT'}  = \&sig_term;
$SIG{'TERM'} = \&sig_term;
$SIG{'HUP'}  = \&sig_term;

$call = uc shift @ARGV if @ARGV;
$clusteraddr = shift @ARGV || '127.0.0.1';
$clusterport = shift @ARGV || 7300;
$myalias = $call;
$mycall  = "DXNODE";
$node = $mycall;

$call = normalise_call($call);
if ($call eq $mycall) {
    print "You cannot connect as your cluster callsign ($mycall)\n";
    exit(0);
}

$Text::Wrap::columns = $cols;
doresize();

my $lastmin = -1;

sub send_later {
    my $msg = shift;
    print $conn "$msg\r\n" if $conn;
}

sub rec_socket {
    my ($line) = @_;
    if ($line =~ /^([A-Z])([^|]*)\|(.*)$/) {
        my ($sort, $incall, $msg) = ($1, $2, $3);
        $call = $incall if $call ne $incall;
        $msg =~ s/[\x00-\x1F]/./g;
        addtotop($sort, $msg);
    } else {
        addtotop('?', $line);
    }
    $lasttime = time;
}

sub wait_for {
    my ($sock, $pattern, $timeout) = @_;
    $timeout //= 10;
    my $sel = IO::Select->new($sock);
    my $buf = '';
    my $start = time;
    while (time() - $start < $timeout) {
        if ($sel->can_read(1)) {
            my $tmp;
            sysread($sock, $tmp, 4096);
            $buf .= $tmp;
            foreach my $line (split /\r?\n/, $buf) {
                addtotop('<', $line);
                return 1 if $line =~ /$pattern/;
            }
        }
    }
    return 0;
}

sub sig_term {
    cease(1, @_);
}

sub cease {
    close($conn) if $conn;
    endwin();
    print @_ if @_;
    exit(0);
}

# Aquí es donde definimos la subrutina `wait_for_prompt`
sub wait_for_prompt {
    my ($sock, $call, $pass) = @_;
    my $sel = IO::Select->new($sock);
    my $buf = '';

    while (1) {
        if ($sel->can_read(1)) {
            my $tmp;
            sysread($sock, $tmp, 4096);
            $buf .= $tmp;
            foreach my $line (split /\r?\n/, $buf) {
                addtotop('<', $line);
                if ($line =~ /login: ?$/i) {
                    print $sock "$call\r\n";
                } elsif ($line =~ /password: ?$/i) {
                    print $sock "$pass\r\n";
                } elsif ($line =~ /dxspider\s+>$/i) {
                    return 1;
                }
            }
        }
    }
}

$conn = IO::Socket::INET->new(PeerAddr => $clusteraddr, PeerPort => $clusterport, Proto => 'tcp')
    or die "No se pudo conectar a $clusteraddr:$clusterport\n";
$conn->autoflush(1);

wait_for_prompt($conn, $call, $password);

send_later("set/page " . ($maxshist - 5));
send_later("set/nobeep");

my $sel = IO::Select->new();
$sel->add($conn);
$sel->add(\*STDIN);

while (1) {
    my $ch = $bot->getch();  # captura teclas aunque no haya I/O pendiente
    rec_stdin($ch) if defined $ch and $ch ne '-1';
    my @ready = $sel->can_read(0.1);
    for my $fh (@ready) {
        if (fileno($fh) == fileno($conn)) {
            my $buf = '';
            my $len = sysread($conn, $buf, 4096);
            if (!$len) {
                cease("Conexión cerrada\n");
            }
            foreach my $line (split /\r?\n/, $buf) {
                rec_socket($line);
            }
        } elsif (fileno($fh) == fileno(STDIN)) {
            my $ch = $bot->getch();
            rec_stdin($ch) if defined $ch && $ch ne '-1';
        }
    }

    $top->refresh() if $top->is_wintouched;
    $bot->refresh();
    my $t = time;
    if ($t > $lasttime) {
        my ($min) = (gmtime($t))[1];
        if ($min != $lastmin) {
            show_screen() unless $inscroll;
            $lastmin = $min;
        }
        $lasttime = $t;
    }
}

sub rec_stdin {
my $r = shift;

# Si empieza con ESC, capturamos secuencia completa
if ($r eq "\e") {
    my $seq = $r;
    for (1..5) {  # máximo 5 caracteres más
        my $next = $bot->getch();
        last unless defined $next && $next ne '-1';
        $seq .= $next;
        last if $next eq '~';  # fin típico de secuencia
    }

    $r = $fn_lit_map{$seq} if exists $fn_lit_map{$seq};

}

    return unless defined $r;
#addtotop('#', "TECLA RECIBIDA: [$r] " . ord($r));

    # Ejecutar macro si se ha pulsado una tecla Fn (F1 a F12)
if ($r =~ /^KEY_F\((\d+)\)$/ || ($r =~ /^\d+$/ && exists $macros{$r})) {
    my $macro = $macros{$r};
    if ($macro && length $macro) {
        $inbuf = $macro;
        $pos = $lth = length($inbuf);
        addtotop(' ', $inbuf);     # lo pinta arriba
        send_later("$inbuf");      # lo envía
        $inbuf = "";
        $pos = $lth = 0;
        $bot->move(1, 0);
        $bot->clrtobot();
        $bot->refresh();
    }
    return;
}

    $r = '0' if !$r;

    if ($r eq "\n" || $r eq "\r") {
        $inbuf = " " unless length $inbuf;
        if ($inbuf =~ /^!/) {
            $inbuf =~ s/^!//;
            for (my $i = $#kh; $i >= 0; $i--) {
                if ($kh[$i] =~ /^$inbuf/) {
                    $inbuf = $kh[$i];
                    last;
                }
            }
        }
        push @kh, $inbuf if length $inbuf;
        shift @kh if @kh > $maxkhist;
        $kpos = @kh;

        if ($inscroll && $spos < @sh) {
            $spos = @sh - $pagel;
            $inscroll = 0;
            show_screen();
        }

        addtotop(' ', $inbuf);
        send_later("$inbuf");
        $inbuf = "";
        $pos = $lth = 0;

    } elsif ($r eq KEY_UP) {
        if ($kpos > 0) {
            $inbuf = $kh[--$kpos];
            $pos = $lth = length $inbuf;
        } else {
            beep();
        }

    } elsif ($r eq KEY_DOWN) {
        if ($kpos < @kh - 1) {
            $inbuf = $kh[++$kpos];
            $pos = $lth = length $inbuf;
        } else {
            beep();
        }

    } elsif ($r eq KEY_LEFT) {
        $pos-- if $pos > 0;

    } elsif ($r eq KEY_RIGHT) {
        $pos++ if $pos < $lth;

    } elsif ($r eq KEY_BACKSPACE || $r eq "\x7f") {
        if ($pos > 0) {
            substr($inbuf, --$pos, 1) = '';
            $lth--;
        } else {
            beep();
        }

    } elsif ($r eq KEY_DC) {
        if ($pos < $lth) {
            substr($inbuf, $pos, 1) = '';
            $lth--;
        } else {
            beep();
        }

    } elsif ($r eq KEY_PPAGE) {
        if ($spos > 0 && @sh > $pagel) {
            $spos -= $pagel + int($pagel / 2);
            $spos = 0 if $spos < 0;
            $inscroll = 1;
            show_screen();
        } else {
            beep();
        }

    } elsif ($r eq KEY_NPAGE) {
        if ($inscroll && $spos < @sh) {
            $spos += int($pagel / 2);
            $spos = @sh - $pagel if $spos > @sh - $pagel;
            show_screen();
            if ($spos >= @sh) {
                $spos = @sh;
                $inscroll = 0;
            }
        } else {
            beep();
        }

    } elsif ($r eq KEY_HOME) {
        $pos = 0;

    } elsif ($r eq KEY_END) {
        $pos = $lth;

    } elsif ($r =~ /^[\x20-\x7E]$/) {
        if ($pos < $lth) {
            my $a = substr($inbuf, 0, $pos);
            my $b = substr($inbuf, $pos);
            $inbuf = $a . $r . $b;
        } else {
            $inbuf .= $r;
        }
        $pos++;
        $lth++;
} elsif (ord($r) == 5) {  # Ctrl-E
    edit_macro();
    $bot->clear();
    $bot->move(1, 0);
    $bot->refresh();
    return;

    } else {
        beep();
    }

    # 🖥 Redibujar línea inferior SIEMPRE después de cada acción
    $bot->move(1, 0);
    $bot->clrtobot();
    $bot->addstr(substr($inbuf, 0, $cols));
    $bot->move(1, $pos > $cols ? $cols : $pos);
    $bot->refresh();
}

sub addtotop {
    my $sort = shift;
    while (@_) {
        my $inbuf = shift;
        my $l = length $inbuf;
        if ($l > $cols) {
            $inbuf =~ s/\s+/ /g;
            if (length $inbuf > $cols) {
                $Text::Wrap::columns = $cols;
                my $token;
                ($token) = $inbuf =~ m!^(.* de [-\w\d/\#]+:?\s+|\w{9}\@\d\d:\d\d:\d\d )!;
                $token ||= ' ' x 19;
                push @sh, split /\n/, wrap('', ' ' x length($token), $inbuf);
            } else {
                push @sh, $inbuf;
            }
        } else {
            push @sh, $inbuf;
        }
    }
    show_screen() unless $inscroll;
}

sub setattr {
    my ($line) = @_;

    return unless $has_colors;

    # Si es spot automático: contiene '-#'
    if ($line =~ /-#/) {
        $top->attrset(A_BOLD | COLOR_PAIR(3));  # automático = cian (o el color que prefieras)
        return;
    }

    # Si es spot humano tipo "DX de ...", analizamos la frecuencia
    if ($line =~ /^DX de [\w\/\-]+:\s+(\d+\.\d+)/) {
        my $freq = $1;
        if ($freq <= 30000.0) {
            $top->attrset(A_BOLD | COLOR_PAIR(5));  # ≤ 30 MHz → amarillo
        } else {
            $top->attrset(A_BOLD | COLOR_PAIR(2));  # > 30 MHz → azul
        }
        return;
    }

    # Si no es DX ni automático, aplicamos las reglas normales
    foreach my $ref (@colors) {
        if ($line =~ m{$$ref[0]}) {
            $top->attrset($$ref[1]);
            last;
        }
    }
}

sub show_screen {
    $top->attrset(COLOR_PAIR(0)) if $has_colors;
my $start;
if ($inscroll) {
    $start = $spos;
    $start = 0 if $start < 0;
    $start = $#sh - $pagel + 1 if $start > $#sh - $pagel + 1;
} else {
    $start = @sh > $pagel ? $#sh - $pagel + 1 : 0;
    $spos = $start;  # actualiza posición si no está en scroll
}

    my $i = 0;

for my $line (@sh[$start .. $#sh]) {
    $top->move($i, 0);
    $top->clrtoeol();             # limpia la línea
    setattr($line);               # aplica el color adecuado
    $top->addstr(substr($line, 0, $cols));
    $top->attrset(COLOR_PAIR(0)); # ← ¡resetea el color!
    $i++;
}

    # Línea inferior con timestamp y otros datos
    my $time = ztime(time);
    my $shl = @sh;
    my $size = $lines . 'x' . $cols . '-';
    my $add = "-$spos-$shl";
    my $c = "$call\@$node";
    my $str = "-" . $time . '-' . ($inscroll ? 'S':'-') . '-' x ($cols - (length($size) + length($c) + length($add) + length($time) + 3));

    $scr->move($lines-4, 0);
    $scr->clrtoeol();
    $scr->addstr($str);
    $scr->addstr($size);
    $scr->attrset($mycallcolor) if $has_colors;
    $scr->addstr($c);
    $scr->attrset(COLOR_PAIR(0)) if $has_colors;
    $scr->addstr($add);

    $top->noutrefresh();  # encola refresco, no lo ejecuta aún
    $scr->noutrefresh();
    doupdate();           # hace un solo refresco de pantalla
}

sub doresize {
    endwin() if $scr;
    initscr();
    raw();
    noecho();
    nonl();

    $lines = LINES;
    $cols  = COLS;
    $has_colors = has_colors();
    start_color() if $has_colors;

    # (Re)definir colores si están disponibles
    if ($has_colors) {
        init_pair(0, COLOR_WHITE,  COLOR_BLACK);   # texto normal
        init_pair(1, COLOR_RED,    COLOR_BLACK);   # errores, F1:...
        init_pair(2, COLOR_BLUE,   COLOR_BLACK);   # DX > 30 MHz
        init_pair(3, COLOR_CYAN,   COLOR_BLACK);   # DX de máquina "-#"
        init_pair(4, COLOR_GREEN,  COLOR_BLACK);   # WWV, WCY
        init_pair(5, COLOR_YELLOW, COLOR_BLACK);   # DX ≤ 30 MHz
        init_pair(6, COLOR_MAGENTA,COLOR_BLACK);   # genéricos
    }

    # Alturas de cada sección
    my $bot_height    = 3;
    my $macros_height = 5;
    my $top_height    = $lines - $bot_height - $macros_height;

    # Pantalla principal
    $scr = new Curses;

    # Ventana superior (scroll principal)
    $top = $scr->subwin($top_height, $cols, 0, 0);
    $top->scrollok(0);
    $top->idlok(1);
    $top->meta(1);
    $top->keypad(1);
    $top->leaveok(1);
    $top->clrtobot();

    # Ventana de macros
    $macrowin = $scr->subwin($macros_height, $cols, $top_height, 0);
    $macrowin->scrollok(0);
    $macrowin->keypad(0);
    $macrowin->nodelay(1);

    # Línea de comandos inferior
    $bot = $scr->subwin($bot_height, $cols, $top_height + $macros_height, 0);
    $bot->scrollok(1);
    $bot->keypad(1);
    $bot->move(1, 0);
    $bot->meta(1);
    $bot->nodelay(1);
    $bot->clrtobot();

    # Colores y scroll
    $mycallcolor = COLOR_PAIR(1) unless $mycallcolor;

    $pagel = $top_height;
    $inscroll = 0;
    $spos = @sh < $pagel ? 0 : @sh - $pagel;

    draw_macros();
    show_screen();
}

sub draw_macros {
    return unless $macrowin;
    $macrowin->clear();

    # Línea de separación (línea 0)
    $macrowin->move(0, 0);
    my $msg = "-- Ctrl-E to edit macros --";
    my $line = '-' x $cols;
    substr($line, int(($cols - length($msg)) / 2), length($msg)) = $msg;
    $macrowin->addstr($line);

    my @fn_keys = (1 .. 12);
    for my $i (0 .. $#fn_keys) {
        my $key = KEY_F($fn_keys[$i]);
        my $cmd = $macros{$key} // '';
        my $prefix = sprintf("F%-2d:", $fn_keys[$i]);

        my $row = int($i / 4) + 1;  # Líneas 1, 2, 3 (después de la barra)
        my $col = ($i % 4) * int($cols / 4);

        $macrowin->move($row, $col);

        # Color rojo para el F1:
        $macrowin->attrset(COLOR_PAIR(1));
        $macrowin->addstr($prefix);

        # Color normal para el resto
        $macrowin->attrset(COLOR_PAIR(0));
        $macrowin->addstr(' ' . substr($cmd, 0, int($cols / 4) - length($prefix) - 2));
    }

    $macrowin->noutrefresh();
    doupdate();
}

sub edit_macro {
    $bot->nodelay(0);
    $bot->clear();
    $bot->clrtobot();
    $bot->move(1, 0);
    $bot->addstr("Editar macro F1-F12 (número 1-12): ");
    $bot->refresh();

    my $key = $bot->getch();
    $bot->nodelay(1);

    return unless defined $key && $key =~ /^[1-9]$|^1[0-2]$/;

    my $fn = int($key);
    $bot->clear();
    $bot->addstr(1, 0, "Nuevo comando para F$fn: ");
    $bot->refresh();

    my $newcmd = '';
    my $pos = 0;
    while (1) {
        my $c = $bot->getch();
        last unless defined $c;

        if ($c eq "\n" || $c eq "\r") {
            last;
        } elsif ($c eq "\x7f" || $c eq KEY_BACKSPACE) {
            if ($pos > 0) {
                $pos--;
                substr($newcmd, $pos, 1) = '';
            }
        } elsif ($c =~ /^[\x20-\x7E]$/) {
            substr($newcmd, $pos, 0) = $c;
            $pos++;
        }
        # Pintamos línea de edición
        $bot->move(1, 0);
        $bot->clrtobot();
        $bot->addstr(1, 0, "Nuevo comando para F$fn: $newcmd");
        $bot->move(1, length("Nuevo comando para F$fn: ") + $pos);
        $bot->refresh();
    }

    $macros{KEY_F($fn)} = $newcmd;
    draw_macros();  # Actualizar pantalla de macros
    save_macros();
}

sub load_macros {
    return unless -f $macro_file;

    open my $fh, '<', $macro_file or return;
    while (<$fh>) {
        chomp;
        next unless /^F(\d{1,2})=(.*)$/;
        my ($num, $cmd) = ($1, $2);
        $macros{KEY_F($num)} = $cmd if $num >= 1 && $num <= 12;
    }
    close $fh;
}

sub save_macros {
    open my $fh, '>', $macro_file or return;
    for my $n (1 .. 12) {
        my $val = $macros{KEY_F($n)} // '';
        print $fh "F$n=$val\n";
    }
    close $fh;
}
