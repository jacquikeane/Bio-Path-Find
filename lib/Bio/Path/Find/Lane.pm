
package Bio::Path::Find::Lane;

# ABSTRACT: a class for working with information about a sequencing lane

use v5.10;    # required for Type::Params use of "state"

use Moose;
use namespace::autoclean;
use MooseX::StrictConstructor;

use Carp qw( carp );
use Path::Class;
use File::Find::Rule;
use Try::Tiny;
use Cwd;

use Bio::Path::Find::Lane::Status;
use Bio::Path::Find::Exception;

use Type::Params qw( compile );
use Types::Standard qw(
  Object
  Str
  Int
  HashRef
  ArrayRef
  slurpy
  Dict
  Optional
  Bool
);
use Bio::Path::Find::Types qw(
  BioPathFindLaneStatus
  BioTrackSchemaResultLatestLane
  PathClassFile
  PathClassDir
  FileType
  AssemblyType
);

with 'MooseX::Log::Log4perl', 'MooseX::Traits';

=head1 CONTACT

path-help@sanger.ac.uk

=cut

#-------------------------------------------------------------------------------
#- attributes ------------------------------------------------------------------
#-------------------------------------------------------------------------------

=head1 ATTRIBUTES

=cut

#-------------------------------------------------------------------------------
#- required attributes ---------------------------------------------------------
#-------------------------------------------------------------------------------

=attr row

A L<Bio::Track::Schema::Result::LatestLane> object for this row.

=cut

has 'row' => (
  is       => 'ro',
  isa      => BioTrackSchemaResultLatestLane,
  required => 1,
);

#-------------------------------------------------------------------------------
#- optional read-write attributes ----------------------------------------------
#-------------------------------------------------------------------------------

=attr filetype_extensions

Hash ref that maps a filetype, e.g. C<fastq>, to its file extension, e.g.
C<.fastq.gz>. The default mapping is empty and should be overridden by a
mapping provided by a C<Role|Bio::Path::Find::Lane::Role> applied to the
C<Lane>.

=cut

# this mapping is cargo-culted from the original code and doesn't necessarily
# make much sense...

has 'filetype_extensions' => (
  is      => 'rw',
  isa     => HashRef [Str],
  lazy    => 1,
  builder => '_build_filetype_extensions',
);

sub _build_filetype_extensions {
  {
    # empty mapping; provided by applied Role, e.g. B::P::F::Lane::Role::Data
  };
}

#---------------------------------------

=attr search_depth

The depth of the search when looking for files using a pattern match. Default
is 1 level.

=cut

has 'search_depth' => (
  is      => 'rw',
  isa     => Int,
  default => 1,
);

#-------------------------------------------------------------------------------
#- read-only attributes --------------------------------------------------------
#-------------------------------------------------------------------------------

=attr files

Reference to an array of L<Path::Class::File> objects representing the files
associated with this lane.

=cut

# this is a read-write attribute but it's only writeable via a private
# accessor

has 'files' => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => ArrayRef [PathClassFile],
  default => sub { [] },
  handles => {
    _add_file    => 'push',       # private method
    all_files    => 'elements',
    has_files    => 'count',
    has_no_files => 'is_empty',
    file_count   => 'count',
    clear_files  => 'clear',
  },
);

#---------------------------------------

=attr root_dir

A L<Path::Class::Dir> object representing the root directory for files related
to the database from which this lane was derived.

=cut

has 'root_dir' => (
  is      => 'ro',
  isa     => PathClassDir,
  lazy    => 1,
  builder => '_build_root_dir',
);

sub _build_root_dir {
  my $self = shift;

  my $root_dir = dir( $self->row->database->hierarchy_root_dir );

  # sanity check: make sure that the root directory, the top of the filesystem
  # tree for all of the files that we're going to look for, actually exists. If
  # it doesn't, that might indicate a problem with the mountpoint on the
  # machine and it's worth telling the user, so that they don't simply think
  # their IDs etc. don't exist
  unless ( -e $root_dir ) {
    Bio::Path::Find::Exception->throw( msg =>
        "ERROR: can't see the filesystem root ($root_dir). This may indicate a problem with mountpoints"
    );
  }

  return $root_dir;
}

#---------------------------------------

=attr storage_path

A L<Path::Class::Dir> object representing the canonical path to all files for
this lane.

=cut

has 'storage_path' => (
  is      => 'ro',
  isa     => PathClassDir,
  lazy    => 1,
  builder => '_build_storage_path',
);

sub _build_storage_path {
  my $self = shift;
  return dir( $self->root_dir, $self->row->storage_path );
}

#---------------------------------------

=attr symlink_path

A L<Path::Class::Dir> object representing the symlinked directory for data
files related to this lane.

=cut

has 'symlink_path' => (
  is      => 'ro',
  isa     => PathClassDir,
  lazy    => 1,
  builder => '_build_symlink_path',
);

sub _build_symlink_path {
  my $self = shift;
  return dir( $self->root_dir, $self->row->path );
}

#---------------------------------------

=attr found_file_type

The type of file that was found when running L<find_files>, or C<undef> if
L<find_files> has not yet been run. This attribute acts as a proxy for checking
if this C<Lane> has found files yet. If C<found_file_type> is set, i.e. not
C<undef>, the L<find_files> method has been called. This can be checked using
the L<has_found_files> predicate.

The type of tile to find is specified as an argument to L<find_files> and
cannot be set separately. B<Read only>.

=cut

has 'found_file_type' => (
  is        => 'rw',
  isa       => Str,
  writer    => '_set_found_file_type',
  predicate => 'has_found_files',
);

#---------------------------------------

=attr status

The L<Bio::Path::Find::Lane::Status> object for this lane.

=cut

has 'status' => (
  is      => 'ro',
  isa     => BioPathFindLaneStatus,
  lazy    => 1,
  builder => '_build_status',
  handles => [
    'pipeline_status',
  ],
);

sub _build_status {
  my $self = shift;

  return Bio::Path::Find::Lane::Status->new( lane => $self );
}

#-------------------------------------------------------------------------------
#- public methods --------------------------------------------------------------
#-------------------------------------------------------------------------------

=head1 METHODS

=cut

# these methods are all generated by the traits on attributes

=head2 all_files

Returns a list of the files for this lane. The files are represented by
L<Path::Class::File> objects, giving the absolute path to the file on disk.

=head2 has_files

Returns true if this lane has files associated with it, false otherwise.
B<Note> that this method will return false if the L<find_files> method has
been run but there are no files found, and also if the L<find_files> method
simply hasn't yet been run.

=head2 has_no_files

Returns true if this file has B<no> files associated with it, false otherwise.
To be explicit, this is the inverse of L<has_files>.

=head2 file_count

Returns the number of files associated with this lane.

=head2 clear_files

Clears the list of found files. No return value.

=cut

#-------------------------------------------------------------------------------

# these are concrete methods from this class

=head2 find_files($filetype)

Look for files associated with this lane with a given filetype. Returns the
number of files found.

This method relies on functionality that must be provided by C<Roles>. For
example, the ability to find fastq files is provided by
L<Bio::Path::Find::Lane::Role::Data>. The C<Role> should normally be applied to
the L<Lane|Bio::Path::Find::Lane> at instantiation, something like:

  my $lane = Bio::Path::Find::Lane->with_traits('Bio::Path::Find::Lane::Role::Data')
                                  ->new( row => $lane_row );

You can also apply roles to classes; refer to the (L<Moose
docs|https://metacpan.org/pod/distribution/Moose/lib/Moose/Manual/Roles.pod#ADDING-A-ROLE-TO-AN-OBJECT-INSTANCE>)
for how to do that.

=cut

sub find_files {
  state $check = compile( Object, FileType|AssemblyType );
  my ( $self, $filetype ) = $check->(@_);

  $self->_set_found_file_type($filetype);

  $self->clear_files;

  # see if this Lane has a "_get_<filetype>" method, which will come from a
  # Role applied when the Lane is instantiated
  my $method_name = "_get_$filetype";
  $self->$method_name if $self->can($method_name);

  # can't find files of a specific type; fall back on the mapping between
  # filetype and filename extension
  if ( $self->has_no_files ) {
    my $extension = $self->filetype_extensions->{$filetype};
    $self->_get_extension($extension)
      if ( defined $extension and $extension =~ m/\*/ );
    $self->log->debug( 'found ' . $self->file_count . ' files using extension mapping' )
      if $self->has_files;
  }

  return $self->file_count;
}

#-------------------------------------------------------------------------------

=head2 print_paths

Prints the paths for this lane.

If a file type was specified when running L<find_files>, this method prints the
path to that type of file only. If file type was not specified, this method
prints the path to the directory containing all files for this lane.

Returns the number of files found, if a file type was specified, or 1 if we're
printing the path to the lane's directory.

=cut

sub print_paths {
  my $self = shift;

  my $rv = 0;
  if ( $self->found_file_type ) {
    say $_ for ( $self->all_files );
    $rv += $self->has_files;
  }
  else {
    say $self->symlink_path;
    $rv = 1;
  }

  return $rv;
}

#-------------------------------------------------------------------------------

=head2 make_symlinks( dest => ?$dest, rename => $?rename, filetype => ?$filetype)

Generate symlinks for files from this lane.

If C<$dest> is supplied it must be a L<Path::Class::Dir> giving the destination
directory for the links. An exception is thrown if the destination directory
doesn't exist.

If C<$dest> is not supplied, we create symlinks in the current working
directory.

An optional filetype may also be given. This must be one of "C<fastq>",
"C<bam>", "C<pacbio>" or "C<corrected>" (see L<Bio::Path::Find::Types>, type
C<FileType>). If C<$filetype> is supplied, the lane will look for files of the
specified type, even if it has already searched for files, allowing the caller
to override the filetype that was specified when instantiating the
L<Bio::Path::Find::Lane> object.

If the destination path already exists, either as a link or as a regular file,
we issue a warning and skip the file. There is no option to overwrite existing
files/links; move or delete them before trying to create new links.

If C<$rename> is true, filenames will be created with hashes (#) converted into
underscores (_).

This method throws an exception if it cannot create symlinks, possibly because
perl itself can't create links on the current platform.

Returns the number of links created.

=cut

sub make_symlinks {
  state $check = compile(
    Object,
    slurpy Dict [
      dest     => Optional [PathClassDir],
      rename   => Optional [Bool],
      filetype => Optional [FileType]
    ],
  );
  my ( $self, $params ) = $check->(@_);

  if ( not defined $params->{dest} ) {
    $self->log->debug('using current directory as destination');
    $params->{dest} = dir getcwd;
  }

  unless ( -d $params->{dest} ) {
    Bio::Path::Find::Exception->throw( msg =>
        'ERROR: destination for symlinks does not exist or is not a directory ('
        . $params->{dest}
        . ')' );
  }

  if ( $params->{filetype} ) {
    $self->log->debug( 'find files of type "' . $params->{filetype} . '"' );
    $self->find_files( $params->{filetype} );
  }

  my $rv = 0;
  if ( $self->has_found_files and $self->has_files ) {
    $rv = $self->_make_file_symlinks( $params->{dest}, $params->{rename} );
  }
  else {
    $rv = $self->_make_dir_symlink( $params->{dest}, $params->{rename} );
  }

  return $rv;
}

#-------------------------------------------------------------------------------
#- private methods -------------------------------------------------------------
#-------------------------------------------------------------------------------

# make a link to the found files for this lane

sub _make_file_symlinks {
  my ( $self, $dest, $rename ) = @_;

  if ( $self->has_no_files ) {
    carp 'WARNING: no files found for linking';
    return 0;
  }

  my $num_successful_links = 0;
  FILE: foreach my $src_file ( $self->all_files ) {

    my $filename = $src_file->basename;

    # do we need to rename the link (convert hashes to underscores) ?
    $filename =~ s/\#/_/g if $rename;

    my $dst_file = file( $dest, $filename );

    if ( -f $dst_file ) {
      carp "WARNING: destination file ($dst_file) already exists; skipping";
      next FILE;
    }

    if ( -l $dst_file ) {
      carp
        "WARNING: destination file ($dst_file) is already a symlink; skipping";
      next FILE;
    }

    my $success = 0;
    try {
      $success = symlink( $src_file, $dst_file );
    }
    catch {
      # this should only happen if perl can't create symlinks on the current
      # platform
      Bio::Path::Find::Exception->throw(
        msg => "ERROR: cannot create symlinks: $_" );
    };
    $num_successful_links += $success;

    carp qq(WARNING: failed to create symlink for "$src_file") unless $success;
  }

  $self->log->debug("created $num_successful_links links");

  return $num_successful_links;
}

#-------------------------------------------------------------------------------

# make a link to the directory containing the files for this lane. Actually, we
# make a link to the link to that directory, but... semantics

sub _make_dir_symlink {
  my ( $self, $dest, $rename ) = @_;

  # symlink_path gives the path to the directory containing the data files for
  # the lane. Here we chop off the final component of that path and use that
  # as the basis for the symlink that we'll create
  my $dir_name = $self->symlink_path->dir_list(-1);

  # do we need to rename the link (convert hashes to underscores) ?
  $dir_name =~ s/\#/_/g if $rename;

  my $src_dir = $self->symlink_path;
  my $dst_dir = file( $dest, $dir_name );

  if ( -e $dst_dir ) {
    carp "WARNING: destination dir ($dst_dir) already exists; skipping";
    return 0;
  }

  if ( -l $dst_dir ) {
    carp "WARNING: destination dir ($dst_dir) is already a symlink; skipping";
    return 0;
  }

  my $success = 0;
  try {
    $success = symlink( $src_dir, $dst_dir );
  }
  catch {
    # this should only happen if perl can't create symlinks on the current
    # platform
    Bio::Path::Find::Exception->throw(
      msg => "ERROR: cannot create symlinks: $_" );
  };

  carp qq(WARNING: failed to create symlink for "$dest") unless $success;

  return $success;
}

#-------------------------------------------------------------------------------

sub _get_extension {
  my ( $self, $extension ) = @_;

  $self->log->trace(qq(searching for files with extension "$extension"));

  my @files =
    File::Find::Rule->file->extras( { follow => 1 } )
    ->maxdepth( $self->search_depth )->name($extension)
    ->in( $self->symlink_path );

  $self->log->debug( 'trace ' . scalar @files . ' files' );

  $self->_add_file( file($_) ) for @files;
}

#-------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;

1;

