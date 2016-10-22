#!/usr/bin/perl
#First operational version of the trivial intrusion detection system for cduck
use strict;
use warnings;
use Net::Pcap;
use Sys::Syslog qw( :DEFAULT setlogsock);
use strict;
use warnings;
$|=1;
my $software="CapiTIDS";
my $version="0.9.3"; 
my $CBASEDIR="/usr/local/capibara/cduck/";
my $SBASEDIR="/usr/local/capibara/security/";
#Locate all the needed binaries
my (%BINPATH);
{
  my ($path,$bin);
  my (@binlist)=("iptables","ifconfig");
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
     unless ($BINPATH{$bin})
     {
        die "Binary $bin not found";
     }
  }
}
my ($IFCONFIG)=$BINPATH{"ifconfig"};
my ($IPTABLES)=$BINPATH{"iptables"};
#Find out how syslog is to be used
my $facility="user";
if (-e "${CBASEDIR}etc/ilog")
{
  setlogsock('inet');
  if (open(LCONF,"${CBASEDIR}etc/ilog"))
  {
    $facility=<LCONF>;
    close(LCONF);
    chop($facility);
    chomp($facility);
  }
} 
else
{
  setlogsock('unix');
  if (open(LCONF,"${CBASEDIR}etc/ulog"))
  {
    my $facility=<LCONF>;
    close(LCONF);
    chop($facility);
    chomp($facility);
  }
}
my $ok=0;
my ($f1);
foreach  $f1
("daemon","local0","local1","local2","local3","local4","local5","local6","local7","user")
{
  if ($facility eq $f1) {$ok=1;}
}
unless ($ok) {$facility="user";}
# Create a lookup table for devices from the currently configured interfaces
my(%IP2DEV);
open(IFCF,"$IFCONFIG -a|")|| die "Cant start $IFCONFIG";
my $tdevice="";
while(<IFCF>)
{
  if (/^(\w+)\s+Link/) {$tdevice=$1;}
  elsif(/inet addr:(\d+\.\d+\.\d+\.\d+)/)
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
$mfilter =~ s/^\"//;
$mfilter =~ s/\"$//;
$lfilter =~ s/^\"//;
$lfilter =~ s/\"$//;
if ($mdevice =~ /lookup\s+(\d+\.\d+\.\d+\.\d+)/i)
{
  $mdevice=$IP2DEV{$1};
  unless($mdevice)
  {
     print "Unable to lookup mdevice for $1\n";
     exit;
  }
}
if ($device =~ /lookup\s+(\d+\.\d+\.\d+\.\d+)/i)
{
  $device=$IP2DEV{$1};
  unless($device)
  {
     print "Unable to lookup device for $1\n";
     exit;
  }
}
unless ($mdevice && $mfilter && $mtablesfifo)
{
  no warnings;
  print "One of the monitor variables is not set in ids.conf\n";
  print "mdevice = \"$mdevice\"\n";
  print "mfilter = \"$mfilter\"\n";
  print "mtablesfifo = \"$mtablesfifo\"\n";
  exit;
}
unless ($device && $tables && $users)
{
  print "One of the shutdown variables is not set in ids.conf\n";
  exit;
}
unless ($BREACH{"chroot"} && $BREACH{"source"} && $BREACH{"tables"} && $BREACH{"root"})
{
  print "One of the breach variables is not set in ids.conf\n";
  exit;
}
unless ($IDS{chroot} && $IDS{src} && $IDS{system})
{
  print "One of the ids strings is not set for chroot,src and/or system\n";
  exit;
}
#Open all the stuff needed for the pcap logging process
my $err;
print "pcap logging and monitoring process will be listening on $mdevice\n";
my $pcaptl=Net::Pcap::open_live($mdevice,65000,0,0,\$err);
if (!defined($pcaptl))
{
  print "Cant open $mdevice truegh the pcap lib\n";
  exit;
}
my $lfiltert;
if (Net::Pcap::compile($pcaptl,\$lfiltert,$lfilter,1,0))
{
  print "Problem compiling logging filter\n";
  print "$lfilter\n";
  exit;
}
Net::Pcap::setfilter($pcaptl,$lfiltert);
#Open all the stuff needed for the pcap monitoring process
my $pcaptm=Net::Pcap::open_live($mdevice,65000,0,0,\$err);
if (!defined($pcaptl))
{
  print "Cant open $mdevice truegh the pcap lib\n";
  exit;
}
my $mfiltert;
if (Net::Pcap::compile($pcaptm,\$mfiltert,$mfilter,1,0))
{
  print "Problem compiling monitor filter\n";
  print "$mfilter\n";
  exit;
}
Net::Pcap::setfilter($pcaptm,$mfiltert);
# Open the monitoring fifo for use by the fifo monitoring process.
#unless (open(FIFO,"$mtablesfifo"))
#{
#  print "Cant open $mtablesfifo fifo\n";
#  exit;
#}
my ($pclpid);
my ($slgpid);
my ($logpid);
# Fork the emergency logger first as the other processes will need
# to signal this process when things start to smell nasty
if ($logpid = fork)
{
  print "$software $version pcap-logger process to background\n";
}
elsif (defined $logpid)
{
  $SIG{"HUP"}=sub {
     $oklog=0;
  };
  openlog("${software}_pcl","",$facility);
   my ($frame);
   my ($oklog)=1;
   my (@packetbuf) = ();
#  while ($oklog)
#  {
#    my ($pktlog,%hdrlog);
#    if ($pktlog=Net::Pcap::next($pcaptl,\%hdrlog))
#    {
#       if ($#packetbuf >= 1000)
#       {
#          shift(@packetbuf);
#       }
#       push(@packetbuf,$pktlog)
#    }  
#  }
  foreach $frame (@packetbuf)
  {

  }
  exit;
}
