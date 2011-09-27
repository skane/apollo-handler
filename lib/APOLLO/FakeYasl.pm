package APOLLO::FakeYasl;
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# the contents of this file are Copyright (c) 2004 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

use strict;
use vars qw($global_template_cache);
use HTML::Entities qw(encode_entities);
use CGI;

my $KEYWORD = 'yasl';

sub parse{
      my %in = @_;
      return 0 unless ($in{template} && $in{ref});
      my $output;

      my $req = {docroot => $in{docroot} || ''};

      my $work = loadTemplate($req,'',$in{template});

      return _error("failed to load template '$in{template}'") unless $work;
      return _error("failed to parse template '$in{template}'") unless _parse($req,$in{template},\$output,$in{ref},$in{ref},$work);
      return $output;
};


# element types: 0 starttag, 1 endtag, 2 single
sub _parse{
      # print "\nSTARTING parse SUBROUTINE\n";
      my $req = shift;
      my $template = shift;
      my $output = shift;
      my $absref = shift;
      my $ref  = shift;
      my $work = shift;
      my $workrange = shift;
      my $loopno = shift;

      $workrange ||=[1,$#$work];

      my $workcount = $workrange->[0];
      while (($workrange->[1] >= $workcount) && (my $element = $work->[$workcount++])){
	    if (ref($element) eq 'ARRAY' && $element->[0] != 1){
		  if ($element->[0] == 2){ # single
			if (_b_in($element->[1],['value','value-r','value-q','value-u'])){
			      my $val;
			      if(ref($element->[2]) eq 'SCALAR'){
				    if (${$element->[2]} eq '.'){
					  $val = $ref unless ref($ref);
				    }else{
					  $val = _get_ref($absref,$ref,${$element->[2]});
				    }
			      }else{
				    $val = $element->[2];
			      }

			      my $outval;
			      if($element->[1] eq 'value'){
				    $outval = encode_entities($val);
			      }elsif($element->[1] eq 'value-u'){
				    $outval = CGI::escape($val);
			      }elsif($element->[1] eq 'value-r'){
				    $outval = $val;
			      }elsif($element->[1] eq 'value-q'){
				    # not sure what point there is to quote encode if its already urlencoded *shrug*
				    $outval = encode_entities($val);;
			      }
			      $$output .= $outval;
			}elsif($element->[1] eq 'setvalue' || $element->[1] eq 'setvalue-value'){
			      # <yasl:setvalue "nodeName" "value"/>
			      # <yasl:setvalue-value "nodeName" "valueOfNodeName"/>
			      my ($key,$val) = ($element->[2],$element->[3]);
			      if(ref($key) eq 'SCALAR'){
				    my $key = $$key;
				    if($element->[1] eq 'setvalue'){
					  # intentionally broken to mimic yasl setvalue
					  $val = $$val if ref($val) eq 'SCALAR'; # allow " or '
				    }
				    if (ref($val) eq 'SCALAR'){
					  $val = _get_ref($absref,$ref,${$val});
				    }

				    if($key =~ /^__/){ # global
					  $absref->{$key} = $val;
				    }else{
					  $ref->{$key} = $val;
				    }
			      }
			}elsif ($element->[1] eq 'include'){
			      my $val;
			      if(ref($element->[2]) eq 'SCALAR'){
				    $val = ${$element->[2]};
			      }else{
				    $val = $element->[2];
			      }
			      #ok this is kinda ugly
			      _parse($req,_pathmerge($template,$val),$output,$absref,$ref,loadTemplate($req,$template,$val));
			}elsif ($element->[1] eq 'includev'){
			      my $val;
			      if(ref($element->[2]) eq 'SCALAR'){
				    $val = _get_ref($absref,$ref,${$element->[2]});
			      }else{
				    $val = $element->[2];
			      }
			      #ok this is kinda ugly
			      _parse($req,_pathmerge($template,$val),$output,$absref,$ref,loadTemplate($req,$template,$val));
			};
		  }elsif($element->[0] == 0){ #starttag
			my $range=[$workcount];
			my @subwork;
			my %checkcount;
			my $notend=1;
			while ($notend && (my $subelement = $work->[$workcount])){
			      if (ref($subelement) eq 'ARRAY'){
				    if ($subelement->[0] != 2){
					  if($subelement->[0] == 1){
						$checkcount{$subelement->[1]}--;
					  }else{
						$checkcount{$subelement->[1]}++;
					  }
				    }
			      }
			      if ($checkcount{$element->[1]} < 0){
				    $range->[1] = $workcount - 1;
				    $notend = 0;
			      }
			      $workcount++;
			}


			if ($element->[1] eq 'foreach'){
			      if (ref($element->[2]) eq 'SCALAR'){
				    my $val = _get_ref($absref,$ref,${$element->[2]},1);
				    if ($val){
					  unless (ref($val) eq 'ARRAY'){$val = [$val]};
					  my $loopct = 1;
					  foreach (@{$val}){
						_parse($req,$template,$output,$absref,$_,$work,$range,$loopct++);
					  }
				    }
			      }
			}elsif (($element->[1] eq 'if') || ($element->[1] eq 'ifnot')){#  IF //////////////////////////
			      my ($val1,$cmp,$val2) = ($element->[2],$element->[3],$element->[4]);
			      $val1 = _get_ref($absref,$ref,${$val1}) if ref($val1) eq 'SCALAR';
			      $val2 = _get_ref($absref,$ref,${$val2}) if ref($val2) eq 'SCALAR';
			      
			      my $true = 0;
			      if ($cmp){
				    if ($cmp eq 'eq'){
					  $true = 1 if $val1 eq $val2;
				    }elsif($cmp eq 'ne'){
					  $true = 1 if $val1 ne $val2;
				    }elsif($cmp eq 'ge'){
					  $true = 1 if $val1 ge $val2;
				    }elsif($cmp eq 'gt'){
					  $true = 1 if $val1 gt $val2;
				    }elsif($cmp eq 'le'){
					  $true = 1 if $val1 le $val2;
				    }elsif($cmp eq 'lt'){
					   $true = 1 if $val1 lt $val2;
				    }
			      }else{
				    $true = 1 if length($val1);
				    # length check instead of existance or boolean.silly,
				    #but required to match the original yasl
			      }

			      $true = !$true if ($element->[1] eq 'ifnot');
			      if ($true){
				    _parse($req,$template,$output,$absref,$ref,$work,$range,$loopno);
			      }
			}elsif ($element->[1] eq 'ifeven'){#  IF //////////////////////////
                              unless($loopno % 2){
                                    _parse($req,$template,$output,$absref,$ref,$work,$range,$loopno);
                              }
                        }elsif ($element->[1] eq 'ifodd'){#  IF //////////////////////////
                              if ($loopno % 2){
                                    _parse($req,$template,$output,$absref,$ref,$work,$range,$loopno);
                              }
                        }

		  }
	    }else{
		  if (ref($element)){
			my $tmp = substr($$output,-1000);
			$tmp =~ s/[\n\r]|\s{2}//g;
			$tmp = substr($tmp,-100);
			die "FakeYasl ERROR: unmatched \"$element->[1]\" element near: ...$tmp\n";
		  }else{
			$$output .= $element;
		  }
	    }
      }
      return 1;
};
sub _pathmerge{
      my $path = shift;
      my $template = shift;

      $path =~ s/[^\/]*$//;

      while($template =~ s/^\.\.\///){
	    $path =~ s/[^\/]*\/$//;
      }

      $template =~ s/\.\.\///g; # just in case
      $path =~ s/\.\.\///g;

      if ($template =~ /^\//){
	    return $template;
      }

      return $path . $template;

}
sub loadTemplate{
      my $req = shift;
      my $path = shift;
      my $template = shift;
      my $work;


      my $cacheok;
      if(ref($template)){
	    return _error('template accepts only filenames or scalarrefs') unless ref($template) eq 'SCALAR';
      }else{
	    $cacheok = 1;
	    $template = $req->{docroot} . _pathmerge($path,$template);
      }

      $global_template_cache ||= {};
      my @fstat = stat $template;

      if($cacheok && $global_template_cache->{$template} && ref($global_template_cache->{$template}) eq 'ARRAY' && $fstat[9] == $global_template_cache->{$template}->[0]){
	    $work = $global_template_cache->{$template};
      }else{
	    my $fileref;
	    if(ref($template) eq 'SCALAR'){
		  $fileref = $template;
	    }else{
		  return _error("Failed to open $template") unless open INPFILE, "<$template";
		  my $file;
		  while (<INPFILE>) {
			$file .= $_;
		  }
		  close INPFILE;
		  $fileref = \$file;
	    }

	    $work = [$fstat[9]];
	    my @tmp = split /(<\/?$KEYWORD:.*?>)/,${$fileref};
	    foreach my $val (@tmp){
		  if (length($val) > 0){
			if ($val =~ /^<(\/?)$KEYWORD:(.*?)(\/?)>$/){
			      my @params = ($1?1:0 || $3?2:0); # types 0 starttag, 1 endtag, 2 single

			      foreach my $param (split / /,$2){
				    $param =~ s/^("|')(.*?)\1$/$2/;
				    if ($1 eq '"'){
					  push @params,\$param;
				    }else{
					  push @params, $param;
				    };
			      }
			      $val = \@params;
			}
			push (@{$work},$val);
		  }
	    }
	    $global_template_cache->{$template} = $work;
      }
      return $work;
}
sub _get_ref{
      my $absref = shift;
      my $ref = shift;
      my $key = shift;

      $key =~ s/^\/root\//\//;
      my @keyparts = split /\//,$key;

      if(scalar(@keyparts) == 1){
	    my $outref;

	    if ($key =~ /^__/){ # "global" value
		  $outref = $absref->{$key}
	    }else{
		  $outref = $ref->{$key} if ref($ref) eq 'HASH';
	    }

	    return $outref;
      }elsif(scalar(@keyparts) >= 1 && length($keyparts[0]) > 0){
	    foreach(@keyparts){
		  $ref = _get_element($ref,$_);
		  last unless defined($ref);
	    }
	    return $ref;
      }else{
	    shift @keyparts;
	    foreach(@keyparts){
		  $absref = _get_element($absref,$_);
		  last unless defined($ref);
	    }
	    return $absref;
      }
      return undef;
}

sub _get_element{
      my $ref = shift;
      my $element = shift;

      if(ref($ref) eq 'HASH'){
	    return $ref->{$element};
      }elsif(ref($ref) eq 'ARRAY'){
	    return _get_element($ref->[0],$element);
      }else{
	    return undef;
      }
}

sub _error {
      my $message = shift;
      my ( $package, $filename, $line, $method) = caller(1);
      print STDERR "$message ($method, line $line)\n";
      return undef;
}


# returns true if all elements of Arrayref A (or single value) are present in arrayref B
sub _b_in{
      my $value1 = shift;
      my $value2 = shift;
      $value1 = [$value1] unless ref($value1);
      $value2 = [$value2] unless ref($value2);
      return undef unless (ref($value1) eq 'ARRAY' && ref($value2) eq 'ARRAY');
      my %valsA = map {$_ => 1} @{$value2};
      my $results;
      foreach my $val (@{$value1}) {
            unless ($valsA{$val}) {
                  return 0;
            }
      }
      return 1;
}


1;


