# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Except where otherwise specified, this software is Copyright (c) 2001-2003
# Vivendi Universal Net USA.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation. 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#    $Id: CharSet.pm,v 1.2 2004/02/27 03:14:10 impious Exp $
#    $Source: /cvsroot/apollo-handler/apollo-handler/lib/APOLLO/CharSet.pm,v $
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package APOLLO::CharSet ;

use Unicode::String () ;
use Unicode::Map8 () ;
use Exporter ;

@ISA = qw(Exporter) ;
@EXPORT_OK = qw(latin1_to_utf8 utf8_to_latin1 is_valid_ascii is_valid_utf8 can_be_latin1 utf8_regex_prepare) ;

use strict ;


sub is_valid_ascii
{
	my ($string) = @_;

	if ($$string =~ /[\x80-\xFF]/) #anything above 127? not ascii...
	{
		return 0;
	}
	return 1;
}

sub can_be_latin1 # used on utf8 strings only other return BS results
{
	my ($string) = @_;
	
	if ($$string !~ /[\x80-\xFF]/) # all ascii, good to go.
	{
		return 1;
	}
	elsif ($$string =~ /[\xC4-\xFF]/) # would map to a character above 256 if UTF
	{
		return 0;
	}
	# looks fine then
	return 1;
}

sub is_valid_utf8
{
	my ($string) = @_;
	if ($$string !~ /[\x80-\xFF]/) # easiest and most likely case.
	{
		return 1;
	}

	my @str = split //, $$string;
	my $i = 0;
	my $len = length($$string);
	my $state = 0;

	for ($i = 0; $i < $len; $i++)
	{
		my $val = ord($str[$i]);
		if ($state == 0)
		{
			if ( $val >= 0xC0 && $val <= 0xDF) # We should be getting one more byte for this char
			{
				$state = 1;
			}
			elsif ( $val >= 0xE0 && $val <= 0xEF) # We should be getting two more bytes for this char.
			{
				$state = 2;
			}
			elsif ( $val >= 0xF0 && $val <= 0xF7) # We shoudl be getting three more bytes for this char. (Not supported)
			{
				$state = 3;
			}
			elsif ( $val >= 0x80 && $val <= 0xBF) # second or third byte without first getting first byte.
			{
				return 0;
			}
			#	Else it's a single byte char it's OK.
		}
		elsif ($state == 1 || $state == 2)
		{
			if ( $val >= 0x80 && $val <= 0xBF)
			{
				$state--;
			}
			else
			{
				return 0;
			}
		}
		elsif ($state >= 3)
		{
			return 0; #We're not doing more than 3 bytes
		}
	}
	return 1;
}

sub latin1_to_utf8
{
  my $u = Unicode::String::latin1($_[0]) ;
  return $u->utf8 ;
}

####
# Convert a utf8 byte string to latin 1.  Since this is a lossy
# conversion, you can optionally tell the function what to convert
# characters to if they're > 255.
####
my $latin1_map ;
sub utf8_to_latin1
{
  my $str = shift ;
  my $replchar = shift || "?" ;

  my $u = Unicode::String::utf8($str) ;
  my $unicode = $u->ucs2 ;
  $latin1_map = Unicode::Map8->new("latin1") if !$latin1_map ;
  $latin1_map->default_to8(ord($replchar)) ;
  return $latin1_map->to8($unicode) ;
}

#regex_prepare returns a rexex safe version of the input string (assuming that it's valid UTF-8)
# do not save the value you get from this function... it should only be used for form checking and the like.
sub utf8_regex_prepare{
      my $value = shift;
      my $substitution = [
			  ['([\xC0-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF][\x80-\xBF]|[\xF0-\xF7][\x80-\xBF][\x80-\xBF][\x80-\xBF])' , 'X'],
			 ];

      foreach my $val (@{$substitution}){
	    $value =~ s/$val->[0]/$val->[1]/g;
      }
      return $value;
}

# strip control characters from a scalarref
sub strip_ctrl_chars {
	my $ref = shift;
	return $$ref =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
}

1;
