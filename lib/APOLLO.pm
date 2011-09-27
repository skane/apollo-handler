package APOLLO;
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Except where otherwise specified, this software is Copyright (c) 2001-2003
# Vivendi Universal Net USA.
# Parts of this software are Copyright (c) 2004 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#=======================================================================
#
#  $Id: APOLLO.pm,v 1.33 2010/04/21 18:14:40 impious Exp $
#  $Source: /cvsroot/apollo-handler/apollo-handler/lib/APOLLO.pm,v $
#
#=======================================================================

use strict;

# Kind of an evil hack... Allows for ApolloUtils to be found
BEGIN{
      if(! grep {/apollo-utils/} @INC){
	    my @addlibs = grep {/apollo-handler/i} @INC;
	    map {s/apollo-handler/apollo-utils/i} @addlibs;
	    unshift(@INC,@addlibs);
      }
}

use ApolloUtils::Logger;
use CGI;
use APOLLO::XMLWriter;
use APOLLO::CharSet;



use vars qw(@ISA);


=pod

=head1 CONFIG VARIABLES

=head2 LIST

BaseModule  REQUIRED
TemplateMode Optional (defaults to yasl)
TemplateDir REQUIRED
DenialURL   REQUIRED

ErrorURL    REQUIRED
- OR -
ErrorTemplate

LoginPage   REQUIRED *
LoginBase   REQUIRED *
LoginParams REQUIRED *

DBRConf
SecurityType
LogCustId
DEBUG
NOLOG
NOCUST
LogDir

=cut

sub new {
      my $pkg = shift;
      my %in = @_;
      my $self = {};
      my $function = 'APOLLO::new';

      bless ($self , $pkg);

      $self->{customer} = $in{customer};
      $self->{r} = $in{r};
      $self->{cgi} = $in{cgi};
      $self->{config} = $in{config};
      return $self;
};

sub _Controller_execute {
      my $self = shift;
      my $function = 'APOLLO::_Controller_execute';

      return $self->_error('preinit returned an undefined value') unless
	my $preinit = $self->_Controller_preinit();
      return 1 if $preinit < 0; #bail without an error

      return $self->_error('_Controller_appinit returned a false status') unless
	my $appinit = $self->_Controller_appinit(); # easier than overloading preinit
      return 1 if $appinit < 0; #bail without an error

      return 0 unless $self->_Controller_security();

      return $self->_error('_Controller_begin returned a false status') unless
	$self->_Controller_begin();


      my $cmd = $self->{data}->{cmd};

      if ($cmd) {
	    unless ($cmd =~ /^[A-Za-z][A-Za-z0-9\._]+$/){
		  $self->{DENIAL} = $self->{config}->{DenialURL} || $self->{config}->{ErrorURL};
		  return $self->_error("ERROR! No valid cmd specified. ($cmd)\n");
	    };
	    $self->{logger}->log("Running the command ($cmd)", $function);
	    my $cmdret = eval {
		  $self->$cmd(); # execute the command
	    };

	    if ($@ || !defined $cmdret || $cmdret == 0) {
		  return $self->_error("Command $cmd failed or returned a false return value ($@)"); 
	    }elsif($cmdret == -1){
		  $self->{DENIAL} = $self->{config}->{DenialURL} || $self->{config}->{ErrorURL};
		  return $self->_error("Command $cmd returned Access Denied"); 
	    }
      }

      $self->_Controller_finish();

      $self->{logger}->log("Completed Request", $function) if( defined( $self->{logger} ));

      return 1;
}

sub _Controller_preinit {
      my $self = shift;
      my $function = 'APOLLO::_Controller_preinit';

      $self->{xml} = {};

      $self->{config}->{TemplateMode} ||= 'yasl';
      if(lc($self->{config}->{TemplateMode}) eq 'yasl'){
	    return $self->_error("Failed to Load XMLapi::XMLWriter") unless require XMLapi::XMLWriter;
      }elsif(lc($self->{config}->{TemplateMode}) eq 'fakeyasl'){
	    return $self->_error("Failed to Load APOLLO::FakeYasl") unless require APOLLO::FakeYasl;
      }elsif(lc($self->{config}->{TemplateMode}) eq 'template'){
	    return $self->_error("Failed to Load Template") unless require Template;
      }else{
	    return $self->_error("Error: $self->{config}->{TemplateMode} is not an allowable value for TemplateMode");
      }

      # process form data  ------------------------
      my %data;
      foreach ($self->{cgi}->param()){
            my @array = $self->{cgi}->param($_);

            foreach (@array){
                  my $rv = APOLLO::CharSet::is_valid_utf8(\$_);
                  unless ($rv){
                        $_ = APOLLO::CharSet::latin1_to_utf8($_);
                  };
                  APOLLO::CharSet::strip_ctrl_chars(\$_);
            }

            if (@array > 1){
                  $data{$_} = \@array;
            }else{
                  $data{$_} = $array[0];
            }
      }
      $self->{data} = {%data};

      # process cookies  ------------------------
      my %cookies;
      foreach ($self->{cgi}->cookie()) {
            $cookies{$_} = $self->{cgi}->cookie($_);
      }
      $self->{cookies} = \%cookies;
      $self->{cookie} = $self->{cookies};

	  return $self->_error("failed to create logger") unless
        $self->{logger} = ApolloUtils::Logger->new(
                                                   -bDebug => $self->{config}->{DEBUG}, # Depricated
                                                   -noLog  => $self->{config}->{NOLOG}, # Depricated
                                                   -logLevel => $self->{config}->{LOGLEVEL},
						   -logpath => $self->{config}->{LogDir} . '/' . $self->{config}->{BaseModule} . '.log',
                                                  );


      if ($self->{config}->{DBRConf}) { # bit of a chicken and egg problem here with dbr and logger
	    require DBR;
	    return $self->_error("failed to create dbr") unless
	    $self->{dbr} = DBR->new(
				    -logger => $self->{logger},
			            -conf => $self->{config}->{DBRConf},
				   );
      }

      return $self->_error('_Controller_custinit retruned undefined') unless
	my $custrv = $self->_Controller_custinit();
      return -1 if $custrv < 0; # access denied / bail without an error

      my $userid = $self->{config}->{LOG_CUSTID} || $self->{cust_id};
      if($userid){
	    $self->{logger}->user_id($userid);
	    $self->{logger}->logbase($self->{config}->{LogDir});
      }

      $self->{logger}->log("Started Request", $function);

      # log form data  ------------------------
      foreach my $key (keys %{$self->{data}}){
            $self->{logger}->logDebug("data: $key = $self->{data}->{$key}", $function);
      }
      $self->{data} = {%data};
      # log cookies  ------------------------
      foreach my $key (keys %{$self->{cookies}}){
            $self->{logger}->logDebug("Cookie: $key = $self->{cookies}->{$key}", $function);
      }
      # -------------------------------------------

      $self->{logger}->log("$self->{config}->{BaseModule}\:\:$self->{data}->{class} cmd: $self->{data}->{cmd}", $function);

      return 1;
}

#Login Stub
sub _Controller_custinit{
      my $self = shift;
      return 1;
}

#Application initialisation stub
sub _Controller_appinit{
    return 1;
}

# automatically determine where to send the user for login
sub _Controller_loginURL{
      my $self = shift; # NOTE: no logger or DBR exists yet

      if ($self->{config}->{LoginPage}){
	    return $self->{config}->{LoginPage};
      }

      my $return_url = $self->_Controller_returnURL();

      my $login_url = $self->{config}->{LoginBase};
      return $self->_error("no LoginBase parameter specified!") unless $login_url;
      $login_url .='?';
      if($self->{config}->{LoginParams}){
	    $login_url .= $self->{config}->{LoginParams} . '&';
      }
      $login_url .= "dest=" . $self->{cgi}->escape($return_url);

      return $login_url;
}

sub _Controller_returnURL{
      my $self = shift;
      my $data = shift || $self->{data};

      my $return_url = (($ENV{SERVER_PORT} eq '443')?'https':'http') . '://' . $ENV{HTTP_HOST} . $self->{r}->uri . '?';
      my $ct = 0;
      foreach my $key (keys %{$data}){
	    my $vals = $data->{$key};
	    foreach my $val ((ref($vals) eq 'ARRAY')?(@{$vals}):($vals)){
		  $return_url .= '&' if $ct;
		  $return_url .= ( $self->{cgi}->escape($key) . '=' . $self->{cgi}->escape($val));
		  $ct++;
	    }
      }

      return $return_url;
}

sub _Controller_Cleanup {
      my $function = 'APOLLO::_Controller_Cleanup';
      my $self = shift;
      $self->{logger}->logDebug("Started", $function) if( defined( $self->{logger} ) );
      $self->{dbr}->flush_handles() if( defined( $self->{dbr} ) );
      if( defined ($self->{customer}) ) {
            undef $self->{customer};
      }

      return 1;
}

sub DESTROY {
      my $function = 'APOLLO::DESTROY';
      my $self = shift;
      $self->{logger}->logDebug("DESTROY", $function) if( defined( $self->{logger} ) );

      foreach (keys %{$self}){
	    undef $self->{$_};
      }

      foreach my $parent (@ISA) {
         next if $self->{DESTROY}{$parent}++;
         my $destructor = $parent->can("DESTROY");
         $self->$destructor() if $destructor;
      }
}

sub _Controller_finish {
      my $function = 'APOLLO::_Controller_finish';
      my $self = shift;

      $self->{logger}->logDebug("Started... ", $function);

      # run security post processing if applicable

      foreach my $secobj (@{$self->{security}}){
	  my $sub = ref($secobj) . '::finish';
	  if (eval "exists &$sub"){
	      $self->{logger}->log("running $sub", $function);
	      eval{
		  $secobj->finish()
	      };
	  }
      }

      # save cookies ///////////////////
      my $vhost = $self->{cgi}->virtual_host();
      my $domain;
      if($vhost =~ /(\.[^.]+\.[A-Za-z]{2,3})$/){
            $domain = $1;
      }else{
	 $domain = $vhost;
      }
      my $cookie;
      foreach my $key (keys %{$self->{cookies}}){

	    my %cookie_param = (
				'-path'    => '/',
				'-domain'  => $domain,
				'-name'    => $key,
				'-expires' => '+2y',
			       );
	    my $setflag = 0;
	    my $cval = $self->{cookies}->{$key};
	    my $value;
	    if(ref($cval) eq 'HASH'){
		  $value = $cval->{'-value'};
		  map { $cookie_param{$_} = $cval->{$_} } keys %{$cval};
	    }else{
		  $value = $cval;
	    }

	    $cookie_param{-value} = $value; #yes, this is intentional

	    if( length($value) > 0 ){
		  if($self->{cgi}->cookie($key) ne $cval){
			$setflag = 1;
		  }
	    }else{
		  $cookie_param{-expires} = 'Thursday, 01-Jan-1970 10:00:00 GMT';
		  $cookie_param{-value} = '';
		  $setflag = 1;
	    }

	    if ($setflag){
		  $cookie = $self->{cgi}->cookie(%cookie_param);
                  $self->{r}->err_headers_out->add( "Set-Cookie" => $cookie );
	    };

      }

      if( defined $self->{customer} )
      {
      	    $self->{customer}->flush();
      	    undef $self->{customer};
      }
      # ////////////////////////////////
      return 1;
}

sub _Controller_begin {
      my $self = shift;

      foreach (keys %{$self->{data}}){ # do this now (after security)
	    $self->{xml}->{$_} = $self->{data}->{$_};
      }
      return 1;
}

=pod

=head1 XMLrecurse

=head2 DESCRIPTION

    Hashrefs are interpreted to create elements who's name is the hash key and who's value is the hash value.
    The value can be another hashref, an arrayref or a plain value.

    Arrayrefs are combined with hashrefs to create multiple instances of that element

    Plain values are interpreted as being value elements.

=cut

sub _XMLrecurse{
      my ($self,$key,$val,$xw) = @_;
      my $ref=ref($val);
      if ($ref eq 'HASH'){
	    $xw->starttag($key);
	    foreach (keys %{$val}){
		  _XMLrecurse($self,$_,$val->{$_},$xw);
	    }
	    $xw->endtag($key);
      }elsif($ref eq 'ARRAY'){
	    foreach (@{$val}){
		  _XMLrecurse($self,$key,$_,$xw);
	    }
      }else{
	      if ($key ne '' && ($val ne '' || $self->{ALLOW_BLANK_XMLTAGS} )){
		      $xw->element($key,$val);
	      }
      }

}

sub _Controller_publish {
      my $self = shift;
      my $function = 'APOLLO::_Controller_publish';
      my $cnt;
      $self->{logger}->logDebug("Started...",$function);

      if ($self->{REDIRECT}) {

	  my ($baseurl,$extraurl);
	  if(ref($self->{REDIRECT}) eq 'ARRAY'){
	      my $extrahash;
	      ($baseurl,$extrahash) = @{$self->{REDIRECT}};
	      if(ref($extrahash) eq 'HASH'){
                    my ($base_has_args) = $baseurl =~ m!(\?)!;
		  foreach my $key (keys %{$extrahash}){
		      my $ref = $extrahash->{$key};
		      $ref = [$ref] unless ref($ref) eq 'ARRAY';
		      foreach my $val (@{$ref}){
			  if ($base_has_args || $extraurl ne ''){$extraurl .= '&'}else{$extraurl .= '?'};
			  $extraurl .= $key . '=' . $self->{cgi}->escape($val);
		      }
		  }
	      }
	  }else{
	      $baseurl = $self->{REDIRECT};
	  }

	  my $url = $baseurl . $extraurl;

	  $self->{r}->status(302);
	  unless ($url =~ /^https?:\/\//){

	      if ($ENV{SCRIPT_URI} && $ENV{HTTP_HOST}) {
		  my $base = $ENV{SCRIPT_URI};
		  my $host = $ENV{HTTP_HOST};
		  $base =~ s/^(.*?\:\/\/).*?(\/)/$1$host$2/;

		  if ($url =~ /^\//) {
		      $base =~ s/^(.*?\:\/\/.*?\/).*$/$1/;
		  } else {
		      $base =~ s/^(.*?\:\/\/.*\/).*$/$1/;
		  }
		  $url = $base . $url;
	      }
	  }
	  $self->{logger}->log("REDIRECT to $url", $function);
	  $self->{r}->header_out('Location' => $url);
	  $self->{r}->send_http_header();
	  return 1;
      }

      if ($self->{RAW_OUT}) {
	    my $param = $self->{RAW_OUT};
	    if(ref($param) ne 'HASH'){
		  $param = {
			    type => 'text/plain',
			    data => $param
			   }
	    }
	    return $self->_error('Error: $self->{RAW_OUT}->{type} and ->{data|handle} must be specified in raw mode!') unless ($param->{type} && $param->{data} || $param->{handle});
	    $self->{r}->content_type($param->{type} || 'text/plain');

	    if($param->{header}) {
		  return $self->_error('Error: $self->{RAW_OUT}->{header} must be a hash!') unless ref( $param->{header} ) eq 'HASH';
		  $self->{r}->header_out(%{$param->{header}});
	    }

	    $self->{r}->send_http_header();
	    if($param->{handle}){
		  my $buff;
		  while (read($param->{handle},$buff,1024)){
			print $buff;
		  }
		  close $param->{handle};
	    }else{
		  print STDOUT $param->{data};
	    }

	    return 1;
      }

      my $tmpl = $self->{data}->{template};
      $tmpl ||= $self->{template};

      $self->{RAW} ||= $self->{data}->{raw};
      return $self->_error("Error: No Template specified!") unless ($tmpl || $self->{RAW});
      return $self->_error("Error: Xml parameter is undefined!") unless defined($self->{xml});

      ###############################write out the xml / parse the template ######################-------

      my $xw;
      my $template = "$self->{config}->{TemplateDir}/$tmpl";

      my $mode = lc($self->{config}->{TemplateMode});

      # the raw flag takes precidence over everything, after that we evaluate yasl vs fakeyasl.

      if($self->{RAW}) { #### RAW
	    $self->{logger}->log("Writing raw xml", $function);
	    $self->{r}->content_type('text/plain');
	    $self->{r}->send_http_header();
	    $xw = new APOLLO::XMLWriter(\*STDOUT);
      }elsif ($mode eq 'yasl') { #### YASL
	    $self->{logger}->logDebug("Writing the XML on template $self->{config}->{TemplateDir}/$tmpl", $function);
	    $xw = new XMLapi::XMLWriter();
	    $xw->set_input_charset('utf-8');
      }



      if ($self->{RAW}) { ### RAW
	    _XMLrecurse($self,'root',$self->{xml},$xw);

      }elsif($mode eq 'yasl'){### YASL 
	    _XMLrecurse($self,'root',$self->{xml},$xw);
	    $self->{r}->notes("XML_HANDLE" , $xw->handle());
	    $self->{r}->internal_redirect($template);

      } elsif($mode eq 'template') { #### Template Toolkit
	    if ($template) {
		  $template =~ s/^\///g;
		  # create Template object
		  $self->{logger}->logDebug("Using Template toolkit to write XML on template $self->{config}->{TemplateDir}/$tmpl", $function);

		  my $ttkcfg = {
				INCLUDE_PATH => [ $self->{r}->document_root() ],
				INTERPOLATE  => 0,
				POST_CHOMP   => 2,
				PRE_CHOMP => 1,
				TRIM => 1,
				#EVAL_PERL    => 1, # evaluate Perl code blocks
			       };

		  if ($self->{pre_template}){
			$ttkcfg->{PRE_PROCESS} = $self->{pre_template};
			$ttkcfg->{PRE_PROCESS} =~ s/^\///g;
		  }
		  if ($self->{post_template}){
			$ttkcfg->{POST_PROCESS} = $self->{post_template};
			$ttkcfg->{POST_PROCESS} =~ s/^\///g;
		  }
		  my $ttk = Template->new($ttkcfg) or return $self->_error( 'new TT object failed' );

		  my $output;
		  $ttk->process( $template, $self->{xml}, \$output) or return $self->_error( "Template Toolkit Error: " . $ttk->error() );

		  $self->{'content-type'} ||= 'text/html';
		  $self->{r}->content_type($self->{'content-type'});
		  $self->{r}->send_http_header();
		  print $output;

	    } else {
		  return $self->_error("Error: No template specified!");
	    }
      }elsif($mode eq 'fakeyasl') { #### FAKEYASL
	    if ($template) {
		  $self->{logger}->logDebug("Using FakeYasl to write XML on template $self->{config}->{TemplateDir}/$tmpl", $function);
		  my $output = APOLLO::FakeYasl::parse(
						       docroot  => $self->{r}->document_root(),
						       template => $template,
						       ref      => $self->{xml}
						      );
		  return $self->_error("No data was returned by FakeYasl parser!") unless defined $output;
		  $self->{'content-type'} ||= 'text/html';
		  $self->{r}->content_type($self->{'content-type'});
		  $self->{r}->send_http_header();
		  print $output;
	    } else {
		  return $self->_error("Error: No template specified!");
	    }
      }

      $self->{logger}->logDebug("Done with writeXML",$function);

      return 1;
}

sub _Controller_security {
      my $function = 'APOLLO::_Controller_security';
      my $self = shift;

      $self->{logger}->logDebug("Started... ($self->{config}->{SECURITY_TYPE}) ", $function);

      my $types = $self->{config}->{SecurityType} || $self->{config}->{SECURITY_TYPE};

      $types ||= 'NONE';

      if($types =~ /NONE/i){
	    return 1;
      }else{
	  $types =~ s/^\s+//;
	  $types =~ s/\s+$//;

	  my @types = split(/\s+/,$types);

	  $self->{security} = [];
	  foreach my $name (@types){
	      if ($name =~ s/^SELF_//) {
		  my $rv = eval { $self->$name() };
		  unless ($rv){
		      $self->{DENIAL} = $self->{config}->{DenialURL};
		      $self->{logger}->log('ACCESS DENIED! redirecting to denial page',$function);
		  }
		  return 0 unless $rv;
	      } else {
		  my $secobj = {};
		  my $class = 'APOLLO::Security::' . $name;

		  if (eval "require $class") {
		      my $object;
		      my $rv = eval "\$object = new $class(-controller => \$self)";
		      if($rv){
			  $rv = eval {
			      $object->enforce(); # execute the command
			  };
		      }
		      unless ($rv){
			  $self->{DENIAL} = $self->{config}->{DenialURL};
			  $self->{logger}->log('ACCESS DENIED! redirecting to denial page',$function);
			  return 0;
		      }
		      push @{$self->{security}}, $object;
		  } else {
		      $self->{DENIAL} = $self->{config}->{ErrorPage};
		      $self->_error("$name Failed to load or is not a valid security module");
		      return 0;
		  }
	      }
	  }
      }
      return 1;
}

sub REDIRECT {
      my $self = shift;
      my $url = shift;
      my (%extra) = (@_);

      $self->{REDIRECT} = [$url,\%extra];
      return 1;
}

sub _error {
      my $self = shift;
      my $message = shift;
      my ( $package, $filename, $line, $method) = caller(1);

      if ($self->{logger}){
	    $self->{logger}->logErr($message,$method);
      }else{
	    print STDERR "$message ($method)\n";
      }
      push @{$self->{_error}||=[]}, "$message ($method)";

      return undef;
}

sub _usererr {
      my $self = shift;
      my %errors = @_;

      map {$self->{xml}->{ERROR}->{$_} = $errors{$_}} keys %errors;

      return 1;
}


=pod

=head1 _formcheck

the _formcheck method allows you to perform basic form validation of the data recieved from the user.
you specify a set of fieldnames and regular expressions to compare them against. these regexs are run against the appropriate field is $self->{data}


=head2 parameters:

-fields

use the fields parameter to specify either a hash or an array of key => 'regex' pairs
optionally an arrayref of ['regex','errorcode'] may be spefified instead of regex

-return

specifies weather the errors should be reported in $self->{xml} or if they should be returned as a hashref of key => 'errorcode' pairs

-error_tag

specifies the xml subtag for the error codes to go into. defaults to 'ERROR'

-multerror

specifies weather more than one errorcode should be returned. only the first error code is returned if this is false.

=head2 usage:


$self->_formcheck(
                  -fields => {
                              fieldA => '.',
                              fieldB => '.',
                             }
                 );

$self->_formcheck(
                  -fields => [
                              fieldA => '.',
                              fieldA => '^.+@.+$',
                              fieldB => '.',
                             ]
                 );

=head2 optional "quick" usage:

all parameters are defaulted. the -fields parameter is derrived from the input array of the method

$self->_formcheck(
                  fieldA => '.',
                  fieldA => '^.+@.+$',
                  fieldB => '.',
                 );

=cut


sub _formcheck{
      my $self = shift;
      my @params = @_;
      my %params = @params;
      unless ($params{-fields}) {
	    %params = ();
	    $params{-fields} = [@params];
      }

      my %errors;

      $params{-return} = uc($params{-return}) || 'XML';
      $params{-error_tag} ||= 'ERROR';
      $params{-multerrors} ||= 0;

      my @flds;
      @flds = @{$params{-fields}} if ref($params{-fields}) eq 'ARRAY';
      @flds = %{$params{-fields}} if ref($params{-fields}) eq 'HASH';
      my %keycounter;
      while (@flds) {
	    my ($key,$spec) = (shift @flds,shift @flds);
	    $keycounter{$key}++;
	    my $val = $self->{data}->{$key};
	    my ($regex,$errcode);
	    if (ref($spec) eq 'ARRAY') {
		  ($regex,$errcode) = @{$spec};
	    } else {
		  $regex = $spec;
		  $errcode = $keycounter{$key};
	    }

	    unless($val =~ /$regex/){
		  if ($errors{$key}) {
			if ($params{-multerrors}) {
			      $errors{$key} = [$errors{$key}] unless ref($errors{$key}) eq 'ARRAY';
			      push @{$errors{$key}}, $errcode;
			}
		  } else {
			$errors{$key} = $errcode;
		  }
	    }

      }

      if ($params{-return} eq 'XML') {
            if (%errors) {
		  map {$self->{xml}->{$params{-error_tag}}->{$_} = $errors{$_}} keys %errors
	    }
	    return scalar(keys %errors);
      } elsif (($params{-return} eq 'HASH')) {
	    return \%errors;
      }
}

1;
