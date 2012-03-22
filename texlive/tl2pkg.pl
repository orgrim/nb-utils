#!/usr/pkg/bin/perl

#
# Copyright 2012 Nicolas Thauvin. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#
# This a helper script to create Texlive packages in pkgsrc.
#
# We use the text database of Texlive package available here:
# http://mirrors.ctan.org/systems/texlive/tlnet/tlpkg/texlive.tlpdb
#

use strict;
use Getopt::Long;
use File::Path qw(make_path);

use Data::Dumper;

my $pkgfind = '/usr/pkg/bin/pkgfind';
my $tlpdb;
my $report;
my $pkgsrc = '/usr/pkgsrc';
my $inspect;
my $help;
my $tetex;
my $output = '';
my $generate;

sub usage {
    print qq{usage: $0 [options] [tlpkg [...]]
options:
    -R, --report         tell us how much work is necessary
    -T, --tetex          find missing pkg to remove teTeX3-texmf
    -I, --inspect        search TLPKG in DB
    -G, --generate       generate reported packages

    -s, --pkgsrc=DIR     pkgsrc directory ("$pkgsrc")
    -d, --tlpdb=FILE     path to the tkpdb file

    -o, --output=DIR     generate packages in DIR

    -h, --help           print help

};
    exit 1;
}

GetOptions("report|R" => \$report,
	   "tetex|T" => \$tetex,
	   "inspect|I"  => \$inspect,
	   "generate|G" => \$generate,
	   "pkgsrc|s=s" => \$pkgsrc,
	   "tlpdb|d=s" => \$tlpdb,
	   "output|o=s" => \$output,
	   "help" => \$help) or die usage();
usage() if $help;

my @tlpkgs = @ARGV;

# The tlpdb file is mandatory
unless ($tlpdb) {
    print "-d is required\n";
    usage();
}

open(TLPDB, $tlpdb) or die "Could not open $tlpdb: $!\n";

# besoin:
# - recherche d'un package
# - parcours du fichier, renvoi l'entrée suivante
# - vérifier par rapport à l'archive tlnet
# - trouver un package dans pkgsrc
# - vérifier si une maj est dispo dans pkgsrc
# - générer un pkg
# - générer un diff pour une update
# - générer un rapport

# cas des binaires : vérifier si le binaire est dans pkgsrc (aller jusque la PLIST)

sub get_next_entry {

    my $entry = {};
    my $in = 0;
    my $where;
    while (<TLPDB>) {
	chomp;

	# an empty line marks the end of the entry
	return $entry if (m/^$/ && $in);

	if (m/^name (\S+)$/) {
	    $entry->{name} = $1;
	    $in = 1;
	    next;
	}

	# unique keyword goes directly into the hash value
	foreach my $kw (qw{name category revision shortdesc relocated catalogue-ctan catalogue-date catalogue-license catalogue-version}) {
	    if (m/^${kw} (.+)$/) {
		$entry->{$kw} = $1;
	    }
	}

	# multiple keyword content is appended to a list ref in hash value
	foreach my $kw (qw{longdesc depend execute}) {
	    if (m/^${kw} (.+)$/) {
		$entry->{$kw} = [] unless defined $entry->{$kw};
		push @{$entry->{$kw}}, $1;
	    }
	}

	# prepare lists for keyword than open blocks
	foreach my $kw (qw{binfiles docfiles runfiles srcfiles}) {
	    if (m/^${kw}/) {
		$entry->{$kw} = [] unless defined $entry->{$kw};
		$where = $kw;
	    }
	}

	# append the block line to the current block keyword list
	if (m/^ (\S+)$/) {
	    push @{$entry->{$where}}, $1;
	    next;
	}
    }

    # If this point is reached, then something went wrong
    return;
}

sub search_entry {
    my $tlpkg = shift;
    return unless defined $tlpkg;

    # rewind the tlpdb filehandle. Save the position in the file
    my $init_pos = tell(TLPDB);
    seek(TLPDB, 0, 0);

    # search the file
    my $pos = $init_pos;
    while (<TLPDB>) {
	chomp;

	if (m/^name (\S+)$/) {
	    if ($1 eq $tlpkg) {
		# Go back to the beginning of the line containing name, get_next_entry() needs this
		seek(TLPDB, $pos, 0);
		my $entry = get_next_entry();

		# when a entry is found, restore the position in the file before returning
		seek(TLPDB, $init_pos, 0);
		return $entry;
	    }
	}

	# save the position in the file to let us go back
	$pos = tell(TLPDB);
    }

    # End reach, nothing found
    seek(TLPDB, $init_pos, 0);
    return;
}



# # Find if a tlpkg already exists in pkgsrc
# sub find_pkg {
#     my $tlpkg = shift || return; # we need a tlpdb

#     # check if the tlpkg has binary and search for them
#     my $has_bin = 0;
#     if (exists $tlpkg->{depend}) {
# 	foreach my $dep (@{$tlpkg->{depend}}) {
# 	    if ($dep =~ m/ARCH$/) {
# 		$has_bin = 1;
# 	    }
# 	}
#     }
#     # check if there are docs
# }

# Find if a tlpkg already exists in pkgsrc
sub pkgsrc_exists {
    my $name = shift || return;

    my $command = qq{$pkgfind -qcx tex-$name |};
    open(PKGFIND, $command) or die "Could not execute $pkgfind: $!\n";

    my $found = 0;
    while (<PKGFIND>) {
	chomp;
	$found = 1 if m/${name}$/;
    }
    close(PKGFIND);

    return $found;
}

# Generate Makefile
sub gen_pkg_makefile {
    my $a = shift || return;

    # Create Makefile
    my $makefile = qq{# \$NetBSD\$

DISTNAME=	$a->{distname}
};
    if ($a->{distname} =~ m/\./) {
	$makefile .= qq{PKGNAME=	tex-\${DISTNAME:S/./-/}-$a->{version}
};
    } else {
	$makefile .= qq{PKGNAME=	tex-\${DISTNAME}-$a->{version}
};
    }

    $makefile .= qq{TEXLIVE_REV=	$a->{rev}
TEXLIVE_USE_CTAN=	yes # Remove afterwards. Needed to make distinfo

MAINTAINER=	user\@example.org
COMMENT=	$a->{comment}

};

    if ($a->{type} eq "runtime" and exists $a->{execute}) {
	foreach my $ex (@{$a->{execute}}) {
	    if ($ex =~ m/^addMap\s+(\S+)$/) {
		$makefile .= qq{TEX_MAP_FILES+=\t\t$1\n};
	    }
	}
	foreach my $ex (@{$a->{execute}}) {
	    if ($ex =~ m/^addMixedMap\s+(\S+)$/) {
		$makefile .= qq{TEX_MIXEDMAP_FILES+=\t$1\n};
	    }
	}
    }

    $makefile .= qq{
.include "../../print/texlive/package.mk"
.include "../../mk/bsd.pkg.mk"
};

    return $makefile;
}

sub gen_pkg_descr {
    my $e = shift || return;

    my $descr;
    if (exists $e->{longdesc}) {
	foreach my $line (@{$e->{longdesc}}) {
	    $descr .= $line . "\n";
	}
    } else {
	$descr = $e->{shortdesc} || "FIXME";
    }

    return $descr;
}

sub gen_pkg_plist {
    my $l = shift || return;

    my $plist = qq{\@comment \$NetBSD\$\n};
    foreach my $file (@{$l}) {
	$file =~ s!RELOC!share/texmf-dist!;
	$plist .= $file . "\n";
    }

    return $plist;
}

sub gen_pkg {
    my $e = shift || return;

    # Prepare some values
    my $version;
    if (exists $e->{'catalogue-version'}) {
	$version = $e->{'catalogue-version'};
    } else {
	$version = $e->{'catalogue-date'};
	$version = s/-.+$//;
    }
    my $comment = $e->{shortdesc} || "FIXME";
    $comment =~ s/\.$//;
    my $pkgname = "tex-".$e->{name};

    if (exists $e->{runfiles}) {
	# Create runtime pkg
	print "==> $pkgname\n";

	my $pkgdir = ${output}."/tex-".$e->{name};
	make_path($pkgdir);

	# Create Makefile
	open(MK, ">", qq{${pkgdir}/Makefile});
	print MK gen_pkg_makefile({type => "runtime",
				  distname => $e->{name},
				  version => $version,
				  comment => $comment,
				  execute => $e->{execute},
				  rev => $e->{revision}
				 });
	close(MK);

	# Create DESCR file
	open(DESCR, ">", qq{${pkgdir}/DESCR});
	print DESCR gen_pkg_descr($e);
	close(DESCR);

	# Create PLIST
	open(PLIST, ">", qq{${pkgdir}/PLIST});
	print PLIST gen_pkg_plist($e->{runfiles});
	close(PLIST);
    }

    if (exists $e->{docfiles}) {
	# Create doc pkg
	print "==> ${pkgname}-doc\n";

	$comment = qq{Documentation for $pkgname};
	my $distname = $e->{name} . ".doc";

	# Create documentation pkg
	my $pkgdir = ${output}."/${pkgname}-doc";
	make_path($pkgdir);

	# Create Makefile
	open(MK, ">", qq{${pkgdir}/Makefile});
	print MK gen_pkg_makefile({type => "doc",
				  distname => $distname,
				  version => $version,
				  comment => $comment,
				  rev => $e->{revision}
				 });
	close(MK);

	# Create DESCR file
	open(DESCR, ">", qq{${pkgdir}/DESCR});
	print DESCR "This is documentation for ${pkgname}.\n";
	close(DESCR);

	# Create PLIST
	open(PLIST, ">", qq{${pkgdir}/PLIST});
	print PLIST gen_pkg_plist($e->{docfiles});
	close(PLIST);
    }

}


sub load_tetexmf_plist {
    my $list = {};

    open(TETEX, qq{${pkgsrc}/print/teTeX3-texmf/PLIST})
      or die "Could not load ${pkgsrc}/print/teTeX3-texmf/PLIST: $!\n";

    while (<TETEX>) {
	chomp;
	next if m/^@/;
	$list->{$_} = 1;
    }
    close(TETEX);

    return $list;
}

sub create_report {

    my $missing = 0;
    my $existing = 0;
    my $nodoc = 0;

    while (my $e = get_next_entry()) {

	# XXX Do not work on tlpkgs with binary files
	my $has_bin;
	$has_bin = 1 if exists $e->{binfiles};
	if (exists $e->{depend}) {
	    foreach my $dep (@{$e->{depend}}) {
		if ($dep =~ m/ARCH$/) {
		    $has_bin = 1;
		}
	    }
	}
	next if $has_bin;

	# Skip tlnet specific packages
	next if ($e->{category} eq "TLCore");

	# Skip packages without description
	next unless exists $e->{shortdesc};

	next if ($e->{'catalogue-ctan'} =~ m!^/info!);

	#
	if (! pkgsrc_exists($e->{name})) {
	    print $e->{category}, "/", $e->{name}, ":\t ", $e->{shortdesc}, "\n";
	    $missing++;
	    next;
	}

	if (exists $e->{docfiles} and ! pkgsrc_exists($e->{name}."-doc")) {
	    print $e->{name}, ":\t documentation not found\n";
	    $nodoc++;
	}

	$existing++;
    }

    my $total = $missing + $existing;

    print qq{
missing:  $missing
existing: $existing
nodoc:    $nodoc
total:    $total
}

}

sub inspect_tlpkg {
    my $p = shift || return;

    my $e = search_entry($p);
    print Dumper($e);

}

sub create_tetex_report {

    my @prio = ();
    my $plist = load_tetexmf_plist();

    while (my $e = get_next_entry()) {

	# XXX Do not work on tlpkgs with binary files
	my $has_bin;
	$has_bin = 1 if exists $e->{binfiles};
	if (exists $e->{depend}) {
	    foreach my $dep (@{$e->{depend}}) {
		if ($dep =~ m/ARCH$/) {
		    $has_bin = 1;
		}
	    }
	}
	next if $has_bin;

	foreach my $type (qw{runfiles docfiles}) {
	    if (exists $e->{$type}) {
		foreach my $rf (@{$e->{$type}}) {
		    $rf =~ s!^RELOC!share/texmf-dist!;
		    if (exists $plist->{$rf}) {
			push @prio, $e->{name};
			last;
		    }
		}
	    }
	}
    }

    my %hash = map { $_, 1 } @prio;
    @prio = keys %hash;

    print join(", ", @prio), "\n";
    print "count: ", scalar(@prio), "\n";

    return @prio;
}


# Do something
my @gen = ();
if ($inspect) {
    foreach my $tlpkg (@tlpkgs) {
	print "=====> $tlpkg\n";
	inspect_tlpkg($tlpkg);
    }
} elsif ($tetex) {
    @gen = create_tetex_report();
} elsif ($report) {
    create_report();
} else {
    foreach my $tlpkg (@tlpkgs) {
	gen_pkg(search_entry($tlpkg));
    }
}

if ($generate) {
    foreach my $tlpkg (@gen) {
	gen_pkg(search_entry($tlpkg));
    }
}

close(TLPDB);

# TODO
# - liste d'exclusion
# - vérification du pkgsrc (si texlive, revision/version)

