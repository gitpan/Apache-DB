package Apache::SmallProf;

use strict;
use vars qw($VERSION @ISA);
use Apache::DB 0.04;
@ISA = qw(DB);

$VERSION = '0.02';

$Apache::Registry::MarkLine = 0;

sub handler {
    my $r = shift;
    my $sdir = $r->dir_config('SmallProfDir') || 'logs/smallprof';
    my $dir = $r->server_root_relative($sdir);
    mkdir $dir, 0755 unless -d $dir;

    unless (-d $dir) {
	die "$dir does not exist: $!";
    }

    (my $uri = $r->uri) =~ s,/,::,g;
    $uri =~ s/^:+//;

    my $db = Apache::SmallProf->new(file => "$dir/$uri", dir => $dir);
    $db->begin;
    $r->register_cleanup(sub { 
	local $DB::profile = 0;
	$db->end;
	#shift->child_terminate;
	0;
    });

    0;
}

package DB;

sub new {
    my $class = shift;
    my $self = bless {@_}, $class;

    Apache::DB->init;

    $self;
}

use strict;
use Time::HiRes qw(time);
$DB::profile = 0; #skip startup profiles

sub begin {
    $DB::trace = 1;

    $DB::drop_zeros = 0;
    $DB::profile = 1;
    if (-e '.smallprof') {
	do '.smallprof';
    }
    $DB::prevf = '';
    $DB::prevl = 0;
    my($diff);
    my($testDB) = sub {
	my($pkg,$filename,$line) = caller;
	$DB::profile || return;
	%DB::packages && !$DB::packages{$pkg} && return;
    };

    # "Null time" compensation code
    $DB::nulltime = 0;
    for (1..100) {
	$DB::start = time;
	&$testDB;
	$DB::done = time;
	$diff = $DB::done - $DB::start;
	$DB::nulltime += $diff;
    }
    $DB::nulltime /= 100;

    $DB::start = time;
}

sub DB {
    my($pkg,$filename,$line) = caller;
    $DB::profile || return;
    %DB::packages && !$DB::packages{$pkg} && return;
    $DB::done = time;

    # Now save the _< array for later reference.  If we don't do this here, 
    # evals which do not define subroutines will disappear.
    no strict 'refs';
    $DB::listings{$filename} = \@{"main::_<$filename"} if 
	defined(@{"main::_<$filename"});
    use strict 'refs';

    my $delta = $DB::done - $DB::start;
    $delta = ($delta > $DB::nulltime) ? $delta - $DB::nulltime : 0;
    $DB::profiles{$filename}->[$line]++;
    $DB::times{$DB::prevf}->[$DB::prevl] += $delta;
    ($DB::prevf, $DB::prevl) = ($filename, $line);

    $DB::start = time;
}

use File::Basename qw(dirname basename);

sub out_file {
    my($self, $fname) = @_;
    if($fname =~ /eval/) {
	$fname = basename($self->{file}) || "smallprof.out";
    } 
    elsif($fname =~ s/^Perl.*Handler subroutine \`(.*)\'$/$1/) {
    }
    else {
	for (keys %INC) {
	    if($fname =~ s,.*$_,$_,) {
		$fname =~ s,/+,::,g;
		last;
	    }
	}
	if($fname =~ m,/,) {
	    $fname = basename($fname);
	}
    }
    return "$self->{dir}/$fname.prof";
}

sub spad {
    (" " x (10 - length($_[0])))
}

sub end {
    my $self = shift;

    # Get time on last line executed.
    $DB::done = time;
    my $delta = $DB::done - $DB::start;
    $delta = ($delta > $DB::nulltime) ? $delta - $DB::nulltime : 0;
    $DB::times{$DB::prevf}->[$DB::prevl] += $delta;

    my($i, $stat, $time, $line, $file);

    my %cnt = ();
    foreach $file (sort keys %DB::profiles) {
	my $out = $self->out_file($file);
	open(OUT, ">$out") or die "can't open $out $!";
	if (defined($DB::listings{$file})) {
	    $i = -1;
	    foreach $line (@{$DB::listings{$file}}) {
		++$i or next;
		chomp $line;
		$stat = $DB::profiles{$file}->[$i] || 0 
		    or !$DB::drop_zeros or next;
		$time = defined($DB::times{$file}->[$i]) ?
		    $DB::times{$file}->[$i] : 0;
		printf OUT "%s%d %.6f%s%d:%s\n", 
		spad($stat), $stat, $time, spad($i), $i, $line;
	    }
	} 
	else {
	    $line = "The code for $file is not in the symbol table.";
	    warn $line;
	    for ($i=1; $i <= $#{$DB::profiles{$file}}; $i++) {
		next unless 
		    ($stat = $DB::profiles{$file}->[$i] || 0 
		     or !$DB::drop_zeros);
		$time = defined($DB::times{$file}->[$i]) ?
		    $DB::times{$file}->[$i] : 0;
		printf OUT "%s%d %.6f%s%d:%s\n", 
		spad($stat), $stat, $time, spad($i), $i, $line;
	    } 
	}
	close OUT;
    }
}

sub sub {
    no strict 'refs';
    local $^W = 0;

    goto &$DB::sub unless $DB::profile;
    $DB::sub{$DB::sub} =~ /(.*):(\d+)-/;
    $DB::profiles{$1}->[$2]++ if defined $2;
    $DB::listings{$1} = \@{"main::_<$1"} if defined(@{"main::_<$1"});
    if(defined &$DB::sub) {
	&$DB::sub;
    }
    else {
	warn "can't call `$DB::sub'\n";
    }
}

1;
__END__

=head1 NAME

Apache::SmallProf - Hook Devel::SmallProf into mod_perl

=head1 SYNOPSIS

 <IfDefine PERLSMALLPROF>

    <Perl>
     use Apache::DB ();
     Apache::DB->init;
    </Perl>

    <Location />
     PerlFixupHandler Apache::SmallProf
    </Location>
 </IfDefine>

=head1 DESCRIPTION

Devel::SmallProf is a line-by-line code profiler.  Apache::SmallProf provides
this profiler in the mod_perl environment.  Profiles are written to
I<ServerRoot/logs/smallprof> and unlike I<Devel::SmallProf> the profile is
split into several files based on package name.

The I<Devel::SmallProf> documentation explains how to analyize the profiles,
e.g.:

 % sort -nrk 2  logs/smallprof/CGI.pm.prof | more
         1 0.104736       629:     eval "package $pack; $$auto";
         2 0.002831       647:       eval "package $pack; $code";
         5 0.002002       259:    return $self->all_parameters unless @p;
         5 0.000867       258:    my($self,@p) = self_or_default(@_);
         ...

=head1 SEE ALSO

Devel::SmallProf(3), Apache::DB(3), Apache::DProf(3)

=head1 AUTHOR

Doug MacEachern
