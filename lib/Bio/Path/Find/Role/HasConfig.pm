
package Bio::Path::Find::Role::HasConfig;

# ABSTRACT: role providing attributes for interacting with configurations

use Moose::Role;

use Types::Standard qw(
  HashRef
);

use Bio::Path::Find::Types qw( 
  PathClassFile
  FileFromStr
);

use Config::Any;

use Bio::Path::Find::Exception;

=head1 CONTACT

path-help@sanger.ac.uk

=cut

#-------------------------------------------------------------------------------
#- public attributes -----------------------------------------------------------
#-------------------------------------------------------------------------------

=head1 ATTRIBUTES

=attr config_file

Path to the configuration file. If not specified, we'll look for a filename
in the C<PATHFIND_CONFIG> environment variable.

Throws an exception if the config file isn't specified and can't be found
via C<PATHFIND_CONFIG>, or if the file doesn't exist where it's supposed to
exist.

=cut

has 'config_file' => (
  is      => 'ro',
  isa     => PathClassFile->plus_coercions(FileFromStr),
  coerce  => 1,
  lazy    => 1,
  writer  => '_set_config_file',
  builder => '_build_config_file',
  trigger => \&_check_config_file,
);

sub _build_config_file {
  my $self = shift;

  my $config_file = $ENV{PATHFIND_CONFIG};

  Bio::Path::Find::Exception->throw( msg => "ERROR: can't determine config file" )
    unless defined $config_file;

  Bio::Path::Find::Exception->throw( msg => "ERROR: default config file ($config_file) doesn't exist (or isn't a file)" )
    unless -f $config_file;

  return $config_file;
}

sub _check_config_file {
  my ( $self, $config_file, $old_config_file ) = @_;

  Bio::Path::Find::Exception->throw( msg => "ERROR: config file ($config_file) doesn't exist" )
    unless -f $config_file;
}

#---------------------------------------

# the configuration hash
has 'config' => (
  is      => 'rw',
  isa     => HashRef,
  lazy    => 1,
  writer  => '_set_config',
  builder => '_build_config',
);

sub _build_config {
  my $self = shift;

  # load the specified configuration file. Using Config::Any should let us
  # handle several configuration file formats, such as Config::General or YAML
  my $cfg = Config::Any->load_files(
    {
      files           => [ $self->config_file ],
      use_ext         => 1,
      flatten_to_hash => 1,
      driver_args     => {
        General => {
          -InterPolateEnv  => 1,
          -InterPolateVars => 1,
        },
      },
    }
  );

  Bio::Path::Find::Exception->throw(
    msg => q(ERROR: failed to read configuration from file ") . $self->config_file . q(")
  )
    unless scalar keys %{ $cfg->{$self->config_file} };

  return $cfg->{$self->config_file};
}

#-------------------------------------------------------------------------------

1;
