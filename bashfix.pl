#!/usr/bin/env perl
use strict;
use warnings;
use File::Temp 'tempdir';
use 5.008;
use Carp 'croak';

our $VERSION = 0.03;

my %bash_patches_count = (
    '3.0' => 22,
    '3.1' => 23,
    '3.2' => 57,
    '4.0' => 44,
    '4.1' => 17,
    '4.2' => 53,
    '4.3' => 30,
);
# check not root user
check_not_root();

# check mandatory C binaries available
check_prereqs();

my $version = get_version();
print "Bash version $version detected\n";

# check it's Bash 3 or 4
die
"Error: bashfix.pl can only upgrade versions 3 or 4 of Bash, but $version was found. Exiting ..."
  unless substr( $version, 0, 1 ) =~ /[34]/;

# check it's not fully patched already
my $major_minor_version = substr( $version, 0, 3 );
my $patch_version = substr( $version, -2 );
die "Your Bash is already fully patched!"
  unless $bash_patches_count{$major_minor_version} != $patch_version;

update_bash( download_bash() );

my $new_version = get_version();

if ( $version ne $new_version ) {
    print "Bash version $new_version is now installed\n";
}
else {
    print "An error occured, Bash was not upgraded\n";
}

sub download_bash {
    my $tmpdir = tempdir();
    print "Created working directory $tmpdir\n";

    my $short_version = substr $version, 0, 3;
    my $bash = "bash-$short_version";

    # download and extract bash
    print "Downloading Bash\n";
    system
"wget -q -O $tmpdir/$bash.tar.gz https://ftp.gnu.org/pub/gnu/bash/$bash.tar.gz";
    system("cd $tmpdir && tar zxf $bash.tar.gz");

    # apply patches
    print "Downloading patches\n";
    my $version_no_dot = substr( $version, 0, 1 ) . substr( $version, 2, 1 );
    my $num_patches = $bash_patches_count{$short_version}
      || die "Error getting number of patches for Bash";

    for ( 1 .. $num_patches ) {
        my $patch_number = sprintf "%03d", $_;
        my $patch_url =
"https://ftp.gnu.org/pub/gnu/bash/bash-$short_version-patches/bash$version_no_dot-$patch_number";
        system
          "cd $tmpdir/$bash && curl -s $patch_url | patch -N -p0 &> /dev/null";
    }

    # confirm patch level is correct
    my $patch_header = `cat $tmpdir/$bash/patchlevel.h`;
    $patch_header =~ /#define PATCHLEVEL\s+(\d+)/;
    print "Bash patched to level $1\n";

    if ( $1 == $bash_patches_count{$short_version} ) {
        print "Bash fully patched!\n";
    }
    else {
        die "Bash not fully patched, exiting ...";
    }

    # configure, make, test
    print "Configuring Bash ...\n";
    system "cd $tmpdir/$bash && ./configure &> /dev/null";
    print "Building and testing Bash ...\n";
    system "cd $tmpdir/$bash && make &> /dev/null";
    system "cd $tmpdir/$bash && make test &> /dev/null";

    die "Error creating bash binary" unless -e "$tmpdir/$bash/bash";
    print "Success. New Bash binary built!\n";

    return "$tmpdir/$bash/bash";
}

sub check_prereqs {
    my @prereq_bins = qw/bison patch byacc gettext autoconf wget curl/;
    for my $bin (@prereq_bins) {
        my $bin_path;
        eval { $bin_path = check_bin_exists($bin) };
        die
"$bin is required for install but not found, install it via your package manager"
          unless $bin_path and -e $bin_path;
    }
}

sub check_not_root {
    die "Error: you must not run bashfix as root user" unless $>;
}

sub check_root {
    die "Error: you must run bashfix as root user" if $>;
}

sub update_bash {
    my $new_bash_bin_path = shift;
    die "Error cannot find new Bash binary at $new_bash_bin_path"
      unless -e $new_bash_bin_path;

    my $bash_path = get_bin_location();
    if ( -e $bash_path ) {
        print "Making backup copy of $bash_path at $bash_path.bak\n";
        system "sudo cp $bash_path $bash_path.bak";
        system "sudo cp -f $new_bash_bin_path $bash_path";
    }
    else {
        die "Can't read file at $bash_path";
    }
    if ( -e '/bin/bash' ) {
        print "Making backup copy of /bin/bash at /bin/bash.bak\n";
        system "sudo cp /bin/bash /bin/bash.bak";
        system "sudo cp -f $new_bash_bin_path /bin/bash";
    }
}

sub check_bin_exists {
    my $bin = shift;
    run_command( "which $bin", qr/^.*?$/ );
}

sub get_bin_location {
    run_command( 'which bash', qr/^.*?$/ );
}

sub get_version {
    run_command( 'bash --version', qr/\d\.\d\.\d+/ );
}

sub run_command {
    my ( $command, $regex ) = @_;
    my $output = `$command`;
    $output =~ /($regex)/;
    $1 or croak "Command returned no output";
}

1;
