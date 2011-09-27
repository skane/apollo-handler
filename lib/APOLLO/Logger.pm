# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Except where otherwise specified, this software is Copyright (c) 2001-2003
# Vivendi Universal Net USA.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# $Id: Logger.pm,v 1.7 2005/09/20 17:21:42 impious Exp $
# $Source: /cvsroot/apollo-handler/apollo-handler/lib/APOLLO/Logger.pm,v $
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package APOLLO::Logger;

use vars qw(@ISA @EXPORT);

@ISA = ('Exporter');

use strict;
use Carp;
use FileHandle;

#global DEBUG logging flag
my $DEBUG = 0;

=pod

=head1 NAME

APOLLO::Logger


=head1 SYNOPSIS

  use APOLLO::Logger;

  $logger = new APOLLO::Logger( [ -customer => $customer_obj,
                                        -cust_id  => $customer_id,
                                        -bDebug   => $boolDebug,
                                        -noLog    => $boolNoLog,
                                        -logpath  => $alternatePath ]
                                    );

=head1 DESCRIPTION

The purpose of the Logger Object is to log script information 
on a per customer basis, as well as keep a transaction log of
all DB related API Calls.

=head1 METHODS

=head2 new (Constructor)

=over 4

=item B<-customer>

=item B<-cust_id>

=item B<-bDebug>

=item B<-noLog>

=item B<-logpath>

=back

=cut

sub new {
  my( $pkg, %in ) = @_;
   
  my( $self ) = {};
  
  bless( $self, $pkg );

  $self->{bLog} = ( defined( $in{-noLog} ) )?0:1;

  $self->{bDebug} = ( $in{-bDebug} )?1:0;

  $self->{logbase} =  ( $in{-logpath} )?$in{-logpath}:'';
  
  if( ref $in{-customer} ) {
    $self->{cust_id} = $in{-customer}->getValue('cust_id');
    $self->{customer} = $in{-customer};
  } elsif( $in{-cust_id} ) {
    $self->{cust_id} = $in{-cust_id};
  }
 
  return( $self );
}

=pod

=head2 log

This method provides logging on a per customer basis. If a reference to a
logging sub was passed in on object creation, this methods merely hands off 
the logging. If no customer was provided, B<Logger>'s LogDebug is called

=cut
# ____ _____________________________________________________
sub log {
  my( $self )   = shift;
  my( $msg )    = shift;
  my( $caller ) = shift;
  my( $type )   = shift;
  my( $logname )= shift;

  return unless( $self->{bLog} );
  
  if( $self->{cust_id} || $logname ) {

    my($s,$m,$h,$D,$M,$Y) = getTime();
    my $log = $logname;
    my $fh;

    $type ||= 'INFO';
    $log  ||= 'session';

    #standard session logging

    if( defined( $self->{"${log}Handle"} ) ) {

      $fh = $self->{"${log}Handle"};

    } else {

      my $logpath;

      if( $logname ) {

        $logpath = "$self->{logbase}-${log}.log";
          
      } else {
	my $cust_id = (('0'x(9 - length ($self->{cust_id}))) . $self->{cust_id});

        my( $cust_a ) = substr( $cust_id, 0, 3 );
        my( $cust_b ) = substr( $cust_id, 3, 3 );
        my( $path )   = "$self->{logbase}-${log}logs/$cust_a/$cust_b/";
        
        # make sure the dir structure is there
        unless( -d $path ) {
          my( $sub_a ) = "$self->{logbase}-${log}logs/$cust_a/";
          unless( -d $sub_a ) {
            my( $logbase ) = "$self->{logbase}-${log}logs/";
            unless( -d $logbase ) {
              my( $root ) = ( $logbase =~ m|^(.*/).*logs/$| );
              unless( -d $root ) {
                mkdir( $root, 0775 ) || print STDERR "APOLLO::Logger: Failed to mkdir $root\n";
              }
              mkdir( $logbase, 0775 ) || print STDERR "APOLLO::Logger: Failed to mkdir $logbase\n";
            }
            mkdir( $sub_a, 0775 ) || print STDERR "APOLLO::Logger: Failed to mkdir $sub_a\n";
          }
          mkdir( $path, 0775 ) || print STDERR "APOLLO::Logger: Failed to mkdir $path\n";
        }
        
        $logpath = "$path$cust_id";

      } 

      $fh = new FileHandle;
      $fh->autoflush(1);

      sysopen( $fh, $logpath, O_WRONLY|O_CREAT|O_APPEND, 0666 ) || print STDERR "APOLLO::Logger: FAILED to open log $logpath\n";

      $self->{"${log}Handle"} = $fh;
  
      $self->logDebug( "New Logger $logpath opened by $caller",'APOLLO::Logger' );
    }

    print $fh "$Y$M$D$h$m$s\t$type\t$caller\t$msg\n";

  } else {
    $self->logDebug("$msg -- no email");
  }
}

=pod

=head2 logErr

wrapper around log for error related logging.

=cut
# ____ _logErr ________________________________________________________
sub logErr {
  my( $self )   = shift;
  my( $msg )    = shift;
  my( $caller ) = shift;

  return unless( $self->{bLog} );
  
  $self->log( $msg, $caller, 'ERROR' );
  
}

=pod

=head2 logSecurity

wrapper around log for security related logging. 

=cut
# ____ logSecurity ________________________________________________________
sub logSecurity {
  my( $self )   = shift;
  my( $msg )    = shift;
  my( $caller ) = shift;

  return unless( $self->{bLog} );
  
  $self->log( $msg, $caller, 'SECURITY' );
  $self->log( $msg, $caller, 'SECURITY', 'security' );
}

=pod

=head2 logDebug

wrapper around log for debug related logging. 

=cut

# ____ logDebug ________________________________________________________
sub logDebug {
  my( $self )   = shift;
  my( $msg )    = shift;
  my( $caller ) = shift;

  return unless( $self->{bLog} );
  return unless( $self->{bDebug} );
  
  $self->log( $msg, $caller, 'DEBUG' );
}

=pod

=head2 logWarn

wrapper around log for warning related logging. 

=cut

# ____ logWarn ________________________________________________________
sub logWarn {
  my( $self )   = shift;
  my( $msg )    = shift;
  my( $caller ) = shift;

  return unless( $self->{bLog} );
  
  $self->log( $msg, $caller, 'WARN' );
  $self->log( $msg, $caller, 'WARN', 'warn' );
}

=pod

=head2 logTransaction

wrapper around log for warning related logging. 

=cut
# ____ logTransaction ________________________________________________________
sub logTransaction {
  my( $self )   = shift;
  my( $msg )    = shift;
  my( $caller ) = shift;

  $self->log( $msg, $caller, 'TRANS', 'transaction' );
}

=pod

=head2 DESTROY (destructor)

=cut
# ____ DESTROY ________________________________________________________
sub DESTROY {
  my( $self ) = shift;

  # close the log filehandle1
  if( defined( $self->{logHandle} ) ) {
    close $self->{logHandle};
    undef $self->{logHandle};
  }
 
}

=pod

=head2 getTime

accepts null or unix time as input (if null, current time is assumed)
returns an array like localtime, except that year is adjust to 4 digits and
month is 1-12 instead of 0-11

=cut
# ____ getTime _______________________________________________________________
sub getTime {
  my($time) = @_;
  $time ||= time;
  my(@time) = localtime($time);
  $time[4]++;
  my($i);
  for($i=0;$i<=$#time;$i++) {
    if (length($time[$i])<2) {
      $time[$i] = "0$time[$i]";
    }
  }
  
  $time[5] += 1900;
  
  return(@time);
}
1;
