#!/usr/bin/perl
# Automated Agent Repair script 2.0.

use warnings;
use strict;
use POSIX;
use Term::ANSIColor;
use Term::Cap;

=doc

	Name:			AARS.pl #A2RS.pl
	Description:	OMI Agent Automated Repair Script
	
=cut


###
### Script Variables
###
my $debug = 1;
my %seen;
my ($pt, $pn, $spn, $dps, $tbs, $disabled, @stored_policies);
my ($pagt, $mproc, $mtbs, $an, $san, $as, $ac);
my (@stored_agent_proc, @agt_processes, $mpols);
my $tbs_framework = `ps -aef|grep -i -e corba_agent|grep -v -e grep -e looping`;
my $local_host = `hostname --short`;
my @msga_query = `sudo /opt/OV/lbin/eaagt/opcmsga -status 2>&1`;

# Counters & Flags
my $msgagt_reset_cnt = 0;
my $agt_buf_cnt = 0;
my $mpols_flag  = 0;
my $mtbs_flag   = 0;
my $mproc_flag  = 0;
my $pagt_flag   = 0;
my $dp_cnt      = 0;

# Initialize arrays empty
my @nl = (); # Holds policy line data for PolicyCheck 
my @dl = (); 
my @al = ();
my @running = ();
my @missing_pols = ();
my @disabled_pols = ();
my @missing_procs = ();
my @disabled_procs = ();
my @missing_tbs_pols = ();

# Stored LISTS
my @agt_ovc_procs = qw{ovbbccb ovcd ovcs ovconfd};

my @agt11_stored_procs = qw{scopeux midaemon ttd perfalarm perfd agtrep coda
                            ompolparm opcacta opcle opcmona opcmsga opcmsgi
                            rtmd};

my @agt12_stored_procs = qw{midaemon ttd perfalarm agtrep hpsensor oacore
                            ompolparm opcacta opcle opcmona opcmsga opcmsgi};

my @stored_pols = ("\"OPC_PERL_INCLUDE_INSTR_DIR\"","\"ALL_CORE_syslogng\"","\"QA-OPS_LINUX_LocalFS_Log\"","\"LINUX_FS_MON\"","\"LINUX_MEM_MON\"","\"LINUX_PROC_MON _RHEL6_7\"","\"UNIX_CORE_Syslog-ng\"","\"CORE_opcmsg\"","\"CYBERARK_Health\"","\"Sys_SystemDiscovery\"");

my @tbs_stored_pols = ("\"APP_Log_Monitor\"","\"FRAMEWORKS_Agent_ITOPS\"","\"FRAMEWORKS_PROCESS_STATUS_LOG\"","\"FRAMEWORK_Corba_Agent\"","\"FRAMEWORK_LoopingCorbaAgent\"");

###
### LogFile Creation
###

# id = corp login id 
chomp $local_host;
my $LogFile  = "/export/home/{id}/agt_$local_host.log";
open(LOG, "> $LogFile") or die "Can't open $LogFile. $!\n" if $debug;

###
### Agent Versioning
###

my $agt_ver  = `sudo /opt/OV/bin/opcagt -version`;
chomp $agt_ver;

$agt_ver = substr $agt_ver, 0,2;

if ($agt_ver == 11) {
    @stored_agent_proc = @agt11_stored_procs;
} else {
    @stored_agent_proc = @agt12_stored_procs;
}

###
### MAIN Section
###

if ($local_host =~ m/Zhpomi|Znnm/i) {
    &logger("Local machine \"$local_host\" is an OMI Mgmt Server -\
             exiting script!") if $debug;
    exit 0;
} else {
    &policy_check;
    &agent_check;
    &agent_buffering;
    &agent_certs;
}


### BASE Policy Check - LOGGING
foreach $mpols (@missing_pols) {
    &logger("BASE POLICY $mpols:\[MISSING\]") if $debug;
    $mpols_flag++;
}

if ($mpols_flag > 0)  {
    &logger("MISSING BASE POLICY CHECK:\[FAILED\]") if $debug;
} else {
    &logger("MISSING BASE POLICY CHECK:\[PASSED\]") if $debug;
}

# BASE Disabled Policy - LOGGING
foreach $disabled (@disabled_pols) {
    &logger("POLICY $disabled:\[DISABLED\]") if $debug;

    if ($disabled) {
        `sudo /opt/OV/bin/ovpolicy -enable -polname $disabled`;
        if ($? == 0) {
            &logger("POLICY $disabled RE-ENABLEMENT:\[SUCCEEDED\]") if $debug;
        } else {
            &logger("POLICY $disabled RE-ENABLEMENT:\[FAILED\]") if $debug;
        }
    }

}

if ($dp_cnt == 0) { &logger("DISABLED POLICY CHECK:\[PASSED\]") if $debug; }


# TBS FRAMEWORK Missing Policies - LOGGING
# only if CORBA_AGT process found

if ($tbs_framework =~ /corba_agent/i) {
    foreach $mtbs (@missing_tbs_pols) {
        &logger("POLICY $mtbs:\[MISSING\]") if $debug;
        $mtbs_flag++;
    }
}

if ($tbs_framework =~ /corba_agent/i) {
    if ($mtbs_flag > 0) {
        &logger("MISSING POLICY CHECK:\[FAILED\]") if $debug;
    } else {
        &logger("MISSING POLICY CHECK:\[PASSED\]") if $debug;
    }
}


### OMI Agent Missing Processes - LOGGING
foreach $mproc (@missing_procs) {
   &logger("AGENT PROCESS $mproc:\[MISSING\]") if $debug;
    if ($mproc) {
        `sudo /opt/OV/bin/opcagt -start $mproc`;
        if ($? == 0) {
            &logger("MISSING AGENT PROCESS CHECK:\[PASSED\]") if $debug;
        } else {
            &logger("MISSING AGENT PROCESS CHECK:\[FAILED\]") if $debug;
        }
    }
}

### Agent Disabled/Stopped Process - LOGGING
foreach $pagt (@disabled_procs) {
    &logger("AGENT PROCESS $pagt:\[STOPPED\]") if $debug;
    if ($pagt) {
        `sudo /opt/OV/bin/ovc -start $pagt`;
        my $ps = `ps -aef|grep -i $pagt|grep -v grep`;

        if ($ps) {
            &logger("Restart of $pagt:\[SUCCEEDED]") if $debug;
        } else {    
            &logger("Restart of $pagt:\[FAILED\]") if $debug;
            $pagt_flag++;
        }
    }
}

if ($pagt_flag > 0) {
    &logger("RUNNING AGENT PROCESS Check:\[FAILED\]") if $debug;
} else {
    &logger("RUNNING AGENT PROCESS Check:\[PASSED\]") if $debug;
}


### Cleanup
close (LOG);
exit 0;



#######################################################
###
### Subroutines
###
#######################################################


# POLICY_CHECK
# Running Policy Check against STORED LIST subroutine
# Populates @running with just the policy name
# which is then dumped into the special array %seen
# at which point it is compared against @stored_policies
# If not found in @stored then push onto @missing_pols

sub policy_check {

    my @pol_query  = `sudo /opt/OV/bin/ovpolicy -l`;

    if ($? != 0) {
        &logger("Error executing \"/opt/OV/bin/ovpolicy -l\" on $local_host") if $debug;
    } else {
        foreach (@pol_query) {
            chomp $_;
            next if (($_ !~ /\w+/)||($_ =~ m/Type|localhost|^\s*$/i));
            next if $seen{$_};

            @nl = split '\"', $_;
            $pt = $nl[0];
            $pt =~ s/^\s+$//;
            $pn = $nl[1];
            $pn = "\"$pn\"";

            if (($pn =~ /LINUX_CPU_MON/)||($pn =~ /UNIX_AGENT_HEALTH/)) {
                # `sudo /opt/OV/bin/ovpolicy -remove -polname $pn -host $local_host`;
                &logger("FOUND Policy $pt:$pn loaded on $local_host") if $debug;
            }
    
            if ($_ =~ m/disabled/i) {
                push @disabled_pols, $pn;
                $dp_cnt++;
            }
    
            push @running, $pn;
        }
    
        @seen{@running} = ();
    
        if ($tbs_framework =~ /corba_agent/i) {
            foreach $tbs(@tbs_stored_pols) {
                push(@missing_tbs_pols, $tbs) unless exists $seen{$tbs};
            }
        }
    
        foreach $spn(@stored_pols) {
            push(@missing_pols, $spn) unless exists $seen{$spn};
        }
    }
}


# AGENT_CHECK
# Agent Process Check Subroutine

sub agent_check {

    my @agt_query  = `sudo /opt/OV/bin/opcagt 2>&1`;

    if ($? != 0) {
        &logger("Error executing \"/opt/OV/bin/opcagt\" on $local_host.") if $debug;
    } else {
        my @seen = ();
        foreach my $ap (@agt_query) {
            chomp $ap;
            next if (($ap!~ /\w+/)||($ap =~ m/^Agent|^Message|omi|\-$|^\s*$/i));
            next if $seen{$ap};
            @al = split ' ', $ap;
            $ac = $#al;
            $an = $al[0];
            $as = $al[$ac];
    
            if ($as =~ m/stopped/i) {
                push @disabled_procs, $an;
            }
    
            push @agt_processes, $an;
        }
    
        @seen{@agt_processes} = ();
    
        foreach $san(@stored_agent_proc) {
            push(@missing_procs, $san) unless exists $seen{$san};
        }
    }
}


# AGENT_BUFFERING
# Check Agent for message Buffering

sub agent_buffering {

    my @msga_query = `sudo /opt/OV/lbin/eaagt/opcmsga -status 2>&1`;

    if ($? != 0) {
        &logger("Error executing \"/opt/OV/lbin/eaagt/opcmsga -status\" on $local_host\n") if $debug;
    } else {
        foreach my $agtbuf (@msga_query) {
    
            chomp $agtbuf;
            next if (($agtbuf !~ /\w/)||($agtbuf =~ m/^Agent Health/));

            if (($agtbuf =~ m/Message Agent buffering/i)||($agtbuf =~ m/Could not contact Message Agent/i)) {
                &logger("AGENT BUFFERING CHECK:\[FAILED\]") if $debug;
                `sudo /opt/OV/bin/ovc -stop opcmsga 2>&1`;
                `sudo /opt/OV/bin/ovc -start opcmsga 2>&1`;
            
                if ($? == 0) {
                    my $cur_buf_state = `sudo /opt/OV/lbin/eaagt/opcmsga -status|grep -i "Message Agent is not buffering"`;
                    unless ($cur_buf_state) {
                        &logger("AGENT BUFFERING RESET:\[FAILED\]") if $debug;
                        $agt_buf_cnt++;
                    } else {
                        &logger("AGENT BUFFERING RESET:\[SUCCEEDED\]") if $debug;
                    }   
                } else {
                    &logger("MESSAGE AGENT RESET:\[FAILED\]") if $debug;
                    $msgagt_reset_cnt++;
                }
    
            }
        }
        unless (($agt_buf_cnt > 0)||($msgagt_reset_cnt > 0)) { &logger("AGENT BUFFERING CHECK:\[PASSED\]") if $debug; }
    }
}

# AGENT_CERTS
# Checks Agent Certificates

sub agent_certs {

    my @certs = `sudo /opt/OV/bin/ovcert -status 2>&1`;
    my $cert;

    if ($? != 0) {
        &logger("Error executing \"/opt/OV/bin/ovcert -status\" on $local_host") if $debug;
    } else {
 	       foreach $cert(@certs) {
 	               chomp $cert;

 	               if ($cert =~ m/Certificate is installed/i) {
 	                       &logger("AGENT CERTIFICATE CHECK:\[PASSED\]") if $debug;
 	               } else {
                &logger("AGENT CERTIFICATE CHECK:\[FAILED\]") if $debug;
            }
        }
    }
}


# LOGGER
# Creates standardized logfile entries

sub logger {
       my $msg = shift;
       my ($sec, $min,$hour,$mday, $mon,$year, $wday,$yday,$isdst) = localtime(time);
       $year = sprintf("%02d", $year % 100);
       $mon++;

    # Standard logfile timestamp
       if ( $mon  < 10 ) { $mon  = 0 . $mon  };
       if ( $mday < 10 ) { $mday = 0 . $mday };
       if ( $hour < 10 ) { $hour = 0 . $hour };
       if ( $min  < 10 ) { $min  = 0 . $min  };
       if ( $sec  < 10 ) { $sec  = 0 . $sec  };

       my $stamp = "$mon/$mday/$year $hour:$min:$sec";

    if ($msg =~ m/\[MISSING\]$|\[DISABLED\]$|\[FAILED\]$|\[STOPPED\]$/) {
        our @msg_str = split ":", "$msg";
        our $lname = $msg_str[0];
        our $lstat = $msg_str[1];
        return print LOG colored(sprintf("%-17s%2s%-50s%-15s\n", $stamp,": ",$lname,$lstat), 'red');
        return printf("%-17s%2s%-50s%-15s\n", $stamp,": ",$lname,$lstat);
    } elsif ($msg =~ m/\[RUNNING\]$|\[SUCCEEDED\]$|\[PASSED\]$/) {
        our @msg_str = split ":", "$msg";
        our $lname = $msg_str[0];
        our $lstat = $msg_str[1];
        return print LOG colored(sprintf("%-17s%2s%-50s%-15s\n", $stamp,": ",$lname,$lstat), 'green');
        return printf("%-17s%-2s%-50s%-15s\n", $stamp,": ",$lname,$lstat);
    } else {
        return print LOG colored(sprintf("%-17s%-2s%-50s\n", $stamp,": ",$msg), 'cyan');
        return printf("%-17s%-2s%-50s\n", $stamp,": ",$msg);
    }

    return;
}
