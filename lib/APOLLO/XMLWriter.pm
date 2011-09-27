package APOLLO::XMLWriter ;
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Except where otherwise specified, this software is Copyright (c) 2001-2003
# Vivendi Universal Net USA.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#    $Id: XMLWriter.pm,v 1.2 2004/02/27 03:14:10 impious Exp $
#    $Source: /cvsroot/apollo-handler/apollo-handler/lib/APOLLO/XMLWriter.pm,v $
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#
# Written by Matt DiMeo.
#
#  Usage:
#  
#  $fh = new IO::File(">outfile.xml") ;
#  $writer = new APOLLO::XMLWriter($fh) ;
#  $fh->print(qq[<?xml version="1.0" ?>\n] ;
#  $writer->starttag("Artist", "artist_id"=>12939) ;
#    $writer->element("name", "Red Delicious") ;
#  $writer->endtag() ;
#  $fh->close() ;


# you can change these to empty strings to save file size and parse time.
use constant XML_INDENT_STRING => "  " ;
use constant XML_NEWLINE => "\n" ;

use strict ;
use Carp ;

####
# Constructor.
# Just takes a filehandle to write to.
####
sub new 
{
  my ($package, $fh) = @_ ;
  my $self = { FH=>$fh,
               INDENT=>0,
	       TAGSTACK=>[],
	       CHARSETSTACK=>[],
	       UTF8_INPUT => 0,
	     } ;
  
  bless $self, $package ;
}

####
# Method to print an xml start tag.
#
#  Call like this:
#    $writer->starttag("song", "song_id"=>1234).
#  This will generate <song song_id="1234"> 
####
sub starttag
{
  my ($self, $tag, @params) = @_ ;
  my $fh = $self->{FH} ;
  my $params = "" ;
  while (@params) {
    my $param = shift @params ;
    my $paramval = shift(@params) || croak "must provide values for all params" ;
    $params .= qq/ $param="/ . mangle($paramval) . qq/"/ ;
  }

  # indent by the number of tags on the stack.
  my $indent = XML_INDENT_STRING x scalar(@{$self->{TAGSTACK}}) ;
  print $fh $indent, "<$tag$params>" . XML_NEWLINE ;
  push @{$self->{TAGSTACK}}, $tag ;
}

####
# Print an xml end tag and decrement the indent.
# You don't need to provide the tag name (since we get it from the
# stack), but if you do, it will make sure they match.
####
sub endtag
{
  my ($self, $checktag) = @_ ;
  my $fh = $self->{FH} ;
  my $tag = pop(@{$self->{TAGSTACK}}) ;

  if (defined($checktag) && $checktag ne $tag) {
    croak "Tag mismatch... expected $tag, got $checktag" ;
  }

  my $indent = XML_INDENT_STRING x scalar(@{$self->{TAGSTACK}}) ;
  print $fh $indent, "</$tag>" . XML_NEWLINE ;
}

####
# Prints a complete xml element with start and end tags bordering characters.
####
sub element
{
  my ($self, $tag, $chars) = @_ ;
#Carp::cluck("undef") if (!defined $chars) ;
  my $fh = $self->{FH} ;

  my $indent = XML_INDENT_STRING x scalar(@{$self->{TAGSTACK}}) ;
  print $fh $indent, "<$tag>",
        $self->{UTF8_INPUT} ? mangle_already_utf8($chars) : mangle($chars), 
	"</$tag>" . XML_NEWLINE ;
}

sub mangle
{
  my ($package,$chars) = @_ ;   # this is so you can call mangle as a method
  $chars = $package if @_==1 ;  #    (for subclassing) or as a function.

  $chars =~ s/\&/\&amp;/g ;
  $chars =~ s/</\&lt;/g ;
  $chars =~ s/>/\&gt;/g ;
  
  $chars =~ s/([\200-\377])/"&#".ord($1).";"/ge ;
  
  return $chars ;
}

sub mangle_already_utf8
{
  my ($package,$chars) = @_ ;   # this is so you can call mangle as a method
  $chars = $package if @_==1 ;  #    (for subclassing) or as a function.

  $chars =~ s/\&/\&amp;/g ;
  $chars =~ s/</\&lt;/g ;
  $chars =~ s/>/\&gt;/g ;

  return $chars ;
}

####
# Sets the input character set, either iso-8859-1 or utf-8
####
sub set_input_charset
{
  my ($self, $charset) = @_ ;

  $charset = lc $charset ;
  if ($charset eq 'utf-8') {
    $self->{UTF8_INPUT} = 1 ;
  } elsif ($charset eq 'iso-8859-1' or $charset eq 'latin-1') {
    $self->{UTF8_INPUT} = 0 ;
  } else {
    # More charsets should probably not be added here.  Anything else
    # should be converted to utf-8 before being used with any xmlwriter.
    die "unsupported charset $charset" ;
  }
}

####
# Set the input charset, saving the old one on a stack for later
# retrieval.
####
sub push_input_charset
{
  my ($self, $charset) = @_ ;
  push @{$self->{CHARSETSTACK}}, $self->{UTF8_INPUT} ;
  $self->set_input_charset($charset) ;
}

sub pop_input_charset
{
  my ($self) = @_ ;
  $self->{UTF8_INPUT} = pop @{$self->{CHARSETSTACK}} ;
}

1 ;
