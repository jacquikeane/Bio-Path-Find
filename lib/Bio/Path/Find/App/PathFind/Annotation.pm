
package Bio::Path::Find::App::PathFind::Annotation;

# ABSTRACT: find annotation results

use v5.10; # for "say"

use MooseX::App::Command;
use namespace::autoclean;
use MooseX::StrictConstructor;

use Carp qw( croak carp );
use Path::Class;
use Capture::Tiny qw( capture_stderr );

use Types::Standard qw(
  Maybe
  ArrayRef
  +Bool
  Str
);

use Bio::Path::Find::Types qw( :types );

use Bio::Path::Find::Exception;
use Bio::Path::Find::Lane::Class::Annotation;

use Bio::AutomatedAnnotation::ParseGenesFromGFFs;

extends 'Bio::Path::Find::App::PathFind';

with 'Bio::Path::Find::App::Role::Linker',
     'Bio::Path::Find::App::Role::Archivist',
     'Bio::Path::Find::App::Role::Statistician';

#-------------------------------------------------------------------------------
#- usage text ------------------------------------------------------------------
#-------------------------------------------------------------------------------

# this is used when the "pf" app class builds the list of available commands
command_short_description 'Find annotation results';

=head1 NAME

pf annotation - Find annotations for assemblies

=head1 USAGE

  pf annotation --id <id> --type <ID type> [options]

=head1 DESCRIPTION

The C<annotation> command finds annotations for assembled genomes. By default
the command returns the path to the GFF file(s) for lanes, but you can find
other types of annotation data using the C<--filetype> option. You can also
create symlinks to the found files using C<--symlink>, or archive them as a
tar or zip archive using C<--archive>.

If you specify the C<--gene> option, you can search the GFF files for
particular gene names. Adding C<--product> will make the search look for
products as well as genes with the given name. Specifying C<--nucleotide> will
return the found genes as nucleotide, rather than amino-acid sequences.

Use "pf man" or "pf man annotation" to see more information.

If you use the assemblies in your analysis please cite:
"Robust high throughput prokaryote de novo assembly and improvement pipeline for Illumina data",
Andrew J. Page, Nishadi De Silva, Martin Hunt, Michael A. Quail,
Julian Parkhill, Simon R. Harris, Thomas D. Otto, Jacqueline A. Keane. (2016).
Microbial Genomics 2(8): doi:10.1099/mgen.0.000083

and

"Prokka: rapid prokaryotic genome annotation", Torsten Seemann. (2014). 
Bioinformatics 30(14):2068-9. doi:10.1093/bioinformatics/btu153


=head1 EXAMPLES

  # find GFF files for lanes
  pf annotation -t lane -i 12345_1

  # find fasta files
  pf annotation -t lane -i 12345_1 -f faa
  pf annotation -t lane -i 12345_1 --filetype fasta

  # output a fasta containing all sequences with a specific gene name
  # (writes "output.gryA.fa")
  pf annotation -t file --ft lane -i ids.txt -g gryA

  # output a fasta containing nucleotide sequences for a specific gene
  # (writes "gryA.ffn")
  pf annotation -t file --ft lane -i ids.txt -g gryA -n -o gryA.ffn

  # output a fasta file containing all sequences with gene name
  # or product matching "gryA"
  pf annotation -t file --ft lane -i ids.txt -g gryA -p

  # archive GFF files in a gzip-compressed tar file
  pf annotation -t lane -i 12345_1 -a my_gffs.tar.gz

  # archive fasta files in a zip file
  pf annotation -t lane -i 12345_1 -f faa -z my_fastas.zip

=cut

=head1 OPTIONS

These are the options that are specific to C<pf annotation>. Run C<pf man> to
see information about the options that are common to all C<pf> commands.

=over

=item --gene, -g <gene>

Search for sequences with gene name C<gene>. Write a fasta file with the found
sequences

=item --product, -p <product>

Search for sequences with product name C<product>. Write the sequences to
a fasta file

=item --nucleotides, -n

When finding genes or products, output gene/product sequence as nucleotides
rather than amino-acids. Default is to output amino-acid sequences.

=item --program, -p <assembler>

Restrict search to files generated by one of the specified assemblers. You
can give multiple assemblers by adding C<-P> multiple times

  pf annotation -t lane -i 12345 -P iva -P spades

or by giving it a comma-separated list of assembler names:

  pf annotation -t lane -i 12345 -P iva,spades

The assembler must be one of C<iva>, C<pacbio>, C<hgap_4_0>, C<canu_1_6>, C<spades>, or C<velvet>.
Default: return files from all assembly pipelines.

=item --filetype, -f <filetype>

Type of annotation files to find. Must be one of: C<gff> (default), C<faa>
(same as C<fasta>), C<ffn> (same as C<fastn>), or C<gbk> (same as C<genbank>)

=item --stats, -s [<stats filename>]

Write a file with statistics about found lanes. Save to specified filename,
if given. Default filename: <ID>_annotationfind_stats.csv

=item --symlink, -l [<symlink directory>]

Create symlinks to found annotation files. Create links in the specified
directory, if given, or in the current working directory by default.

=item --archive, -a [<tar filename>]

Create a tar archive containing annotation files. Save to specified filename,
if given. Default filename: assemblyfind_<ID>.tar.gz

=item --no-tar-compression, -u

Don't compress tar archives.

=item --zip, -z [<zip filename>]

Create a zip archive containing annotation files. Save to specified filename,
if given. Default filename: assemblyfind_<ID>.zip

=item --rename, -r

Rename filenames when creating archives or symlinks, replacing hashed (#)
with underscores (_).

=back

=cut

=head1 SCENARIOS

=head2 Find annotations

By default the C<pf annotation> command finds and prints the locations of any
GFF files for a set of lanes:

  % pf annotation -t lane -i 5008_5

You can find different types of annotation file e.g. fasta files:

  % pf annotation -t lane -i 5008_5 -f fasta

The available annotation file types are:

=over

=item C<faa>, which is equivalent to C<fasta>

=item C<ffn> or C<fastn>

=item C<gbk> or C<genbank>

=item C<gff> (default)

=back

=head2 Find genes or products

You can search for sequences with a specific gene name or product. To search
for all C<gryA> genes:

  pf annotation -t lane -i 12345_1 -g gryA

To search for products, use the C<-p> option with the product description:

  pf annotation -t lane -i 12345_1 -p "transcriptional regulator"

The C<-g> and C<-p> options will write out fasta files containing the sequences
found (something like "output.<gene>.fa" or "output.<product>.fa"), and print a
summary of what they found, showing how many of the annotation files contained
or were missing the specified gene/product.

Note that you can specify both C<-g> and C<-p>, which will search for genes or
products with the given name, but you can only give one search name, which
must be given as the argument to C<-g>, i.e.

  pf annotation -t lane -i 12345_1 -g gryA -p

Giving values for both C<-g> and C<-p> will print a warning and the search will
ignore the value given with C<-p>.

=head2 Archive all annotations for a study

You can search for all of the GFF files for a given study and collect them
in a single tar or zip archive:

  pf annotation -t study -i 123 -a study_123_annotations.tar.gz

or you can create symlinks to the GFF files in another directory:

  pf annotation -t study -i 123 -l

=head2 Get statistics for a lane's annotation results

You can generate a CSV file containing statistics for the annotation results
for a particular lane:

  pf annotation -t lane -i 12345_1#1 -s lane_12345_1#1_stats.csv

Note that a lane may have annotations from multiple pipelines. In this case you
can restrict your output to show only annotations from a particular assembly
pipeline:

  pf annotation -t lane -i 12345_1#1 -s -P iva

=head1 SEE ALSO

=over

=item pf assembly - find assemblies

=back

=cut

#-------------------------------------------------------------------------------
#- command line options --------------------------------------------------------
#-------------------------------------------------------------------------------

option 'filetype' => (
  documentation => 'type of files to find',
  is            => 'ro',
  isa           => AnnotationType,
  cmd_aliases   => 'f',
  # default       => 'gff',
  # don't specify a default here; it screws up the gene finding method
);

#---------------------------------------

option 'output' => (
  documentation => 'output filename for genes',
  is            => 'ro',
  isa           => Str,
  cmd_aliases   => 'o',
);

#---------------------------------------

option 'nucleotides' => (
  documentation => 'output nucleotide sequence instead of protein sequence',
  is            => 'ro',
  isa           => Bool,
  cmd_aliases   => 'n',
);

#---------------------------------------

option 'program' => (
  documentation => 'look for annotation created by specific assembly pipeline(s)',
  is            => 'ro',
  isa           => Assemblers,
  cmd_aliases   => 'P',
  cmd_split     => qr/,/,
);

#---------------------------------------

option 'gene' => (
  documentation => 'gene name',
  is            => 'ro',
  isa           => Str,
  cmd_aliases   => 'g',
);

#---------------------------------------

# this option can be used as a simple switch ("-p") or with an argument
# ("-p product"). It's a bit fiddly to set that up...
option 'product' => (
  documentation => 'product name',
  is            => 'ro',
  cmd_aliases   => 'p',
  trigger       => \&_check_for_product_value,
  # no "isa" because we want to accept both Bool and Str and it doesn't seem to
  # be possible to specify that using the combination of MooseX::App and
  # Type::Tiny that we're using here
);

# set up a trigger that checks for the value of the "product" command-line
# argument and tries to decide if it's a boolean, in which case we'll use the
# gene name when searching for sequences, or a string, in which case we'll
# treat that string as a product name
sub _check_for_product_value {
  my ( $self, $new, $old ) = @_;

  if ( not defined $new ) {
    # search for products, but using the gene name
    $self->_product_flag(1);
  }
  elsif ( not is_Bool($new) ) {
    # search for products using the specified name
    $self->_product_flag(1);
    $self->_product( $new );
  }
  else {
    # don't search for products. Shouldn't ever get here
    $self->_product_flag(0);
  }
}

# private attributes to store the (optional) value of the "product" attribute.
# When using all of this we can check for "_product_flag" being true or false,
# and, if it's true, check "_product" for a value
has '_product'      => ( is => 'rw', isa => Str );
has '_product_flag' => ( is => 'rw', isa => Bool );

#-------------------------------------------------------------------------------
#- private attributes ----------------------------------------------------------
#-------------------------------------------------------------------------------

# this is a builder for the "_lane_class" attribute, which is defined on the
# parent class, B::P::F::A::PathFind. The return value specifies the class of
# object that should be returned by the B::P::F::Finder::find_lanes method.

sub _build_lane_class {
  return 'Bio::Path::Find::Lane::Class::Annotation';
}

#---------------------------------------

# this is a builder for the "_stats_file" attribute that's defined by the
# B::P::F::Role::Statistician. This attribute provides the default name of the
# stats file that the command writes out

sub _build_stats_file {
  my $self = shift;
  return file( $self->_renamed_id . '.annotationfind_stats.csv' );
}

#---------------------------------------

# set the default name for the symlink directory

around '_build_symlink_dest' => sub {
  my $orig = shift;
  my $self = shift;

  my $dir = $self->$orig->stringify;
  $dir =~ s/^pf_/assemblyfind_/;

  return dir( $dir );
};

#---------------------------------------

# set the default names for the tar or zip files

around [ '_build_tar_filename', '_build_zip_filename' ] => sub {
  my $orig = shift;
  my $self = shift;

  my $filename = $self->$orig->stringify;
  $filename =~ s/^pf_/annotationfind_/;

  return file( $filename );
};

#---------------------------------------

# these are the sub-directories of a lane's data directory where we will look
# for annotation files

has '_subdirs' => (
  is => 'ro',
  isa => ArrayRef[PathClassDir],
  builder => '_build_subdirs',
);

sub _build_subdirs {
  return [
    dir(qw( iva_assembly annotation )),
    dir(qw( spades_assembly annotation )),
    dir(qw( velvet_assembly annotation )),
    dir(qw( pacbio_assembly annotation )),
	dir(qw( hgap_4_0_assembly annotation )),
	dir(qw( canu_1_6_assembly annotation )),
  ];
}

#-------------------------------------------------------------------------------
#- public methods --------------------------------------------------------------
#-------------------------------------------------------------------------------

sub run {
  my $self = shift;

  # TODO fail fast if we're going to end up overwriting a file later on

  # set up the finder

  # build the parameters for the finder
  my %finder_params = (
    ids      => $self->_ids,
    type     => $self->_type,
    filetype => $self->filetype || 'gff',
    subdirs  => $self->_subdirs,
  );

  # tell the finder to set "search_depth" to 3 for the Lane objects that it
  # returns. The files that we want to find using Lane::find_files are in the
  # sub-directory containing assembly information, so the default search depth
  # of 1 will miss them.
  $finder_params{lane_attributes}->{search_depth} = 3;

  # make Lanes store found files as simple strings, rather than
  # Path::Class::File objects. The list of files is handed off to
  # Bio::AutomatedAnnotation::ParseGenesFromGFFs, which spits the dummy if it's
  # handed objects.
  $finder_params{lane_attributes}->{store_filenames} = 1;

  # should we tell the lanes to restrict ther search for files to a those
  # created by a specific assembler ?
  if ( $self->program ) {
    # yes; tell the Finder to set the "assemblers" attribute on every Lane that
    # it returns
    $finder_params{lane_attributes}->{assemblers} = $self->program;
  }

  # should we look for lanes with the "annotated" bit set on the "processed"
  # bit field ? Turning this off, i.e. setting the command line option
  # "--ignore-processed-flag" will allow the command to return data for lanes
  # that haven't completed the annotation pipeline.
  $finder_params{processed} = Bio::Path::Find::Types::ANNOTATED_PIPELINE
    unless $self->ignore_processed_flag;

  # find lanes
  my $lanes = $self->_finder->find_lanes(%finder_params);

  $self->log->debug( 'found a total of ' . scalar @$lanes . ' lanes' );

  if ( scalar @$lanes < 1 ) {
    say STDERR 'No data found.';
    exit;
  }

  # do something with the found lanes
  if ( $self->_symlink_flag or
       $self->_tar_flag or
       $self->_zip_flag or
       $self->_stats_flag or
       $self->gene or
       $self->product ) {
    $self->_make_symlinks($lanes) if $self->_symlink_flag;
    $self->_make_tar($lanes)      if $self->_tar_flag;
    $self->_make_zip($lanes)      if $self->_zip_flag;
    $self->_make_stats($lanes)    if $self->_stats_flag;

    if ( $self->gene or $self->_product_flag ) {
      $self->_print_files($lanes);
      $self->_find_genes($lanes);
    }
  }
  else {
    $self->_print_files($lanes);
  }
}

#-------------------------------------------------------------------------------
#- private methods -------------------------------------------------------------
#-------------------------------------------------------------------------------

sub _print_files {
  my ( $self, $lanes ) = @_;

  my $pb = $self->_create_pb('collecting files', scalar @$lanes);

  my @files;
  foreach my $lane ( @$lanes ) {
    push @files, $lane->all_files;
    $pb++;
  }

  say $_ for @files;
}

#-------------------------------------------------------------------------------

sub _find_genes {
  my ( $self, $lanes ) = @_;

  # the user gave "-p" but no value and there was no "-g"
  if ( not $self->gene and
       $self->_product_flag and
       ( not defined $self->_product or $self->_product eq '' ) ) {
    croak q(ERROR: you must either give a value for "-p" or you must specify a gene name using "-g");
  }

  # we'll issue a warning if the user specifies "-g X -p Y", to the effect that
  # we're ignoring the value "Y" and are looking only for genes or products
  # called X.
  if ( $self->gene and $self->_product_flag and $self->_product ) {
    my $g = $self->gene;
    my $p = $self->_product;
    print STDERR <<"EOF_warning";
WARNING: searching for genes and products with different names is not supported.
Ignoring product name "$p" and searching instead for genes or products named "$g".
EOF_warning
  }

  # see if we need to go and find the GFF files. If the user specified a
  # filetype other than GFF (with "-f" on the command line) then the lanes will
  # already have found that sort of file, but not the GFFs that we need here.
  # If we don't already have them, go and find the GFFs
  my @gffs;
  if ( defined $self->filetype and $self->filetype eq 'gff' ) {
    push @gffs, $_->all_files for @$lanes;
  }
  else {
    my $pb = $self->_create_pb('finding GFFs', scalar @$lanes);
    for my $current_lane ( @$lanes ) {
      for my $current_gff ( $current_lane->find_files('gff', $self->_subdirs))
      {
        push @gffs, $current_gff."";
        $pb++;
      }
    }
  }

  # set up the parameters for the GFF parser
  my %params = (
    gff_files   => \@gffs,
    amino_acids => $self->nucleotides ? 0 : 1,
  );

  if ( $self->gene and $self->_product_flag ) {
    $params{search_query} = $self->gene;
    $params{search_qualifiers} = [ 'gene', 'ID', 'product' ];
  }
  elsif ( $self->_product_flag ) {
    $params{search_query}      = $self->_product;
    $params{search_qualifiers} = [ 'product' ];
  }
  elsif ( $self->gene ) {
    $params{search_query}      = $self->gene;
    $params{search_qualifiers} = [ 'gene', 'ID' ];
  }

  $params{output_file} = $self->output if defined $self->output;

  my $gf = Bio::AutomatedAnnotation::ParseGenesFromGFFs->new(%params);
  print "finding genes... ";

  # the "ParseGenesFromGFFs" method calls out to BioPerl which issues several
  # warnings and the original annotationfind just shows them. Since they're
  # apparently harmless, we'll be a bit tidier and capture (and discard) STDERR
  # to avoid the user seeing the warnings.
  capture_stderr { $gf->create_fasta_file };

  print "\r"; # make the next line overwrite "finding genes..."

  say 'Outputting nucleotide sequences' if $self->nucleotides;
  if ( $self->_product_flag ) {
    say "Samples containing gene/product:\t" . $gf->files_with_hits;
    say "Samples missing gene/product:   \t" . $gf->files_without_hits;
  }
  else {
    say "Samples containing gene:\t" . $gf->files_with_hits;
    say "Samples missing gene:   \t" . $gf->files_without_hits;
  }
}

#-------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;

1;

