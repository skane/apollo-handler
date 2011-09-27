package APOLLO::DBR;

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# the contents of this file are Copyright (c) 2004 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#=======================================================================
#
#  $Id: DBR.pm,v 1.15 2005/09/20 17:21:42 impious Exp $
#  $Source: /cvsroot/apollo-handler/apollo-handler/lib/APOLLO/DBR.pm,v $
#
#=======================================================================


use strict;
use DBI;
use APOLLO::DBR::DBRH;

#here is a list of the supported databases:
my %connectstrings = (
		      Mysql => 'dbi:mysql:database=-database-;host=-hostname-',
		      Pg    => 'dbi:Pg:dbname=-database-;host=-hostname-',
		     );

sub new {
  my( $package ) = shift;
  my %params = @_;
  my $self = {logger => $params{-logger}};

  bless( $self, $package );

  return $self->_error("Error: -conf must be specified") unless $params{-conf};

  my @conf;
  my $setcount = 0;
  open CONFIG, "<$params{-conf}";
  while (my $row = <CONFIG>) {
    next if $row =~ /^\s*\#/;	# skip comments
    $conf[$setcount] ||= {};
    if($row =~ /^\s*---/){ # section divider
      $setcount++;
      next;
    }
    $row =~ s/(^\s*|\s*$)//g;
    next unless length($row);
    my ($key,$val) = $row =~ /^(.*?)\s*=\s*(.*)$/;
    $conf[$setcount]->{lc($key)} = $val;
  }
  close CONFIG;

  my %config;

  foreach my $conf (@conf) {
	next unless ref($conf) eq 'HASH';
	my $name = $conf->{name};
	next unless $name;

	my $class = $conf->{class} || 'master'; # default to master

	$config{$name}->{$class} = $conf;

	if($conf->{alias}){
	      $config{$conf->{alias}}->{'*'} = $conf;
	}

  }
  $self->{CONFIG} = \%config;
  $self->{CACHE} = {};

  return( $self );
}


sub setlogger {
      my $self = shift;
      $self->{logger} = shift;
}

sub connect {
  my $self = shift;
  my $name = shift;
  my $class = shift;
  my $flag;

  if ($class eq 'dbh'){ # legacy
	$flag = 'dbh';
	$class = undef;
  }

  my $dbh;

  $class ||= $self->{globalclass} || 'master';

  my $dbinf = $self->{CONFIG}->{$name}->{$class} || $self->{CONFIG}->{$name}->{'*'}; # handle aliases if there's no exact match

  return $self->_error("No config found for db $name class $class") unless $dbinf;

  my $realname = $dbinf->{name};
  my $realclass = $dbinf->{class};

  #print STDERR "Connecting to $realname, $realclass(REQ: $name,$class)\n";

  if($self->{CACHE}->{$realname}->{$realclass}) {
    my $boolean = $self->{CACHE}->{$realname}->{$realclass}->do( "SELECT 1" );
    if( $boolean ) {
      $dbh = $self->{CACHE}->{$realname}->{$realclass};
      #print STDERR "CACHE HIT\n";
    }else{
      $self->{CACHE}->{$realname}->{$realclass}->disconnect();
      undef $self->{CACHE}->{$realname}->{$realclass};
    }
  }


if(!$dbh){
  if($dbinf) {
    my @params;

    my $connect = $connectstrings{$dbinf->{type}};

    return $self->_error("Error: $dbinf->{type} is not a supported database at this time") unless $connect;

    foreach my $key (keys %{$dbinf}){
	  $connect =~ s/-$key-/$dbinf->{$key}/;
    }

    @params = ($connect, $dbinf->{user},$dbinf->{password});

    my $hand = DBI->connect(@params);
    if($hand) {
      $self->{CACHE}->{$realname}->{$realclass} = $hand;
      $dbh = $hand;
      #print STDERR "REAL CONNECT\n";
    }else{
	  return $self->_error("Error: Failed to connect to db $name");
    }

  }else{
    print STDERR "no database defined for handle $name\n";
    return undef;
  }
}

  if(lc($flag) eq 'dbh'){
    return $dbh;
  }else{
    my $dbrh = {
		name => $realname,
		class => $realclass,
		dbh => $dbh,
		dbr => $self,
		logger => $self->{logger},
		config => $dbinf
	       };
    my $hclass = 'APOLLO::DBR::DBRH::' . $dbinf->{type};
    return $self->_error("Failed to Load $hclass ($@)") unless eval "require $hclass";
    bless($dbrh,$hclass);
    return $dbrh;
  }

}

sub remap{
      my $self = shift;
      my $class = shift;

      return $self->_error('class must be specified') unless $class;

      $self->{globalclass} = $class;

      return 1;
}

sub unmap{
      my $self = shift;
      undef $self->{globalclass};

      return 1;
}

sub flush_handles{
    my $self = shift;

    foreach my $dbname (keys %{$self->{CACHE}}){
	  foreach my $class (keys %{$self->{CACHE}->{$dbname}}){
		my $dbh = $self->{CACHE}->{$dbname}->{$class};
		$dbh->disconnect();
		delete $self->{CACHE}->{$dbname}->{class};
	  }
    }

    return undef;
}

sub _error {
      my $self = shift;
      my $message = shift;
      my ( $package, $filename, $line, $method) = caller(1);
      if ($self->{logger}){
	    $self->{logger}->logErr($message,$method);
      }else{
	    print STDERR "$message ($method, line $line)\n";
      }
      return undef;
}

sub DESTROY{
    my $self = shift;

    $self->flush_handles();

}

1;
