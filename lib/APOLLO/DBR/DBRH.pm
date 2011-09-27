package APOLLO::DBR::DBRH;

use strict;


#Usage:
#specify dbh handle and field => value pairs. use scalarrefs to values to prevent their being escaped.
#$dbrh->buildWhere('textfield' => 'value1', 'numfield_with_trusted_source' => \'2222','untrusted_numfield' => ['! > < d <> in !in',2222]);
sub buildWhere{
    my $self = shift;
    my $param = shift;
    my $flag = shift;
    my $aliasmap = shift;

    $param = [%{$param}] if (ref($param) eq 'HASH');
    $param = [] unless (ref($param) eq 'ARRAY');

    my $where;

    while (@{$param}) {
	my $key = shift @{$param};

	# is it an OR? (single element)
	if (ref($key) eq 'ARRAY') {
	      my $or;
	      foreach my $element(@{$key}){
		    if(ref($element)){
			  $or .= ' OR' if $or;
			  $or .= $self->buildWhere($element,'sub',$aliasmap);
		    }
	      }
	      $where .= ' AND' if $where;
	      $where .= " ($or)";
	} else {

	      my $value = shift @{$param};

	      my $operator;
	      my $fvalue;

	      if (ref($value) eq 'HASH') {
		    if($value->{-table} && ($value->{-field} || $value->{-fields})){#is it a subquery?
			  $operator = 'IN';
			  return $self->_error('failed to build subquery sql') unless
			    my $sql = $self->_buildselect(%{$value});
			  $fvalue = "($sql)";

		    }elsif($aliasmap){ #not a subquery... are we doing a join?
			  my $alias = $key;
			  return $self->_error("invalid table alias '$alias' in -fields") unless $aliasmap->{$alias};

			  if(%{$value}){
				my %afields;
				foreach my $k (keys %{$value}) {
				      $afields{"$alias.$k"} = $value->{$k};
				}

				return $self->_error('where part failed') unless
				  my $wherepart = $self->buildWhere(\%afields,'sub',$aliasmap);

				$where .= ' AND' if $where;
				$where .= $wherepart;
			  }

			  next;	# get out of this loop... we are recursing instead

		    }else{
			  return $self->_error("invalid use of a hashref for key $key in -fields");
		    }

	      } else {
		    my $flags;
		    $flags = lc($value->[0]) if (ref($value) eq 'ARRAY');
		    my $blist = 0;

		    my $cont; # flag to continue checking flags after quoting
		    #mutually exclusive flags /////////////////////////
		    if ($flags =~ /like/) { # like
			  return $self->_error('LIKE flag disabled without the allowquery flag') unless $self->{config}->{allowquery};
			  $operator = 'LIKE';
		    } elsif ($flags =~ /\<\>/) { # greater than less than
			  $operator = '<>';
			  $value->[0] .= ' d';
		    } elsif ($flags =~ /\>=/) { # greater than eq
			  $operator = '>=';
			  $value->[0] .= ' d';
		    } elsif ($flags =~ /\<=/) { # less than eq
			  $operator = '<=';
			  $value->[0] .= ' d';
		    } elsif ($flags =~ /\>/) { # greater than
			  $operator = '>';
			  $value->[0] .= ' d';
		    } elsif ($flags =~ /\</) { # less than
			  $operator = '<';
			  $value->[0] .= ' d';
		    }else{
			  $cont = 1;
		    }

		    my @fvalues = $self->quote($value,$aliasmap);
		    return $self->_error("Quoting error with field $key") unless defined($fvalues[0]);

		    if ($cont) {
			  if ($flags =~ /!in/) {
				if (@fvalues > 1) {
				      $operator = 'NOT IN';
				      $blist = 1;
				} else {
				      $operator = '!=';
				}
			  } elsif ($flags =~ /in/) {
				if (@fvalues > 1) {
				      $operator = 'IN';
				      $blist = 1;
				} else {
				      $operator = '=';
				}
			  } elsif ($flags =~ /!/) {
				$operator = '!=';
			  } else {
				$operator = '=';
			  }
		    }
		    #//////////////////////////////////////////////////

		    if ($blist) {
			  $fvalue = '(' . join(',',@fvalues) . ')';
		    } else {
			  $fvalue = $fvalues[0];
		    }
	      }

	      $operator = 'IS' if (($fvalue eq 'NULL') && ($operator eq '='));
	      $operator = 'IS NOT' if (($fvalue eq 'NULL') && ($operator eq '!='));

	      $where .= ' AND' if $where;
	      $where .= " $key $operator $fvalue";
	}
  }

    return '' unless $where;
    if($flag eq 'sub'){
	  return $where;
    }else{
	  return " WHERE$where";
    }
}


sub _buildselect{
      my $self = shift;
      my %params = @_;

      my $sql;
      $sql .= 'SELECT ';


      ####################### table handling #################
      my $tables = $params{-table} || $params{-tables};
      unless (ref($tables)){
	    my @tmptbl = split(/\s+/,$tables);
	    $tables = \@tmptbl if @tmptbl > 1;
      }

      return $self->_error("No -table[s] parameter specified") unless $tables;

      my $aliasmap;
      my @tparts;
      if(ref($tables) eq 'ARRAY'){
	    $aliasmap = {};
	    my $ct = 0;
	    foreach my $table (@{$tables}){
		  return $self->_error("Invalid table name specified ($table)") unless
		    $table =~ /^[A-Za-z][A-Za-z0-9_-]*$/;
		  return $self->_error('No more than 26 tables allowed in a join') if $ct > 25;
		  my $alias = chr(97 + $ct++); # a-z
		  $aliasmap->{$alias} = $table;
		  push @tparts, "$table $alias";
	    }
      }elsif(ref($tables) eq 'HASH'){
	    $aliasmap = {};
	    foreach my $alias (keys %{$tables}){
		  return $self->_error("invalid table alias '$alias' in -table[s]") unless
		    $alias =~ /^[A-Za-z][A-Za-z0-9_-]*$/;
		  my $table = $tables->{$alias};
		  return $self->_error("Invalid table name specified ($table)") unless
		    $table =~ /^[A-Za-z][A-Za-z0-9_-]*$/;

		  $aliasmap->{$alias} = $table;
		  push @tparts, "$table $alias";
	    }
      }else{
	    return $self->_error("Invalid table name specified ($tables)") unless
	      $tables =~ /^[A-Za-z][A-Za-z0-9_-]*$/;

	    @tparts = $tables;
      }

      ################### field handling ######################


      my $fields = $params{-fields} || $params{-field};
      unless(ref($fields)){
	    $fields =~ s/^\s+|\s+$//g;
	    $fields = [split(/\s+/,$fields)];
      }

      if($params{-count}){
	  $sql .= 'count(*) ';
      }elsif (ref($fields) eq 'ARRAY') {
	    my @fields;
	    foreach my $str (@{$fields}) {
		  my @parts = split(/\./,$str);
		  my ($field,$alias);

		  my $outf;
		  if (@parts == 1){
			($field) = @parts;
			$outf = $field;
		  }elsif(@parts == 2){
			($alias,$field) = @parts;
			return $self->_error("table alias '$str' is invalid without a join") unless $aliasmap;
			return $self->_error("invalid table alias '$str' in -fields") unless $aliasmap->{$alias};

			if($params{-dealias}){ 
			      $outf = "$alias.$field as $field";
			}elsif($params{-alias}){
			      $outf = "$alias.$field as '$alias.$field'";
			}else{
			      $outf = "$alias.$field"; # HERE - might result in different behavior on different databases
			}
		  }else{
			$self->_error("invalid fieldname '$str' in -fields");
			next;
		  }

		  next unless $field =~ /^[A-Za-z][A-Za-z0-9_-]*$/; # should bomb out, but leave this cus of legacy code

		  push @fields, $outf;
	    }
	    return $self->_error('No valid fields specified') unless @fields;
	    $sql .= join(',',@fields) . ' ';

      } elsif ($fields eq '*') {
	    $sql .= '* ';
      } else {
	    return $self->_error('No valid fields specified');
      }

      # insert table parts
      $sql .= "FROM " . join(',',@tparts);

      my $where = $self->buildWhere($params{-where},undef,$aliasmap);
      return $self->_error("Failed to build where clause") unless defined($where);

      $sql .= $where;

      if($params{-lock}){
	    my $mode = lc($params{-lock});

	    if($mode eq 'update'){
		  $sql .= ' FOR UPDATE'
	    }
      }

      my $limit = $params{-limit};
      if($limit){
	    return $self->_error('invalid limit') unless $limit =~ /^\d+$/;
	    $sql .= " LIMIT $limit"
      }

      return $sql;
}

# -table -fields -where
sub select{
    my $self = shift;
    my @params = @_;
    my %params;
    if(scalar(@params) == 1){
      $params{-sql} = $params[0];
    }else{
      %params = @params;
    }

    my $sql;
    if($params{-sql}){
	  $sql = $params{-sql};
    }else{
	  return $self->_error('failed to build select sql') unless
	    $sql = $self->_buildselect(%params);
    }

    #print STDERR "sql: $sql\n";
    $self->logDebug($sql);
    return $self->_error('failed to prepare statement') unless
      my $sth = $self->{dbh}->prepare($sql);
      my $rowct = $sth->execute();

    return $self->_error('failed to execute statement') unless defined($rowct);


    my $count = 0;
    my $rows = [];
    if ($rows) {
	  if ($params{-rawsth}) {
		return $sth;
	  }elsif ($params{-count}) {
		($count) = $sth->fetchrow_array();
	  }elsif($params{-arrayref}){
		$rows = $sth->fetchall_arrayref();
	  }elsif ($params{-keycol}) {
		return $sth->fetchall_hashref($params{-keycol});
	  } else {
		while (my $row = $sth->fetchrow_hashref()) {
		      $count++;
		      push @{$rows}, $row;
		}
	  }
    }

    $sth->finish();

    if($rows){
	if($params{-count}){
	    return $count;
	}elsif($params{-single}){
	      return 0 unless @{$rows};
	      my $row = $rows->[0];
	      return $row;
	}else{
	      return $rows;
	}
    }

    return undef;

}

sub quote{
  my $self = shift;
  my $inval = shift;
  my $aliasmap = shift;

  my @values;
  my @fvalues;
  my $flags;


  if (ref($inval) eq 'ARRAY'){
	($flags,@values) = @{$inval};
  }else{
	@values = ($inval);
  }

  foreach my $value (@values){
	my $fvalue;
	if (ref($value) eq 'SCALAR') { # raw values are passed in as scalarrefs cus its super easy to do so.
	      $fvalue=${$value};
	}elsif($flags =~ /j/){ # join
	      my @parts = split(/\./,$value);
	      my ($field,$alias);

	      if (@parts == 1){
		    ($field) = @parts;
	      }elsif(@parts == 2){
		    ($alias,$field) = @parts;
		    return $self->_error("table alias '$value' is invalid without a join") unless $aliasmap;
		    return $self->_error("invalid table alias '$value' in -fields") unless $aliasmap->{$alias};
	      }
	      return $self->_error("invalid fieldname '$value' in -fields") unless $field =~ /^[A-Za-z][A-Za-z0-9_-]*$/;
	      $fvalue = $value;

	}elsif ($flags =~ /d/) {	# numeric
	      if ($value =~ /^-?\d*\.?\d+$/) {
		    $fvalue = $value;
	      }else{
		    return $self->_error("value $value is not a legal number");
		    next;
	      }
	} else {	# string
	      $fvalue = $self->{dbh}->quote($value);
	}

	$fvalue = 'NULL' unless defined($fvalue);
	push @fvalues, $fvalue;
  }

  return @fvalues;
}

sub delete{
  my $self = shift;
  my %params = @_;

  return $self->_error('No valid -where parameter specified') unless ref($params{-where}) eq 'HASH';
  return $self->_error('No -table parameter specified') unless $params{-table} =~ /^[A-Za-z0-9_-]+$/;

  my $sql = "DELETE FROM $params{-table} ";

  if(ref($params{-where}) eq 'HASH'){
	return $self->_error('At least one where parameter must be provided') unless scalar(%{$params{-where}});
  }elsif(ref($params{-where}) eq 'ARRAY'){
	return $self->_error('At least one where parameter must be provided') unless scalar(@{$params{-where}});
  }else{
	return $self->_error('Invalid -where parameter');
  }

  my $where = $self->buildWhere($params{-where});
  return $self->_error("Failed to build where clause") unless defined($where);
  return $self->_error("Empty where clauses are not allowed") unless length($where);
  $sql .= $where;
  #print STDERR "sql: $sql\n";
  $self->logDebug($sql);
  my $success = $self->{dbh}->do($sql);

  return 1 if $success;
  return undef;
}

sub modify{
  my $self = shift;
  my %params = @_;



  $params{-table} ||= $params{-insert} || $params{-update};

  return $self->_error('No proper -fields parameter specified') unless ref($params{-fields}) eq 'HASH';
  return $self->_error('No -table parameter specified') unless $params{-table} =~ /^[A-Za-z0-9_-]+$/;

  my %fields;
  my $call = {params => \%params,fields => \%fields, tmp => {}};
  my $fcount;
  foreach my $field (keys %{$params{-fields}}){
    next unless $field =~ /^[A-Za-z0-9_-]+$/;
    ($fields{$field}) = $self->quote($params{-fields}->{$field});
    return $self->_error("failed to quote value for field '$field'") unless defined($fields{$field});
    $fcount++;
  }
  return $self->_error('No valid fields specified') unless $fcount;

  my $sql;

  my @fkeys = keys %fields;
  if($params{-insert}){
	return $self->_error('Failed to prepare sequence') unless $self->_prepareSequence($call);

	$sql = "INSERT INTO $params{-table} ";
	$sql .= '(' . join (',',@fkeys) . ')';
	$sql .= ' VALUES ';
	$sql .= '(' . join (',',map {$fields{$_}} @fkeys) . ')';
  }elsif($params{-where}){
    $sql = "UPDATE $params{-table} SET ";
    $sql .= join (', ',map {"$_ = $fields{$_}"} @fkeys);

    if(ref($params{-where}) eq 'HASH'){
	  return $self->_error('At least one where parameter must be provided') unless scalar(%{$params{-where}});
    }elsif(ref($params{-where}) eq 'ARRAY'){
	  return $self->_error('At least one where parameter must be provided') unless scalar(@{$params{-where}});
    }else{
	  return $self->_error('Invalid -where parameter');
    }

    my $where = $self->buildWhere($params{-where});
    return $self->_error("Failed to build where clause") unless $where;
    $sql .= $where;
  }else{
      return $self->_error('-insert flag or -where hashref/arrayref (for updates) must be specified');
  }
  #print STDERR "sql: $sql\n";
  $self->logDebug($sql);

  my $rows;
  if($params{-quiet}){
	do {
	      local $self->{dbh}->{PrintError} = 0; # make DBI quiet
	      $rows = $self->{dbh}->do($sql);
	};
	return undef unless defined ($rows);
  }else{
	$rows = $self->{dbh}->do($sql);
	return $self->_error('failed to execute statement') unless defined($rows);
  }

  if ($params{-insert}) {
	my ($sequenceval) = $self->_getSequenceValue($call);
	return $sequenceval;
  } else {
	return $rows || 0;	# number of rows updated or 0
  }



}

sub insert{
    my $self = shift;
    my %params = @_;
    return $self->_error('No -table parameter specified') unless $params{-table} =~ /^[A-Za-z0-9_-]+$/;
    
    return $self->modify(@_,-insert => 1);
}

sub update{
    my $self = shift;
    my %params = @_;
    return $self->_error('No -table parameter specified') unless $params{-table} =~ /^[A-Za-z0-9_-]+$/;
    return $self->modify(@_,-update => 1);
}

#Usage:
# [$dbr->]inTable($dbh [or db name($self-> required)],'table_name','field','value');
#$dbr->inTable($dbh,'table_name','field',$inp)

sub inTable{
  my ($self,$table,$field,$value) = (@_);
  my $rows = $self->select(
			   -fields => [1],
			   -table => $table,
			   -where => {$field => $value},
			  );

  return scalar(@{$rows}) if $rows;

  return undef;
}

# non-functional as of yet
#sub FKlookup{
#      my $self = shift;
#      my %params = @_;
#      return $self->_error('No -table parameter specified') unless $params{-table} =~ /^[A-Za-z0-9_-]+$/;
#      return $self->_error('No -idfield parameter specified') unless $params{-idfield} =~ /^[A-Za-z0-9_-]+$/;
#      return $self->_error('No -textfield parameter specified') unless $params{-textfield} =~ /^[A-Za-z0-9_-]+$/;
#      my $rows = $self->select(
#			       -fields => [$params{-textfield},$params{-idfield}],
#			       -table => $params{-table},
#			       -where => {$field => $value},
#			      );
#}


sub begin{
      my $self = shift;

      return $self->_error('Already transaction - cannot begin') if $self->{'_intran'};

      my $transcache = $self->{dbr}->{'_transcache'} ||= {};
      unless($self->{config}->{nestedtrans}){
	    if( $transcache->{$self->{name}} ){
		  #already in transaction bail out
		  $self->logDebug('BEGIN - Fake');
		  $self->{'_faketran'} = 1;
		  $self->{'_intran'} = 1;
		  $transcache->{$self->{name}}++;
		  return 1;
	    }
      }

      $self->logDebug('BEGIN');
      my $success = $self->{dbh}->do('BEGIN');
      return $self->_error('Failed to begin transaction') unless $success;
      $self->{'_intran'} = 1;
      $transcache->{$self->{name}}++;
      return 1;
}

sub commit{
      my $self = shift;

      my $transcache = $self->{dbr}->{'_transcache'} ||= {};
      if($self->{'_faketran'}){
	    $self->logDebug('COMMIT - Fake');
	    $self->{'_faketran'} = 0;
	    $self->{'_intran'} = 0;
	    $transcache->{$self->{name}}--;
	    return 1;
      }

      return $self->_error('Not in transaction - cannot commit') unless $self->{'_intran'};
      $self->logDebug('COMMIT');
      my $success = $self->{dbh}->do('COMMIT');
      return $self->_error('Failed to commit transaction') unless $success;
      $self->{'_intran'} = 0;
      $transcache->{$self->{name}}--;

      return 1;
}

sub rollback{
      my $self = shift;

      my $transcache = $self->{dbr}->{'_transcache'} ||= {};
      if($self->{'_faketran'}){
	    $self->logDebug('ROLLBACK - Fake');
	    $self->{'_faketran'} = 0;
	    $self->{'_intran'} = 0;
	    $transcache->{$self->{name}}--;
	    #$self->{dbh}->{'AutoCommit'} = 1;
	    return 1;
      }

      return $self->_error('Not in transaction - cannot rollback') unless $self->{'_intran'};

      $self->logDebug('ROLLBACK');
      my $success = $self->{dbh}->do('ROLLBACK');
      #$self->{dbh}->{'AutoCommit'} = 1;
      return $self->_error('Failed to roll back transaction') unless $success;
      $self->{'_intran'} = 0;
      $transcache->{$self->{name}}--;
      return 1;
}


sub getserial{
      my $self = shift;
      my $name = shift;
      my $table = shift  || 'serials';
      my $field1 = shift || 'name';
      my $field2 = shift || 'serial';
      return $self->_error('name must be specified') unless $name;

      $self->begin();

      my $row = $self->select(
			      -table => $table,
			      -field => $field2,
			      -where => {$field1 => $name},
			      -single => 1,
			      -lock => 'update',
			     );

      return $self->_error('serial select failed') unless defined($row);
      return $self->_error('serial is not primed') unless $row;

      my $id = $row->{$field2};

      return $self->_error('serial update failed') unless 
	$self->update(
		      -table => $table,
		      -fields => {$field2 => ['d',$id + 1]},
		      -where => {
				 $field1 => $name
				},
		     );

      $self->commit();

      return $id;
}

############ sequence stubs ###########
#parameters: $self,$call
sub _prepareSequence{
      return 1;
}
sub _getSequenceValue{
      return -1;
}
#######################################

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

sub logDebug{
      my $self = shift;
      my $message = shift;
      my ( $package, $filename, $line, $method) = caller(1);
      if ($self->{logger}){
	    $self->{logger}->logDebug($message,$method);
      }elsif($self->{debug}){
	    print STDERR "DBR DEBUG: $message\n";
      }
}
sub log{
      my $self = shift;
      my $message = shift;
      my ( $package, $filename, $line, $method) = caller(1);
      if ($self->{logger}){
	    $self->{logger}->log($message,$method);
      }else{
	    print STDERR "DBR: $message\n";
      }
      return 1;
}


sub disconnect{
      my $self = shift;

      return $self->_error('dbh not found!') unless
	my $dbh = $self->{dbr}->{CACHE}->{$self->{name}}->{$self->{class}};
      delete $self->{dbr}->{CACHE}->{$self->{name}}->{$self->{class}};

      $dbh->disconnect();


      return 1;
}

# object is slightly shotgunned - clean this shiat
sub DESTROY{
    my $self = shift;

    $self->rollback() if $self->{'_intran'};

}

1;
 
