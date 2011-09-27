package APOLLO::Security::MD5ID;
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Except where otherwise specified, this software is Copyright (c) 2001-2003
# Vivendi Universal Net USA.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#=======================================================================
#
#  $Id: MD5ID.pm,v 1.7 2005/09/20 17:21:42 impious Exp $
#  $Source: /cvsroot/apollo-handler/apollo-handler/lib/APOLLO/Security/MD5ID.pm,v $
#
#=======================================================================

use vars qw(@ISA);

use strict;
use Digest::MD5  qw(md5_hex);
use APOLLO::Security;
@ISA = ('APOLLO::Security');

sub new{
    my $package = shift;
    my %params = @_;

    my $self = {
	        privkey => $params{-privkey},
		regex => $params{-regex},
		logger => $params{-logger},
	       };


    if($params{-controller}){
	my $c = $params{-controller};
	$self->{privkey} = $c->{config}->{MD5ID_PRIVKEY};
	$self->{regex} = $c->{config}->{MD5ID_REGEX};
	$self->{logger} = $c->{logger};
	$self->{data} = $c->{data};
	$self->{xml} = $c->{xml};

	$self->{CONTROLLER} = $params{-controller};
    }

    bless($self,$package);

    return $self->_error('no -privkey specified') unless $self->{privkey};
    return $self->_error('no -logger specified')  unless $self->{logger};

    return $self;

}

sub enforce{
      my $self = shift;
      my $function = 'APOLLO::Security::MD5ID::enforce';

      $self->{logger}->log("Started... ", $function);
      
      return undef unless $self->{CONTROLLER};

      my $error = 0;
      foreach my $key (keys %{$self->{data}}) {
	    if ($key =~ /$self->{regex}/) {
		  if ($self->_is_signed($self->{data}->{$key})){
			unless($self->_is_validsig($key,$self->{data}->{$key})){
			      $self->{logger}->log("$key does not authenticate",$function);
			      delete $self->{data}->{$key};
			      $error++;
			}
			$self->{data}->{$key} = $self->_strip_sig($self->{data}->{$key});
		  }else{
			$self->{logger}->log("$key is not signed... deleting",$function);
			delete $self->{data}->{$key};
		  }
	    }

      }

      if ($error){
	    $self->{logger}->log("one or more authentication errors was reported. Security failed",$function);
	    return 0;
      }
      return 1
}

sub finish{
      my $self = shift;
      my $function = 'APOLLO::Security::MD5ID::finish';

       return undef unless $self->{CONTROLLER};

      $self->{logger}->log("Started... ", $function);

      $self->_sig_recurse(1,$self->{xml});

      my $rd = $self->{CONTROLLER}->{REDIRECT};

      if(ref($rd) eq 'ARRAY'){
	    my $ref = $rd->[1];
	    if(ref($ref) eq 'HASH'){
		  $self->_sig_recurse(0,$rd);
	    }
      }
      return 1;

}

sub _sig_recurse{
      my $self = shift;
      my ($unsg_flag,$val,$prevkey) = @_;

      my $ref=ref($val);

      if ($ref eq 'HASH'){
	    foreach my $key (keys %{$val}){
		  if (ref($val->{$key})){
			$self->_sig_recurse($unsg_flag,$val->{$key},$key);
		  }elsif($key =~ /$self->{regex}/){
		      unless($self->_is_signed($val->{$key})){ # cheap hack to prevent from double signing values
			  if($unsg_flag){
			      $val->{$key . '_unsigned'} = $val->{$key};
			  }
			  $val->{$key} = $self->signval($key,$val->{$key});
		      }
		  }
	    }
      }
      elsif($ref eq 'ARRAY'){
	    my $el;
	    for ($el = 0; $el < scalar(@{$val});$el++){
		  my $element = $val->[$el];
		  if (ref($element)){
			$self->_sig_recurse($unsg_flag,$element,$prevkey);
		  }elsif($prevkey =~ /$self->{regex}/){
			$val->[$el] = $self->signval($prevkey,$element);
		  }
	    }
      }

}

sub signval{
      my $self = shift;
      my $key = shift;
      my $val = shift;

      my $data = "$val-$key-$self->{privkey}";
      my $digest = md5_hex($data);

      return  "$val-sig$digest";
}

sub _is_signed{
      my $self = shift;
      my $val = shift;
      return 1 if $val =~ /-sig[a-z0-9]{32}$/s;
      return 0;
}

sub _strip_sig{
      my $self = shift;
      my $val = shift;
      $val =~ s/-sig[a-z0-9]{32}$//s;
      return $val;
}

sub _is_validsig{
      my $self = shift;
      my $key = shift;
      my $sig = shift;

      return 0 unless $sig =~ /^(.*)-sig([a-z0-9]{32})$/s;

      my $val = $1;
      my $md5sum = $2;

      my $data = "$val-$key-$self->{privkey}";
      my $digest = md5_hex($data);

      return 1 if $digest eq $md5sum;
      return 0;

}

1;
