
use strict;
use warnings;

use Test::More tests => 16;
use Test::Exception;
use Test::Output;
use Path::Class;
use File::Temp qw( tempdir );
use Archive::Tar;
use Cwd;
use Compress::Zlib;

# set up the "linked" directory for the test suite
use lib 't';

use Test::Setup;

unless ( -d dir( qw( t data linked ) ) ) {
  diag 'creating symlink directory';
  Test::Setup::make_symlinks;
}
use_ok('Bio::Path::Find::DatabaseManager');

use Bio::Path::Find::Finder;

# initialise l4p to avoid warnings
use Log::Log4perl qw( :easy );
Log::Log4perl->easy_init( $FATAL );

use_ok('Bio::Path::Find::App::PathFind::Data');

# set up a temp dir where we can write the archive
my $temp_dir = File::Temp->newdir;
dir( $temp_dir, 't' )->mkpath;
my $orig_cwd = getcwd;
symlink dir( $orig_cwd, qw( t data ) ), dir( $temp_dir, qw( t data ) )
  or die "ERROR: couldn't link data directory into temp directory";
chdir $temp_dir;

#-------------------------------------------------------------------------------

# get some test lanes using the Finder directly
my $f = Bio::Path::Find::Finder->new(
  config     => file( qw( t data 13_pf_data_symlinking test.conf ) ),
  lane_class => 'Bio::Path::Find::Lane::Class::Data',
);

my $lanes = $f->find_lanes( ids => [ '10018_1' ], type => 'lane', filetype => 'fastq' );
is scalar @$lanes, 50, 'found 50 lanes with ID 10018_1 using Finder';

#-------------------------------------------------------------------------------

# symlink attribute but no filename
my %params = (
  # no need to pass "config_file"; it will come from the HasConfig Role
  id               => '10018_1',
  type             => 'lane',
  no_progress_bars => 1,
  symlink          => 1,
);

my $pf;
lives_ok { $pf = Bio::Path::Find::App::PathFind::Data->new(%params) }
  'got a new pathfind data command object';

my $dest = dir( $temp_dir, 'pathfind_10018_1' );

combined_like { $pf->_make_symlinks($lanes) }
  qr|Creating links in 'pathfind_10018_1'.*10018_1#51_1\.fastq\.gz|s,
  'creating links in correct directory';

# remove the links directory and do it again, this time checking for the
# absence of a progress bar

$dest->rmtree;

combined_unlike { $pf->_make_symlinks($lanes) }
  qr|linking|,
  'no progress bar';

ok -d $dest, 'found link directory';

my @links = $dest->children;
is scalar( @links ), 50, 'found all links';
$dest->rmtree;

# link in a specific directory, this time with a progress bar

$params{no_progress_bars} = 0;
$params{symlink}          = 'my_link_dir';
$pf = Bio::Path::Find::App::PathFind::Data->new(%params);

$dest = dir( $temp_dir, 'my_link_dir' );

combined_like { $pf->_make_symlinks($lanes) }
  qr|Creating links in 'my_link_dir'.*\.fastq\.gz|s,
  'creating links in correct directory';

ok -d $dest, 'found link directory';

@links = $dest->children;
is scalar( @links ), 50, 'found all links';

# look for exception when directory already exists as a file
file( $temp_dir, 'pre-existing-file' )->touch;

$params{symlink} = 'pre-existing-file';
$pf = Bio::Path::Find::App::PathFind::Data->new(%params);

throws_ok { $pf->_make_symlinks($lanes) }
  qr/couldn't make link directory/,
  'exception when destination exists as a file';

#-------------------------------------------------------------------------------

# Check links get prefixed with library name

# Check linked directory name 
$params{symlink} = 1;
$params{prefix_with_library_name} = 1;
$pf = Bio::Path::Find::App::PathFind::Data->new(%params);
$lanes = $f->find_lanes( ids => [ '10018_1' ], type => 'lane');

combined_like { $pf->_make_symlinks($lanes) }
  qr|Creating links in 'pathfind_10018_1'|s,
  'creating links in correct directory';

$dest = dir( $temp_dir, 'pathfind_10018_1', 'APP_N2_OP1_7492530_10018_1#1');
ok -l $dest, 'found prefixed link directory';

# Check linked filename
$lanes = $f->find_lanes( ids => [ '10018_1' ], type => 'lane', filetype => 'fastq');
$dest->rmtree;
combined_like { $pf->_make_symlinks($lanes) }
  qr|Creating links in 'pathfind_10018_1'.*10018_1#51_1\.fastq\.gz|s,
  'creating links in correct directory';
$dest = file( $temp_dir, 'pathfind_10018_1', 'APP_N2_OP1_7492530_10018_1#1_1.fastq.gz' );
ok -l $dest, 'found prefixed link file';

#-------------------------------------------------------------------------------

# done_testing;

# tidy up after ourselves...
chdir $orig_cwd;

