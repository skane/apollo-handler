package Apache::ApolloHandler;
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Except where otherwise specified, this software is Copyright (c) 2001-2003
# Vivendi Universal Net USA.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#=======================================================================
#
#  $Id: ApolloHandler.pm,v 1.4 2006/11/09 18:45:11 impious Exp $
#  $Source: /cvsroot/apollo-handler/apollo-handler/lib/Apache/ApolloHandler.pm,v $
#
#=======================================================================

use strict;
use CGI;
use Apache::Constants qw(:common);
use vars qw(@INC_CACHE);

sub handler {
      # modperl #INC hack
      my %uniq_inc;
      @INC = grep {!$uniq_inc{$_}++} (@INC_CACHE,@INC);
      # End hack

      #### Apache reqeust object
      my $r = shift;

      my $function = 'handler';
      my $cgi = new CGI;

      my $config = $r->dir_config();
      my $basemod = $config->{BaseModule};

      if ($config->{NoCache}){
	      $r->no_cache(1);
      }
      unless ($basemod){
	      print STDERR "ERROR! No BaseModule specified. (apache conf)\n";
	      return cleanup(OK);
      }

      my $tmp_basemod = $basemod;
      $tmp_basemod =~ s/\:\:/\./g;
      my $class = $tmp_basemod . '.' . $cgi->param('class');
      $class =~ s/\.$//;
      unless ($class =~ /^[A-Za-z0-9\._]+$/){
	    print STDERR "ERROR! No valid class specified. ($class)\n";
	    denial($r, $config->{ErrorURL} || $config->{DenialURL});
	    return cleanup(OK);
      };
      $class =~ s/\./::/g;

      #/////////////////////////////////////////////////////////////////////////////////
      # create new handle
      my %params = (
		    cgi      => $cgi,
		    r        => $r,
		    config   => $config,
		   );
      my $controller;
      my $a = eval "require $class";
      my $b;
      if ($a){
	      $b = eval "\$controller = new $class(\%params)";
      }
      #/////////////////////////////////////////////////////////////////////////////////


      # There has to be at least a cmd and a template past in or I'm going to send you back to the beginning..
      unless (ref($controller) =~ /^$basemod/){
	    if (!$a){
		  print STDERR "$@\nERROR! Class '$class' failed to load\n";
	    }else{
		  print STDERR "$@\nERROR! Creation of '$class' Object failed\n";
	    }
	    denial($r,$config->{ErrorURL} || $config->{DenialURL});
	    return cleanup(OK);
      }

      my $rv = $controller->_Controller_execute();

      my $errorpage = $config->{ErrorURL};
      $errorpage  ||= $config->{DenialURL};

      if (($rv != 1) || $controller->{DENIAL}) {
	    if ((!$controller->{DENIAL}) && $config->{ErrorTemplate}) {
		  $controller->{xml} = {errors => $controller->{_error}};
		  $controller->{template} = $config->{ErrorTemplate};
		  delete $controller->{REDIRECT};
		  delete $controller->{RAW_OUT};
	    } else {
		  my $url = $errorpage;

		  if ($controller->{DENIAL}) {
			if ( length($controller->{DENIAL}) > 1) {
			      $url = $controller->{DENIAL};
			} elsif ($config->{DenialURL}) {
			      $url = $config->{DenialURL};
			}
		  }
		  print STDERR "Apollo Controller: $rv ... $controller->{DENIAL}\n";
		  print STDERR "Apollo Controller: Access Denied! redirecting to $url\n";
		  return undef unless denial($r,$url);
		  $controller->_Controller_Cleanup;
		  return cleanup(OK);
	    }
      }

      denial($r,$errorpage) unless $controller->_Controller_publish;
      $controller->_Controller_Cleanup;
      return cleanup(OK);

}

sub denial {
	my $r = shift;
	my $url = shift;
	$r->status(302);
	return undef unless $url;
	$r->header_out('Location' => $url);
	$r->send_http_header();
	return 1;
}

sub cleanup {
   my $status = shift;
    @INC_CACHE = @INC;
    return $status;
}

1;
