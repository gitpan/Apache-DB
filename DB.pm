package Apache::DB;

use 5.005;
use strict;
use DynaLoader ();

{
    no strict;
    @ISA = qw(DynaLoader);
    $VERSION = '0.06';
    __PACKAGE__->bootstrap($VERSION);
}

$Apache::Registry::MarkLine = 0;

sub init {
    if(init_debugger()) {
	warn "[notice] Apache::DB initialized in child $$\n";
    }

    1;
}

sub handler {
    my $r = shift;

    init();

    require 'Apache/perl5db.pl';
    $DB::single = 1;

    if (ref $r) {
	$SIG{INT} = \&DB::catch;
	$r->register_cleanup(sub { 
	    $SIG{INT} = \&DB::ApacheSIGINT();
	});
    }

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

=head1 FUNCTIONS

=over 4

=item init

This function initializes the Perl debugger hooks without actually
starting the interactive debugger.  In order to debug a certain piece
of code, this function must be called before the code you wish debug
is compiled.  For example, if you want to insert debugging symbols
into code that is compiled at server startup, but do not care to debug
until request time, call this function from a PerlRequire'd file:

 #where db.pl is simply:
 # use Apache::DB ();
 # Apache::DB->init;
 PerlRequire conf/db.pl

 #where modules are loaded
 PerlRequire conf/init.pl

=item handler

This function will start the interactive debugger.  It will invoke
I<Apache::DB::init> if needed.  Example configuration:

 <Location /my-handler>
  PerlFixupHandler Apache::DB
  SetHandler perl-script
  PerlHandler My::handler
 </Location>

=back

=head1 CAVEATS

=over 4

=item -X

The server must be started with the C<-X> to use Apache::DB.

=item filename/line info

The filename of Apache::Registry scripts is not displayed.

=back

=head1 SEE ALSO

perldebug(1)

=head1 AUTHOR

Doug MacEachern



