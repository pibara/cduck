#!/usr/bin/perl
use strict;
use warnings;
use Net::Pcap;
use Sys::Syslog qw( :DEFAULT setlogsock);
$|=1;
my $software="CapiTIDS";
my $version="0.9.6"; 
my $CBASEDIR="/usr/local/capibara/cduck/";
my $SBASEDIR="/usr/local/capibara/security/";
my ($IFCONFIG);
my ($IPTABLES);
my ($KILLALL);
my ($IPFW);
my ($PS);
my ($IPFWCF)="/usr/local/capibara/security/etc/tids_ipfw.conf";
my (%IPFWN2L)=();
my (%IPFWL2N)=();
my ($OS);
sub shutipfw {
  my ($table)=@_;
  my(@tables)=split(/\s+/,$table);;
  syslog "crit", "Closing down subsystem tables: $table";
  foreach $table (@tables)
  {
       my $linenum=$IPFWN2L{$table};
       syslog "crit", "Closing down $table ($linenum) ipfw line";
       `$IPFW delete $linenum`;
       `$IPFW add $linenum unreach filter-prohib ip from any to any`;
  }
  syslog "crit", "Subsystem tables have been closed down";
}
sub shuttables {
  my ($table)=@_;
  my(@tables)=split(/\s+/,$table);;
  syslog "crit", "Closing down subsystem tables: $table";
  foreach $table (@tables)
  {
        syslog "crit", "Closing down $table table";
       `$IPTABLES -F $table`;
       `$IPTABLES -A $table -j REJECT`;
  }
  syslog "crit", "Subsystem tables have been closed down";
}
sub shutusers {
  my($user)=@_;
  my (@users)=split(/\s+/,$user);
  syslog "crit", "Closing down subsystem users: $user";
  foreach $user (@users)
  {
    if (($user =~ /^\w+$/)&&($user ne "root"))
    {
        my ($pscount)=0;
        syslog "crit", "Closing down processes of $user user";
        if ($OS eq "Linux")
        {
          open(PSLIST,"$PS -u $user --no-header|");
        }
        else
        {
          open(PSLIST,"$PS -U $user|");
        }
        while(<PSLIST>)
        {
          if (/^\s*(\d+)\s+.*\s+(\S+)$/)
          {
             my ($pid)=$1;
             my ($procnam)=$2;
             if ($pid >1)
             {
               $pscount++;
               syslog "crit", "killing $procnam ($pid)";
               kill(9,$pid);
             }
          }
        }
        close(PSLIST);
        syslog "crit", "$pscount processes of $user user have been shut down";
    }
  }
  syslog "crit", "Subsystem user processes have been killed";
}
sub shutint {
  my ($device)=@_;
  syslog "crit", "bringing down $device interface";
  `$IFCONFIG $device down`;
  syslog "crit", "Interface $device has been sealed off";
}
sub norestart {
  my ($shutsys)=@_;
  syslog "crit", "setting hint to subsystem to not restart ($shutsys)";
  open(NORES,">${SBASEDIR}etc/norestart");
  close(NORES);
}
#Locate all the needed binaries
my (%BINPATH);
{
  my ($path,$bin);
  my (@binlist)=("iptables","ifconfig","ps","ipfw","uname","killall");
  my (@pathlist)=split(/:/,$ENV{"PATH"});
  my (@basepathlist)=("/usr/local/bin","/usr/local/sbin","/usr/bin","/usr/sbin","/bin","/sbin");
  my (%okpathlist)=();
  foreach $path (@pathlist)
  { 
    $okpathlist{$path}=1;
  }
  foreach $path (@basepathlist)
  { 
    unless ($okpathlist{$path})
    {
       push(@pathlist,$path);
    }
  }
  @basepathlist=reverse(@basepathlist);
  foreach $bin (@binlist)
  {
     foreach $path (@pathlist)
     { 
        if (-f "${path}/$bin")
        {
           $BINPATH{$bin}="${path}/$bin";
        }
     }
     unless (($BINPATH{$bin})||($bin =~ /^ip/))
     {
        die "Binary $bin not found";
     }
  }
}
$IFCONFIG=$BINPATH{"ifconfig"};
$IPTABLES=$BINPATH{"iptables"};
$IPFW=$BINPATH{"ipfw"};
$KILLALL=$BINPATH{"killall"};
{
  my $uname= `$BINPATH{"uname"} -s`;
  if ($uname =~ /^FreeBSD/i) {$OS="FreeBSD";}
  elsif ($uname =~ /^Linux/i) {$OS="Linux";}
  elsif ($uname =~ /BSD/) 
  {
    #Fake FreeBSD for other *BSD flavours, need to test and port to these
    #osses.
    $OS="FreeBSD"; 
  }
  else { $OS="undefined";}
}
unless ($IPTABLES || $IPFW)
{
  die "Neither iptables nor ipfw firewall found";
}

unless ($IPTABLES)
{
  unless(open(IPFWCF,"$IPFWCF"))
  {
    die "Unable to open $IPFWCF";
  }
  while(<IPFWCF>)
  {
    if (/(\w+)\s+(\d+)/)
    {
       $IPFWN2L{$1}=$2;
       my ($count);
       foreach $count (0 .. 19)
       {
         $IPFWL2N{$2+$count}=$1;
       }
    }
  }
}
$PS=$BINPATH{"ps"};
#Find out how syslog is to be used
my $facility="user";
if (-e "${CBASEDIR}etc/ilog")
{
  setlogsock('inet');
} 
else
{
  setlogsock('unix');
}
my $ok=0;
my ($f1);
foreach  $f1
("daemon","local0","local1","local2","local3","local4","local5","local6","local7","user")
{
  if ($facility eq $f1) {$ok=1;}
}
unless ($ok) {$facility="daemon";}
openlog("${software}_main","",$facility);
# Create a lookup table for devices from the currently configured interfaces
my(%IP2DEV);
open(IFCF,"$IFCONFIG -a|")|| die "Cant start $IFCONFIG";
my $tdevice="";
while(<IFCF>)
{
  if (/^(\w+)\s+Link/) {$tdevice=$1;}
  elsif (/^(\w+):\s+flags/) {$tdevice=$1;}
  elsif(/inet addr:(\d+\.\d+\.\d+\.\d+)/)
  {
    $IP2DEV{$1}=$tdevice;
  }
  elsif(/^\s+inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask/)
  {
    $IP2DEV{$1}=$tdevice;
  }
}
#Fetch the tids config from the config file
open(IDSCF,"${SBASEDIR}etc/tids.conf")|| die "Can't open ${SBASEDIR}etc/tids.conf\n";
my (%IDS)=();
my(%BREACH);
while(<IDSCF>)
{
  if (/^(\w+)\s+(\S+.*\S)/)
  {
    unless($1 eq "breach")
    {
      $IDS{$1}=$2;
    }
    else
    {
      my($line);
      $line=$2;
      if ($line =~ /^(\w+)\s+(\w+.*\w)/)
      {
        $BREACH{$1}=$2;
      }
    }
  }
}
close(IDSCF);
my($mdevice)= $IDS{"mdevice"};
my($mfilter)= $IDS{"mfilter"};
my($mtablesfifo)= $IDS{"mtablesfifo"};
my($device)= $IDS{"device"};
my($tables)= $IDS{"tables"};
my($users)= $IDS{"users"};
my($lfilter)= $IDS{"lfilter"};
my($lbuffer)=$IDS{"lbuffer"};
#If not defined in tids.conf set lbuffer to 1000 frames
unless ($lbuffer) {$lbuffer=1000;}
$mfilter =~ s/^\"//;
$mfilter =~ s/\"$//;
$lfilter =~ s/^\"//;
$lfilter =~ s/\"$//;
if ($mdevice =~ /lookup\s+(\d+\.\d+\.\d+\.\d+)/i)
{
  $mdevice=$IP2DEV{$1};
  unless($mdevice)
  {
     syslog "crit", "Unable to lookup mdevice for $1";
     exit;
  }
}
if ($device =~ /lookup\s+(\d+\.\d+\.\d+\.\d+)/i)
{
  $device=$IP2DEV{$1};
  unless($device)
  {
     syslog "crit", "Unable to lookup device for $1";
     exit;
  }
}
unless ($mdevice && $mfilter && $mtablesfifo)
{
  no warnings;
  syslog "crit", "One of the monitor variables is not set in ids.conf";
  syslog "crit", "mdevice = \"$mdevice\"";
  syslog "crit", "mfilter = \"$mfilter\"";
  syslog "crit", "mtablesfifo = \"$mtablesfifo\"";
  exit;
}
unless ($device && $tables && $users)
{
  syslog "crit", "One of the shutdown variables is not set in ids.conf";
  syslog "crit", "device = \'$device'";
  syslog "crit", "tables = \'$tables'";
  syslog "crit", "users  = \'$users'";
  exit;
}
unless ($BREACH{"chroot"} && $BREACH{"source"} && $BREACH{"tables"} && $BREACH{"system"})
{
  syslog "crit", "One of the breach variables is not set in ids.conf";
  syslog "crit", "breach source = \'$BREACH{source}\'";
  syslog "crit", "breach chroot = \'$BREACH{chroot}\'";
  syslog "crit", "breach root   = \'$BREACH{system}\'";
  syslog "crit", "breach tables = \'$BREACH{tables}\'";
  exit;
}
unless ($IDS{chroot} && $IDS{src} && $IDS{system})
{
  syslog "crit", "One of the ids strings is not set for chroot,src and/or system";
  syslog "crit", "chroot = \'$IDS{chroot}\'";
  syslog "crit", "src    = \'$IDS{src}\'";
  syslog "crit", "system = \'$IDS{system}\'";
  exit;
}
#Open all the stuff needed for the pcap logging process
my $err;
#print "pcap logging and monitoring process will be listening on $mdevice\n";
my $pcaptl=Net::Pcap::open_live($mdevice,65000,0,0,\$err);
if (!defined($pcaptl))
{
  syslog "crit", "Cant open $mdevice truegh the pcap lib";
  exit;
}
my $lfiltert;
if (Net::Pcap::compile($pcaptl,\$lfiltert,$lfilter,1,0))
{
  syslog "crit", "Problem compiling logging filter";
  exit;
}
Net::Pcap::setfilter($pcaptl,$lfiltert);
#Open all the stuff needed for the pcap monitoring process
my $pcaptm=Net::Pcap::open_live($mdevice,65000,0,0,\$err);
if (!defined($pcaptm))
{
  syslog "crit", "Cant open $mdevice truegh the pcap lib";
  exit;
}
my $mfiltert;
if (Net::Pcap::compile($pcaptm,\$mfiltert,$mfilter,1,0))
{
  syslog "crit", "Problem compiling monitor filter";
  syslog "crit", "$mfilter";
  exit;
}
Net::Pcap::setfilter($pcaptm,$mfiltert);
# Open the monitoring fifo for use by the fifo monitoring process.
unless (-e "$mtablesfifo")
{
  syslog "crit", "$mtablesfifo fifo does not exist";
  exit;
}
my ($pclpid);
my ($slgpid);
my ($logpid);
#print "Forking the emergency logger\n";
# Fork the emergency logger first as the other processes will need
# to signal this process when things start to smell nasty
if ($logpid = fork)
{
#  print "$software $version pcap-logger process to background\n";
}
elsif (defined $logpid)
{
  openlog("${software}_pcl","",$facility);
  syslog "notice", "Starting with lbuffer=$lbuffer";
  my (@packetbuf) = ();
  my (@hdrbuf) = ();
  $SIG{"HUP"}=sub {
     #Flush the buffered stuf to a pcap file
     my($frame);
     my ($seccount)=2;
     my $time=time();
     my $output="";
     unless (-e "${SBASEDIR}dump/${time}.pcap")
     {
       $output=Net::Pcap::dump_open($pcaptm, "${SBASEDIR}dump/${time}.pcap"); 
       syslog "notice", "Dumping pcap buffer to ${SBASEDIR}dump/${time}.pcap pcap file";
     }
     else
     {
       while (-e "${SBASEDIR}dump/${time}_${seccount}.pcap") {$seccount++;}
       $output=Net::Pcap::dump_open($pcaptm, "${SBASEDIR}dump/${time}_${seccount}.pcap"); 
       syslog "notice", "Dumping pcap buffer to ${SBASEDIR}dump/${time}_${seccount}.pcap pcap file";
     }
     if ($output)
     {
        my ($packet);
        my (%hdrlog);
        while ( ($packet=shift(@packetbuf)) &&
                (%hdrlog = split(/###/,shift(@hdrbuf)))
              )
        {
          Net::Pcap::dump($output, \%hdrlog, $packet)
        }
        Net::Pcap::dump_close($output);
        syslog "notice", "Done dumping to pcap file";
     }
     else
     {
       syslog "notice", "Cant open pcap file for writing : $!";
     }   
  };
  while (1)
  {
    my ($pktlog,%hdrlog);
    if ($pktlog=Net::Pcap::next($pcaptl,\%hdrlog))
    {
       if ($#packetbuf >= $lbuffer)
       {
          shift(@packetbuf);
          shift(@hdrbuf);
       }
       push(@packetbuf,$pktlog);
       push(@hdrbuf,join("###",%hdrlog));
    }  
  }
}
else
{
  syslog "crit", "pcap-logger FORK ERROR";
  exit;
} 
#print "Forking the syslog monitor process\n";
if ($slgpid = fork)
{
 # print "$software $version syslog monitor process to background\n";
}
elsif (defined $slgpid)
{
  openlog("${software}_slm","",$facility);
  syslog "notice", "Start";
  while (!(open(FIFO,"$mtablesfifo")))
  {
    syslog "notice", "(re)opening of fifo $mtablesfifo failed.";
  }
  syslog "notice", "FIFO $mtablesfifo, (re)opened";
  while(1)
  {
     while (<FIFO>)
     {
       if (/tids:compromized\s+(\w+)/)
       {
          syslog "crit", "Subsystem $1 compromized (tables), sealing off subsystem";
          my (@shutdownlist)=split(/\s+/,$BREACH{"tables"});
          my ($shutsys);
          foreach $shutsys (@shutdownlist)
          {
             if ($shutsys =~ /tables/i) {&shuttables($tables);}
             elsif ($shutsys =~ /users/i) {&shutusers($users);}
             elsif ($shutsys =~ /interface/i) {&shutint($device);}
             elsif ($shutsys =~ /norestart/i) {&norestart($shutsys);}
          }
          syslog "crit", "All actions completed for shuting down subsystem";
          syslog "notice", "Asking pcap logger to flush its recent history to disk";
          kill(1,$logpid);
       }
       elsif (/\/kernel:\s+ipfw:\s+(\d+)\s+/)
       {
          my ($subsys)=$IPFWL2N{$1};
          if ($subsys)
          {
            syslog "crit", "Subsystem $subsys compromized (ipfw), sealing off subsystem";
            my (@shutdownlist)=split(/\s+/,$BREACH{"tables"});
            my ($shutsys);
            foreach $shutsys (@shutdownlist)
            {
               if ($shutsys =~ /tables/i) {&shutipfw($tables);}
               elsif ($shutsys =~ /users/i) {&shutusers($users);}
               elsif ($shutsys =~ /interface/i) {&shutint($device);}
               elsif ($shutsys =~ /norestart/i) {&norestart($shutsys);}
            }
            syslog "crit", "All actions completed for shuting down subsystem";
            syslog "notice", "Asking pcap logger to flush its recent history to disk";
            kill(1,$logpid);
          }
       }
     }
  }
  syslog "notice", "Lost connection to fifo, reopening";
  close(FIFO);
}
else
{
  syslog "crit", "pcap-logger FORK ERROR\n";
  kill(9,$logpid);
  exit;
} 

# Now fork the pcap monitoring process.
#print "Forking the pcap monitor process\n";
if ($pclpid = fork)
{
 # print "$software $version pclmon process to background\n";
}
elsif (defined $pclpid)
{
  openlog("${software}_pcm","",$facility);
  syslog "notice", "Start";
  while(1)
  {
    my ($pkt,%hdr);
    if ($pkt=Net::Pcap::next($pcaptm,\%hdr))
    {
     my ($subsys)="";
     my ($clean)=1;
     if ($pkt =~ /$IDS{system}/)
     {
        $clean=0;
        $subsys="system";
     }
     elsif ($pkt =~ /$IDS{src}/)
     {
        $clean=0;
        $subsys="src";
     }
     elsif ($pkt =~ /$IDS{chroot}/)
     {
        $clean=0;
        $subsys="chroot";
     }
     unless ($clean)
     {
        syslog "crit", "Subsystem $subsys compromized, sealing off subsystem";
        my (@shutdownlist)=split(/\s+/,$BREACH{$subsys});
        my ($shutsys);
        foreach $shutsys (@shutdownlist)
        {
           if ($shutsys =~ /tables/i) {&shuttables($tables);}
           elsif ($shutsys =~ /users/i) {&shutusers($users);}
           elsif ($shutsys =~ /interface/i) {&shutint($device);}
           elsif ($shutsys =~ /norestart/i) {&norestart($shutsys);}
        }
        syslog "crit", "All actions completed for shuting down subsystem";        
        syslog "notice", "Asking pcap logger to flush its recent history to disk";
        kill(1,$logpid);
     }
    }
  }
}
else
{
  syslog "crit", "pclmon FORK ERROR";
  kill(9,$logpid);
  kill(9,$slgpid);
  exit;
} 
#On FreeBSD we need to kill -1 the syslogd in order for
#it to talk with the tids named pipe.
sleep(2);
`$KILLALL -1 syslogd`;
print "$software $version All subsystems started\n";
