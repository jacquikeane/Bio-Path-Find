#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use Test::Output;
use Test::Script::Run;
use File::Temp;
use File::Copy;
use Path::Class;
use Cwd;
use IPC::Open2;

# set up the "linked" directory for the test suite
use lib 't';

use Test::Setup;

unless ( -d dir( qw( t data linked ) ) ) {
  diag 'creating symlink directory';
  Test::Setup::make_symlinks;
}
delete $ENV{HARNESS_ACTIVE};
#-------------------------------------------------------------------------------

# set up a temp dir
my $temp_dir = File::Temp->newdir;
dir( $temp_dir, 't' )->mkpath;
my $orig_cwd = getcwd;
symlink dir( $orig_cwd, qw( t data ) ), dir( $temp_dir, qw( t data ) )
  or die "ERROR: couldn't link data directory into temp directory";
chdir $temp_dir;

#-------------------------------------------------------------------------------

# explicitly unset environment variable
delete $ENV{PF_CONFIG_FILE};

my $script = file( $orig_cwd, qw( bin pf ) );
my ( $rv, $stdout, $stderr ) = run_script( $script );

# no arguments but no config or log file path defined
like $stderr, qr/ERROR: no config file defined/,
  'error about missing config on STDERR';

$ENV{PF_CONFIG_FILE} = 'prod.conf';
( $rv, $stdout, $stderr ) = run_script( $script );

#---------------------------------------

# valid command line but non-existent config
$ENV{PF_LOG_FILE} = 'pathfind.log';
( $rv, $stdout, $stderr ) = run_script( $script, [ 'info', '-t', 'lane', '-i', '10018_1#1' ] );

like $stderr, qr/ERROR: specified config file \(prod\.conf\) does not exist/,
  'error about missing config on STDERR';

#---------------------------------------

# put the config in the expected location and try the same command again; this
# time it should work
copy file( qw( t data 18_pf_info_script prod.conf ) ), $temp_dir
  or die "copying prod.conf failed: $!";

( $rv, $stdout, $stderr ) = run_script( $script, [ 'info', '-t', 'lane', '-i', '10018_1#1' ] );

is $stderr, '', 'no output on STDERR';

#---------------------------------------

# specify a different filename
( $rv, $stdout, $stderr ) = run_script( $script, [ 'info', '-t', 'lane', '-i', '10018_1#1', '-o', 'if.csv' ] );

like $stderr, qr/Wrote info to "if.csv"/, 'expected output on STDERR when writing CSV';

ok -f 'if.csv', 'found other CSV file';

#---------------------------------------

# check no info returned when ssid matches internal_id but names don't match
( $rv, $stdout, $stderr ) = run_script( $script, [ 'info', '-t', 'sample', '-i', '2363STDY5509321' ] );

my $expected_stdout = join '', <DATA>;
is $stdout, $expected_stdout, 'got expected info with ssid clash';

#-------------------------------------------------------------------------------

my @log_lines = file('pathfind.log')->slurp;

is scalar @log_lines, 3, 'got expected number of log entries';

like $log_lines[0], qr|bin/pf info -t lane -i 10018_1#1$|, 'log looks sensible';

#-------------------------------------------------------------------------------

# done_testing;

chdir $orig_cwd;

__DATA__
Lane            Sample                    Supplier Name             Public Name               Strain
10050_2#88      2363STDY5509321           NA                        NA                        NA
