package Apache::DB;

use 5.005;
use strict;
use DynaLoader ();

{
    no strict;
    @ISA = qw(DynaLoader);
    $VERSION = '0.02';
    __PACKAGE__->bootstrap($VERSION);
}

$Apache::Registry::MarkLine = 0;

sub handler {
    my $r = shift;

    if(init_debugger()) {
	warn "[notice] Apache::DB initialize in child $$\n";
    }

    require 'Apache/perl5db.pl';
    $DB::single = 1;

    $SIG{INT} = \&DB::catch;
    $r->register_cleanup(sub { $SIG{INT} = \&ApacheSIGINT; 0 });

    return 0;
}

1;
__END__

=head1 NAME

Apache::DB - Run the interactive Perl debugger under mod_perl

=head1 SYNOPSIS

 <Location /perl>
  PerlFixupHandler +Apache::DB

  SetHandler perl-script
  PerlHandler +Apache::Registry
  Options +ExecCGI
 </Location>

=head1 DESCRIPTION

Perl ships with a very useful interactive debugger, however, it does not run
"out-of-the-box" in the Apache/mod_perl environment.  Apache::DB makes a few
adjustments so the two will cooperate.

=head1 CAVEATS

=over 4

=item first compile

The first step through when a script or module is first compiled may produce
unexpected results.  It is almost always best to I<continue> the first run
and step through after the script is compiled.

=item -X

The server must be started with the C<-X> to use Apache::DB.

=item preloading

Module and scripts that are compiled during server startup time will not have
debugging hooks enabled.

=item filename/line info

The filename of Apache::Registry scripts is not displayed.

=back

=head1 SEE ALSO

perldebug(1)

=head1 AUTHOR

Doug MacEachern



