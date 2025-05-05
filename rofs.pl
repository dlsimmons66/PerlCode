#!/usr/bin/perl

### plain old documentation
=pod
    Name:		rofs.pl
	Dirs:		/opt/rofs, /var/logs/rofs		
    Purpose:	To pull metrics on the number of read-only filesystems in each
    environment (prod/qa/dev) and feed them into Graphite & Grafana.

    Notes:    
    Uses the Parallel::ForkManager module for multithreading 
    Capabilities. Pulls the list of servers from the Asset
    DB and relies upon is; as the authoritative source for the
    server lists.

=cut

# Importing the necessary Modules
use strict;
use warnings;
use DBI;
use POSIX;
use Parallel::ForkManager;
use Data::Dumper;

my debug = 1;
$|=1;

# Global Variables
our (%seen, %results);
our ($results, $svr, $total, $clean);
our ($rofs_count, $clean_count, $total_count); 
our ($all_count, $totalsTime, $writeLog, $logfile);
our ($env, $row, $ident, $instance, $server, $epoch, $subcount);
our ($rofs, $total_num, $clean_num, $rofs_num);
our ($hostenv, $targetenv, $dsn, $dbh);
our (@sums, @rofs_sum, @clean_sum, @total_sum);
our (@TT, @Totals, @list, @ROFS, @final_results, @RL, @CL, @TL, @SERVERS, @SORTED);

# Initial Assignments
our $eTime      = time;
our $sumTotal   = 0;
our $cleanTotal = 0;
our $rofsTotal  = 0;
our $hostCount  = 0;

# Grab the input string to process
my @ENVIRONMENT=$ARGV[0];

# Connect to DB
db_connect();

###
### Cycle through Environment
###

foreach $env(@ENVIRONMENT){

	# query DB for list
	if (not $dbh->ping) { db_connect(); }

	my sql = “Select name from system
		LEFT JOIN osType on system.operatingSystem = osType.id
		WHERE type\”UNIX Server\” and utilize=\”$env\” and osType.baseOs
        LIKE \%RHEL%\” and status=\”Active\” and managed=1
		ORDER BY name”;

	my $sth = $dbh->prepare($sql);
	$sth->execute;

	while (row = $sth->fetchrow_arrayref()){
		My $slist = @$row[0];
		Push @SERVERS, @$row[0];
	}

	# Sort Servers alpha-numerically
	unless (@SERVERS) { next; }
	@SORTED = sort @SERVERS;

###
### Initial Logfile Setup on a per environment basis
###

	if ($env =~ /QA\/Sat/) {
		$writelog = “QA”;
	} else {
		$writelog = “$env”;
	}

	$logfile = “.var/log/rofs/rofs” . $writelog . “.log”;
	open(LOG, “> $logfile”) or die “Cant open $writelog. \n”;

      print LOG "#" x 25; print LOG "    $writeLog Read Only Filesystem Check    ";
      print LOG "#" x 25; print LOG "\n";
      print LOG `date`;

	for my $svrname(@SORTED) {
		print LOG “$svrname\n”;
		$hostCount++;
	}

###
### Parallel::ForkManager
###

	my $pm = Parallel::ForkManager->new(50, ‘/tmp/’);
	
	# Parallel Process Tracking and Management
	# required to use Anonymous Subroutine

	$pm->run_on_finish ( sub {

my ($pid, $exit_code, $ident, $core_dump, $data_structure_reference) = @_;

if (defined($data_structure_reference)) {
my $q = $data_structure_reference->{input};
$results{$q} = $data_structure_reference->{result};
}
});

###
### Main Routine
###

	foreach my $q(@SORTED) {
		my $pid = $pm->start and next;
		alarm(10);
	
        # call ‘rofs_check’ subroutine to process data
		my $res = &rofs_check($pm, $q);

		# Grab the returned results
		$pm->finish(0, { result=> $res, input => $q });
	}

	$pm->wait_all_children;

###
### Process results of SSH
###

	while(my ($key, $value) = each %results) {
		@sums = split ‘ ‘, $value;

	# Some simple cleanup work
	$total = $sums[0]; $total =~ s/\s//g;
	$clean = $sums[1]; $clean =~ s/\s//g;
	$rofs  = $sums[2]; $rofs  =~ s/\s//g;

	# Push counts for summations
	push @rofs_sum,  $rofs;
	push @clean_sum, $clean;
	push @total_sum, $total;

	# Figure out which Graphite System to push data to
	if ($rofs >= 1) {
		if ($env =~ /Development/i) {
			$hostenv = “dev”;
			$targetenv = “dev”;
		} elsif ($env = /Test/i) {
			$hostenv = “test”;
			$targetenv = “dev”;
		} elsif ($env = /Production/i) {
$hostenv = prod”;
$targetenv = “prod”;
} else {
$hostenv = “qa”;
$targetenv = “qa”; 
		
		&logger(“$hostenv :: Found local $rofs read-only filesystems on $key”) \
if $debug;
# system("echo -e \"entmon.ROFS.Summary.$hostenv.ROFS.host.$key.count $rofs $eTime   \n\n\"|nc monitor.$targetenv.swacorp.com 2003");
	}
}

### Basic Summation Calculations
&logger("$env :: Performing calculations for Summation Counts") if $debug;
&logger("$env :: Total Hosts Count for found Read-Only Filesystems is $hostCount") \
if $debug;

# Total Number of File Systems
foreach $total_num(@total_sum) {
        $sumTotal = $sumTotal + $total_num;
}
&logger("$env :: Total File Systems: $sumTotal") if $debug;

# Number of Clean RW File Systems
foreach $clean_num(@clean_sum) {
        $cleanTotal = $cleanTotal + $clean_num;
}
&logger("$env :: Total Clean File Systems: $cleanTotal") if $debug;


# Number of Read-Only File Systems
foreach $rofs_num(@rofs_sum) {
        $rofsTotal = $rofsTotal + $rofs_num;
}
&logger("$env :: Total Read-Only File Systems: $rofsTotal") if $debug;

### Calling netcat to push results to Graphite
&logger("$env :: Aligning the environments prior to pushing calculated summaries via netcat...") if $debug;

        if (($rofsTotal + $cleanTotal) == $sumTotal) {
                my ($summary_env, $envout);

          # Reassigning ENV names to match Server Names
                if ($env =~ /Test/i) {
                        $summary_env = "Test";
                        $envout = "dev";
                } elsif ($env =~ /Developement|Dev/i) {
                        $summary_env = "Dev";
                        $envout = "dev";
                } elsif ($env =~ /Production|Prod/i) {
                        $summary_env = "Prod";
                        $envout = "prod";
                } else {
                        $summary_env = "QA";
                        $envout = "qa";
                }

            &logger("$env :: Pushing $summary_env to $envout Graphite Servers") if $debug;
            &logger("entmon.ROFS.Summary.$summary_env.HOST.count $hostCount $eTime") if $debug;
            &logger("entmon.ROFS.Summary.$summary_env.ROFS.count $rofsTotal $eTime") if $debug;
            &logger("entmon.ROFS.Summary.$summary_env.CLEAN.count $cleanTotal $eTime") if $debug;
            &logger("entmon.ROFS.Summary.$summary_env.TOTAL.count $sumTotal $eTime") if $debug;

            system("echo -e \"mon.ROFS.Summary.$summary_env.HOST.count \
$hostCount  $eTime \n\n\"|nc monitor.$envout.com 2003");
            system("echo -e \"mon.ROFS.Summary.$summary_env.ROFS.count \
$rofsTotal  $eTime \n\n\"|nc monitor.$envout.com 2003");
            system("echo -e \"mon.ROFS.Summary.$summary_env.CLEAN.count \
$cleanTotal $eTime \n\n\"|nc monitor.$envout.com 2003");
            system("echo -e \"mon.ROFS.Summary.$summary_env.TOTAL.count \
$sumTotal   $eTime \n\n\"|nc monitor.$envout.com 2003");

        } else {

                &logger("Summation of RO File Systems \+ Clean File Systems do not match Total File Systems") if $debug;
        }

        @SERVERS=();
        @SORTED=();
}

### Close Up and EXIT
&db_disconnect();
close (LOG);
exit 0;

###############
### Subroutines
###############

### DB Connect
# Connects to the Infrastructure Asset DB
# As the Source of Record 
sub db_connect {
        $dsn = "DBI:mysql:database=assetmgmt;host=localhost.domain.com";
        $dbh = DBI->connect($dsn,"prod","dev",) or die ("Error connecting to Asset Management DB!\n");
}

### DB Disconnect
# Self explanatory
sub db_disconnect {
        $dbh->disconnect();
}

###
### READ ONLY File System Check
###

sub rofs_check{
        # This is where we take the list of servers from the DB and process
        # them to check for ROFS for each environment.
        # $pm and $svr are passed and $all_count is returned via
        # data_structure_results{$results} under the Parallel section

        # Reset the Terminal Interface
        `stty sane|tput rs1`;

        # Set the time in epoch
        $epoch = time;
        my ($pm,$svr) = @_;

        # Server exclusion list for various reasons.
        # Don't over compact expression so regex is readable by others
        $pm->finish if ($svr =~ /old|new|xxxx[01|02|03|04/g);

        @ROFS=`/usr/bin/ssh -4 -o GSSAPIAuthentication=no -ntt -q $svr "/bin/cat /proc/mounts"`;

        $rofs_count=0;
        $clean_count=0;
        $total_count=0;

        foreach $instance (@ROFS) {
                chomp $instance;

                # Skip pipes, temporary, removable, virtual, and/or duplicates
                next if ($instance =~ m/nfs|rpc|usb|binfmt_misc|tmpfs|vfadmin|cdrom|iso|^\s*$/i);
                next if $seen{$instance};

                ++$total_count;

                if ($instance =~ /.*?ro,/i) {
                        ++$rofs_count;
                } else {
                        ++$clean_count;
                }
        }

        $all_count = $total_count . " " . $clean_count . " " . $rofs_count;
        return $all_count;
}

###
### Log file Message configuration
###

sub logger {
        # Terminal reset
        `stty sane|tput rs1`;

        # Grab Message to be logged
        my $msg = shift;
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
        $year = sprintf("%02d", $year % 100);
        $mon++;

        # Standard logfile timestamp
        if ( $mon  < 10 ) { $mon  = 0 . $mon  };
        if ( $mday < 10 ) { $mday = 0 . $mday };
        if ( $hour < 10 ) { $hour = 0 . $hour };
        if ( $min  < 10 ) { $min  = 0 . $min  };
        if ( $sec  < 10 ) { $sec  = 0 . $sec  };

        my $stamp = "$mon/$mday/$year $hour:$min:$sec";

        print LOG "$stamp :: $msg\n";
        return;
}