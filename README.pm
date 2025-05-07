# Purpose:
The rofs.pl script is designed to use perl multithreading 
capabilities in order to record the current state of the
environments read-only file systems and report it back to 
Grafana for visual display. 


# Method:
    The rofs script is called via crontab using the root 
    user account on server {localhost}. Server {localhost} 
    must be used because it is the only server provided which 
    contains the necessary SSL Keys for passwordless logins; 
    which is required for the script to work.

    Each environment is called in a series like format; 
    meaning that each environment must successfully complete 
    in order for the next environment to be processed.

    */15 * * * * /opt/rofs/rofs.pl Production && /opt/rofs/rofs.pl Test && /opt/rofs/rofs.pl QA/Sat && /opt/rofs/rofs.pl Development 2>/dev/null

# Required Modules
    Several Perl Modules are required in order for 
    the ROFS script to function properly. The following 
    modules are available for free download using 
    CPAN https://metacpan.org/pod/Parallel::ForkManager:

	Parallel::ForkManager
    Carp
	File::Path
	File::Spec
	File::Temp
	POSIX
	Storable
	Strict

# Installing Modules
    Must be root or equivalent.
    Download the module to local server.
    Decompress the module in target directory:
    gunzip -d <module.tar.gz>

    Unpack the module:
        tar xvf <module.tar>
        Build the module: 
        perl Makefile.PL
        make test
        make install

    The Module(s) is/are now ready to be referenced 
    within the PERL Script. The default modules of 
    strict, warning, and Data::Dumper do not have to 
    be added as they are part of the initial PERL 
    installation and the DBI module is already loaded.

# Running the Script
    When executing the script you will see up to 50 threads as shown below: 

    # ps -aef|grep "/opt/rofs/rofs.pl"|grep -v grep|wc -l
    41

    # ps -aef|grep rofs|grep -v grep
    root     31843 26849  0 10:17 pts/5    00:00:00 /usr/bin/perl /opt/rofs/rofs.pl Production
    root     31871 26849  0 10:17 pts/5    00:00:00 /usr/bin/perl /opt/rofs/rofs.pl Production
    root     31877 26849  0 10:17 pts/5    00:00:00 [rofs.pl] <defunct>
    root     31879 26849  1 10:17 pts/5    00:00:00 [rofs.pl] <defunct>
    root     31880 26849  0 10:17 pts/5    00:00:00 [rofs.pl] <defunct>
    </SNIP>

    NOTE: The <defunct> tag is NOT erroneous. The script calls these <defunct> 
    processes because the REAPER process has not cleaned then up at that point 
    in time. Wait until the script completes you will see all the <defunct> 
    processes cleaned up as demonstrated below:

    # ps -aef|grep -e "/opt/rofs/rofs.pl" -e "defunct"
    root      8029 24856  0 10:25 pts/2    00:00:00 grep /opt/rofs/rofs.pl


# Disclaimer:
"This script is provided 'as is' and without any warranty, 
express or implied, including but not limited to the implied 
warranties of merchantability, fitness for a particular 
purpose, and non-infringement. I will not be liable for any 
damages, including but not limited to direct, indirect, 
incidental, special, consequential, or punitive damages, 
arising out of the use or inability to use this script, 
even if I have been advised of the possibility of such 
damages." 

# Disclaimer:
This script is provided 'as is' and without any warranty, 
express or implied, including but not limited to the implied 
warranties of merchantability, fitness for a particular 
purpose, and non-infringement. I will not be liable for any 
damages, including but not limited to direct, indirect, 
incidental, special, consequential, or punitive damages, 
arising out of the use or inability to use this script, 
even if I have been advised of the possibility of such 
damages.