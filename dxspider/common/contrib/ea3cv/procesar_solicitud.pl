#!/usr/bin/perl

#
#  procesar_solicitud.pl - Procesa la aceptación o rechazo de registros
#
#  Descripción:
#    Este script gestiona la aprobación o el rechazo de solicitudes de registro
#    para el clúster Telnet de EA4URE.
#
#    Si la decisión es ACC (aceptado), se genera una contraseña aleatoria y se
#    escribe un archivo `set/regpass` en los directorios de los nodos DXSpider
#    EA4URE-2, EA4URE-3 y EA4URE-5. A continuación, se envía un correo electrónico
#    al usuario con sus credenciales de acceso.
#
#    Si la decisión es REJ (rechazado), se envía un correo informativo al usuario
#    indicando que su solicitud no ha sido aprobada.
#
#    Todas las acciones realizadas quedan registradas en el fichero
#    `registro_acciones.log` con fecha, hora, indicativo, email, idioma,
#    decisión tomada y estado final del proceso.
#
#  Uso:
#    procesar_solicitud.pl <INDICATIVO> <EMAIL> <E/I> <ACC/REJ>
#
#    Donde:
#      <INDICATIVO> - Indicativo del usuario (ej. EA3XYZ)
#      <EMAIL>      - Dirección de correo del usuario
#      <E/I>        - Idioma del correo: E = Español, I = Inglés
#      <ACC/REJ>    - ACC para aceptar, REJ para rechazar la solicitud
#
#    Ejemplos:
#      ./procesar_solicitud.pl EA3XYZ ea3xyz@example.com E ACC
#      ./procesar_solicitud.pl EA3XYZ ea3xyz@example.com I REJ
#
#  Instalación:
#    Actualmente en: /root/kin/mail/procesar_solicitud.pl
#
#  Requisitos:
#    - Acceso a los volúmenes de los nodos:
#        /root/volumenes/dxspider/nodo-2/cmd_import
#        /root/volumenes/dxspider/nodo-3/cmd_import
#        /root/volumenes/dxspider/nodo-5/cmd_import
#    - Librerías Perl: IO::Socket::SSL, MIME::Base64, File::Path, POSIX
#
#  Configuración:
#    Editar los parámetros SMTP al inicio del script si cambian las credenciales:
#      $smtp_host, $smtp_port, $smtp_user, $smtp_password
#
#  Autor  : Kin EA3CV (ea3cv@cronux.net)
#
#  Versión: 20250526 v1.0
#

use strict;
use warnings;
use utf8;
use File::Path qw(make_path);
use IO::Socket::SSL;
use MIME::Base64;
use POSIX 'strftime';
binmode(STDOUT, ":utf8");

# === CONFIGURACIÓN SMTP ===
my $smtp_host     = 'ure.es';
my $smtp_port     = 465;
my $smtp_user     = 'sysop@ure.es';
my $smtp_password = '@b937-a&TE87s';
my $from_email    = 'sysop@ure.es';

# === PARÁMETROS ===
my ($user, $email, $lang, $decision) = @ARGV;
$user     = uc($user);
$lang     = uc($lang);
$decision = uc($decision);

die "Uso: $0 <usuario> <email> <E/I> <ACC/REJ>\n"
    unless $user && $email && $lang =~ /^[EI]$/ && $decision =~ /^(ACC|REJ)$/;

# === GENERADOR DE CONTRASEÑAS ===
sub generate_password {
    my @chars = ('A'..'Z', 'a'..'z', 0..9, qw/[] . - = % & \$/);
    return join('', map { $chars[int rand @chars] } 1..8);
}

# === REGISTRO ===
sub log_action {
    my ($user, $email, $lang, $decision, $status) = @_;
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    open(my $logfh, '>>', "registro_acciones.log");
    print $logfh "$timestamp - $user - $email - $lang - $decision - $status\n";
    close($logfh);
}

# === TEMPLATES ===
my %templates = (
    ACC => {
        E => {
            subject => "Confirmación de registro en el Clúster Telnet EA4URE de \$user",
            body => "Hola,\n\nSu solicitud de registro ha sido aceptada.\n\nA partir de ahora, puede conectarse al clúster Telnet de ea4ure.com:7300 utilizando las siguientes credenciales:\n\nUsuario:   \$user\nPassword:  \$pass\n\nSi desea cambiar su contraseña, puede hacerlo desde la sesión Telnet ejecutando el comando:\n\nset/password\n\nSi ha solicitado registrar SSID adicionales, podrá usar el mismo password por defecto para todos ellos.\n\nEn caso de utilizar programas que no permiten introducir contraseña automáticamente (como N1MM), puede conectarse con un SSID no registrado.\nNo obstante, recuerde que no podrá enviar spots desde ese usuario, aunque sí podrá mantener acceso en modo lectura.\n\nEsperamos que disfrute del clúster.\n\n73,\nAdministrador del Clúster EA4URE"
        },
        I => {
            subject => "Registration confirmed \$user – EA4URE Telnet Cluster",
            body => "Hello,\n\nYour registration request has been approved.\n\nYou can now connect to the EA4URE Telnet cluster at ea4ure.com:7300 using the following credentials:\n\nUsername:  \$user\nPassword:  \$pass\n\nIf you wish to change your password, you can do so from within the Telnet session by executing the command:\n\nset/password\n\nIf you requested to register additional SSIDs, the same password applies to all of them by default.\n\nIf you're using software that does not support password authentication (such as N1MM), you may connect using an unregistered SSID.\nHowever, please note that you will not be able to send spots unless logged in with a registered username.\n\nWe hope you enjoy the cluster.\n\n73,\nEA4URE Cluster Administrator"
        }
    },
    REJ => {
        E => {
            subject => "Solicitud de registro de \$user en el Clúster Telnet EA4URE",
            body => "Hola,\n\nLamentamos informarle que no ha sido posible verificar su identidad, por lo que su registro en el clúster Telnet EA4URE no ha sido aprobado.\n\nEsto significa que, aunque podrá seguir accediendo al clúster en modo lectura, no podrá enviar spots ni anuncios a través del sistema.\n\nSi cree que se trata de un error o desea aportar más información para completar el proceso de verificación, puede responder a este correo.\n\n73,\nAdministrador del Clúster EA4URE"
        },
        I => {
            subject => "Registration request \$user – EA4URE Telnet Cluster",
            body => "Hello,\n\nWe regret to inform you that we were unable to verify your identity, and therefore your registration for the EA4URE Telnet cluster has not been approved.\n\nThis means that while you will still be able to access the cluster in read-only mode, you will not be able to send spots or announcements.\n\nIf you believe this is a mistake or would like to provide additional information to complete the verification process, feel free to reply to this email.\n\n73,\nEA4URE Cluster Administrator"
        }
    }
);

my $pass = '';
if ($decision eq 'ACC') {
    $pass = generate_password();
    foreach my $nodo (2, 3, 5) {
        my $dir = "/root/volumenes/dxspider/nodo-$nodo/cmd_import";
        make_path($dir) unless -d $dir;
        my $file = "$dir/regpass";
        open(my $fh, '>', $file) or die "No se pudo escribir en $file: $!";
        print $fh "set/regpass $user $pass\n";
        close($fh);
        print "✔️ Actualizado EA4URE-$nodo\n";
    }
}

# Preparar email
my $subject = $templates{$decision}{$lang}->{subject};
my $body    = $templates{$decision}{$lang}->{body};
$subject =~ s/\$user/$user/g;
$body    =~ s/\$user/$user/g;
$body    =~ s/\$pass/$pass/g if $decision eq 'ACC';

# Enviar email manualmente (AUTH LOGIN via SSL 465)
my $sock = IO::Socket::SSL->new(
    PeerHost => $smtp_host,
    PeerPort => $smtp_port,
    SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
    Timeout => 20,
) or die "No se pudo conectar al servidor SMTP\n";

sub smtp_send { my ($cmd) = @_; print $sock "$cmd\r\n"; }
sub smtp_read {
    my $resp = <$sock>;
    return $resp;
}

smtp_read();
smtp_send("EHLO localhost");
while (my $line = <$sock>) { last unless $line =~ /^250\-/; }

smtp_send("AUTH LOGIN"); smtp_read();
smtp_send(encode_base64($smtp_user, '')); smtp_read();
smtp_send(encode_base64($smtp_password, '')); my $auth = smtp_read();
die "Falló autenticación\n" unless $auth =~ /^235/;

smtp_send("MAIL FROM:<$from_email>"); smtp_read();
smtp_send("RCPT TO:<$email>"); smtp_read();
smtp_send("DATA"); smtp_read();

smtp_send("From: $from_email");
smtp_send("To: $email");
smtp_send("Subject: $subject");
smtp_send("Content-Type: text/plain; charset=UTF-8");
smtp_send("");
smtp_send($body);
smtp_send("."); smtp_read();
smtp_send("QUIT"); smtp_read();

log_action($user, $email, $lang, $decision, 'OK');
print "Correo enviado correctamente a $email\n";
