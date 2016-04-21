#!/usr/bin/perl
#
# *** MANAGED BY PUPPET - DO NOT EDIT DIRECTLY! ***
#
# Dale Wellman
# 2/2015
#
# Script to pull data in from Racktables to rancid router.db files
#

use Getopt::Std;
use DBI;

# Getopts
# 	- d: debug output
#

getopts( 'd' );

if( $opt_d )
{
	$DEBUG = 1;
}

# Global Vars
$DB 		= "racktables";
$HOST 		= "racktables.company.com";
$USER 		= "someuser";
$PASSWD 	= "<changeme123>";

$RANCIDDIR	= "/var/rancid";
$DOMAIN		= "company.com";

$DBCONNECT 	= "DBI:mysql:database=$DB;host=$HOST";

# array of racktables attribute keys to rancid directory names
%HARDWARE	= ( 
			"routers", "7",
			"switches", "8",
			"switches-chassis", "1503",
			"firewalls", "50011"
		);

foreach $key (keys %HARDWARE)
{
	my $line = '';

	# DB query on routers, switches, firewalls with rancid flag on
	$DBQUERY = "select inet_ntoa(IPv4Allocation.ip), RackObject.name from RackObject JOIN AttributeValue JOIN IPv4Allocation ON RackObject.id=AttributeValue.object_id AND AttributeValue.object_id=IPv4Allocation.object_id WHERE AttributeValue.attr_id=10011 AND AttributeValue.uint_value=1501 AND AttributeValue.object_tid=$HARDWARE{$key} group by RackObject.name";
	DEBUG( "SQL: select inet_ntoa(IPv4Allocation.ip), RackObject.name from RackObject JOIN AttributeValue JOIN IPv4Allocation ON RackObject.id=AttributeValue.object_id AND AttributeValue.object_id=IPv4Allocation.object_id WHERE AttributeValue.attr_id=10011 AND AttributeValue.uint_value=1501 AND AttributeValue.object_tid=$HARDWARE{$key} group by RackObject.name\n" );

	my $dbh = DBI->connect( $DBCONNECT, $USER, $PASSWD, {'RaiseError' => 1} );
	my $sth = $dbh->prepare( $DBQUERY );
	$sth->execute();
	$sth->bind_columns( \$IP, \$name);
	while( $sth->fetch() )
	{
		# DB Query to find device type
		my $DBQUERY2 = "select Dictionary.dict_value from Dictionary JOIN AttributeValue JOIN RackObject JOIN IPv4Allocation ON Dictionary.dict_key = AttributeValue.uint_value AND AttributeValue.object_id=RackObject.id AND AttributeValue.object_id=IPv4Allocation.object_id WHERE AttributeValue.attr_id='2' AND RackObject.name='$name'";
		$sth2 = $dbh->prepare( $DBQUERY2 );
		$sth2->execute();
		$device = $sth2->fetchrow_array();
		DEBUG( "IP: $IP, Name: $name, Device: $device\n" );
		$sth2->finish();

		# Build arrays for writing to rancid config later
		#   * This should really be rewritten to be more intelligent with new device types
		if( $device =~ /^Cisco/ ) 
		{
			$line = $line . "$name.$DOMAIN;cisco;up\n";
		}
		if( $device =~ /^Fortinet/ ) 
		{
			$line = $line . "$name.$DOMAIN;fortigate;up\n";
		}
		if( $device =~ /^Arista/ ) 
		{
			$line = $line . "$name.$DOMAIN;arista;up\n";
		}
		
	}

	DEBUG( "line: $line\n" );

	# This is kind of hacky but quickest solution.  Stacked switches in racktables are setup in
	# a network cassis "type".  They need a separate key in the associative array for the separate
	# SQL query.  But the output should go to the same switches directory rancid config.

	my $RANCID_FH;

	if( $key =~ /switches-chassis/ )
	{
		$key = 'switches';
		# set the output file
		$FILE = "$RANCIDDIR/$key/router.db";

		# if switches-chassis, append file do not over write
		open( $RANCID_FH, ">>", "$FILE" ) or die "Can't open rancid config: $!\n";
	}
	else
	{
		# set the output file
		$FILE = "$RANCIDDIR/$key/router.db";

		open( $RANCID_FH, ">", "$FILE" ) or die "Can't open rancid config: $!\n";

	}

	print $RANCID_FH $line;
	close( $RANCID_FH );

	$sth->finish();
	$dbh->disconnect;

}



sub DEBUG
{
        print STDERR "DEBUG: " . "@_" if $DEBUG;
}

