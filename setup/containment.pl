#!/usr/bin/perl
require 5.6.0;
use File::Copy;
use IO::Socket::UNIX;
require POSIX;
use strict;
use warnings;
my %GROUPS=();
my %USERS=();
my %USERSG=();
my %IDS=();
if ($> !=0)
{
  print "You need to run install as root\n";
  exit;
} 
print "WARNING !! This is a verry crude setup script for a chroot
enviroment for cduck, it might not work completely or it might give
you to big a chrooted enviroment compared to the strict needs.
Please feel free to patch this script to a bit smarter.
If you do so please share it with the author.\n\n";
#Carefull changing the next line please !!
my $BASEDIR="/usr/local/capibara/";
my $INSTDIR="${BASEDIR}cduck";
my $IDSDIR="${BASEDIR}security";
my $ipfw_startnum=100;
my $ipfw_skip1=$ipfw_startnum+9;
my $ipfw_CAPDB=$ipfw_startnum+10;
my $ipfw_CAPDBi=$ipfw_startnum+10;
my $ipfw_CAPDNS=$ipfw_startnum+30;
my $ipfw_CAPDNSi=$ipfw_startnum+30;
my $ipfw_CAPHTTP=$ipfw_startnum+50;
my $ipfw_CAPHTTPi=$ipfw_startnum+50;
my $ipfw_CAPFETCH=$ipfw_startnum+70;
my $ipfw_CAPFETCHi=$ipfw_startnum+70;
my $ipfw_endnum=$ipfw_startnum+90;
my $bindip=0;
my $extip=0;
unless (open(NC,"${INSTDIR}/etc/cduck_node.conf"))
{
  print "Cant read ${INSTDIR}/etc/cduck_node.conf\n";
  exit 1;
}
while(<NC>)
{
  if (/^bindip\s+(\S+)$/) {$bindip=$1;}
  if (/^extip\s+(\S+)$/) {$extip=$1;}    
}
close(NC);
unless ($bindip) {print "No bindip found in ${INSTDIR}/etc/cduck_node.conf\n";}
unless ($extip) {print "No extip found in ${INSTDIR}/etc/cduck_node.conf\n";}
unless (($bindip) && ($extip)) {exit 1;} 
my (%BINPATH);
{
  my ($path,$bin);
  my (@binlist)=("iptables","ipfw","objdump","find","hostname");
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
        unless ($bin =~ /^ip/)
        {
          die "Binary $bin not found";
        }
     }
  }
}
my ($IPTABLES)=$BINPATH{"iptables"};
my ($IPFW)=$BINPATH{"ipfw"};
my ($OBJDUMP)=$BINPATH{"objdump"};
my ($FIND)=$BINPATH{"find"};
my ($HOSTNAME)=`$BINPATH{"hostname"}`;chomp($HOSTNAME);
my ($NOFIREWALL)=0;
unless ($IPTABLES || $IPFW)
{
  print "\n\nWARNING: Neither iptables nor ipfw was found on this system\n";
  print "         There will be NO FIREWALLING on this system for cduck\n\n";
  $NOFIREWALL=1;
}
my $FIREWALL;
if ($IPTABLES)
{
  $FIREWALL="iptables";
}
elsif($IPFW)
{
  $FIREWALL="ipfw";
  open(IPFWCF,">${BASEDIR}security/etc/tids_ipfw.conf");
  print IPFWCF "CAPDB\t$ipfw_CAPDB\n";
  print IPFWCF "CAPDNS\t$ipfw_CAPDNS\n";
  print IPFWCF "CAPHTTP\t$ipfw_CAPHTTP\n";
  print IPFWCF "CAPFETCH\t$ipfw_CAPFETCH\n";
  close(IPFWCF);
}
open(IDS,"${IDSDIR}/etc/tids.conf")|| die "tids.conf not found\n";
while(<IDS>)
{
  if (/^(\w+)\s+(\w+)/)
  {
    #print "$1 : $2\n";
    $IDS{$1}=$2;
  }
}
close(IDS);
my $group;
foreach $group ("capibara","capiweb")
{
 
   (undef,undef,$GROUPS{$group})=getgrnam($group);
   unless ($GROUPS{$group})
   {
       print "group $group not found\n\n";
       print "Please create the groups \'capibara\' and \'capiweb\' first\n";
       print "and create the following members to this group:\n";
       print "capibara\n\n\tcapfetch\n\tcapdb\n\tcapdns\ncapiweb\n\tcaphttp\n\n";
       exit;
   }
} 
my $user;
foreach $user ("capdb","caphttp","capdns","capfetch","capsys")
{
   (undef,undef,$USERS{$user},$USERSG{$user})=getpwnam($user);
   unless (($USERS{$user})&&($USERSG{$user}))
   {
      if ($user eq "caphttp")
      {
         print "Please create the $user as member of capiweb\n";
         exit;
      }
      else
      {
         print "Please create the $user as member of capibara\n";
         exit;
      }
   }
   elsif ($user eq "caphttp")
   {
      unless ($USERSG{$user} == $GROUPS{"capiweb"})
      {
         print "Please set the gid for caphttp to $GROUPS{capiweb}\n";
         exit;
      }
   }
   else
   {
      unless ($USERSG{$user} == $GROUPS{"capibara"})
      {
         print "Please set the gid for $user to $GROUPS{capibara}\n";
         exit;
      }
   }
} 
print "Creating group file\n";
#if (-e "${INSTDIR}/etc/group") {die "Oops, chrooted dir installed already";}
open(GROUP,">${INSTDIR}/etc/group");
print GROUP "root:x:0:root\n";
print GROUP "capibara:x:$GROUPS{capibara}:capdb,capsys,capdns,capfetch\n";
print GROUP "capiweb:x:$GROUPS{capiweb}:caphttp\n";
close(GROUP);
print "Creating passwd file\n";
#if (-e "${INSTDIR}/etc/passwd") {die "Oops, chrooted dir installed already";}
open(PASSWD,">${INSTDIR}/etc/passwd");
print PASSWD "root:x:0:0:root:/$IDS{chroot}:/bin/$IDS{chroot}\n";
print PASSWD "capdb:x:$USERS{capdb}:$GROUPS{capibara}::${INSTDIR}:/bin/sh\n";
print PASSWD "capsys:x:$USERS{capsys}:$GROUPS{capibara}::${INSTDIR}:/bin/sh\n";
print PASSWD "capdns:x:$USERS{capdns}:$GROUPS{capibara}::${INSTDIR}:/bin/sh\n";
print PASSWD "capfetch:x:$USERS{capfetch}:$GROUPS{capibara}::${INSTDIR}:/bin/sh\n";
print PASSWD "caphttp:x:$USERS{caphttp}:$GROUPS{capiweb}::${INSTDIR}:/bin/sh\n"; 
close(PASSWD);
if ($FIREWALL)
{
 print "Creating $FIREWALL example script\n";
 open(IPTSH,">${IDSDIR}/bin/capcontain.sh");
 if ($IPTABLES) {
 print IPTSH "#!/bin/sh
$IPTABLES -N CAPDB
$IPTABLES -N CAPDNS
$IPTABLES -N CAPHTTP
$IPTABLES -N CAPFETCH
$IPTABLES -F CAPDB
$IPTABLES -F CAPDNS
$IPTABLES -F CAPHTTP
$IPTABLES -F CAPFETCH
$IPTABLES -A CAPDB -d 127.0.0.1 -p udp --sport 9595 -j ACCEPT
$IPTABLES -A CAPDNS -p udp --sport 53 -j ACCEPT
$IPTABLES -A CAPHTTP -p tcp --sport 80 -m state --state ESTABLISHED -j ACCEPT
$IPTABLES -A CAPHTTP -d 127.0.0.1 -p udp --dport 9595 -j ACCEPT\n";
 }
 else
 {
  print IPTSH "#!/bin/sh
$IPFW add $ipfw_skip1 skipto $ipfw_endnum ip from any to any
$IPFW add $ipfw_CAPDBi allow udp from 127.0.0.1 9595 to 127.0.0.1
$IPFW add $ipfw_CAPDNSi allow udp from me 53 to any
$IPFW add $ipfw_CAPHTTPi allow tcp from me 80 to any established\n";
$ipfw_CAPDBi++; $ipfw_CAPDNSi++; $ipfw_CAPHTTPi++;
print IPTSH "$IPFW add $ipfw_CAPDBi allow udp from 127.0.0.1 to 127.0.0.1 9595
$IPFW add $ipfw_CAPDNSi allow udp from any to me 53
$IPFW add $ipfw_CAPHTTPi allow tcp from any to me 80\n";
$ipfw_CAPDBi++; $ipfw_CAPDNSi++; $ipfw_CAPHTTPi++;
print IPTSH "$IPFW add $ipfw_CAPHTTPi allow udp from 127.0.0.1  to 127.0.0.1 9595\n";
$ipfw_CAPHTTPi++;
print IPTSH "$IPFW add $ipfw_CAPHTTPi allow udp from 127.0.0.1  9595 to 127.0.0.1\n";
   $ipfw_CAPHTTPi++;
  }
 if (-e "${IDSDIR}/etc/loghost")
 {
  open(LH,"${IDSDIR}/etc/loghost")|| die "Cant open ${IDSDIR}/etc/loghost for reading";
  my $lh=<LH>;
  chomp($lh);
  chomp($lh);
  if ($lh =~ /^\d+\.\d+\.\d+\.\d+$/)
  {
    if ($IPTABLES)
    {
      print IPTSH "$IPTABLES -A CAPHTTP -d $lh -p udp --dport 514 -j ACCEPT\n";
      print IPTSH "$IPTABLES -A CAPDB -d $lh -p udp --dport 514 -j ACCEPT\n";
      print IPTSH "$IPTABLES -A CAPDNS -d $lh -p udp --dport 514 -j ACCEPT\n";
    }
    else
    {
      print IPTSH "$IPFW add $ipfw_CAPHTTPi allow udp from me to $lh 514\n";
      $ipfw_CAPHTTPi++;
      print IPTSH "$IPFW add $ipfw_CAPHTTPi allow udp from $lh 514 to me\n";
      $ipfw_CAPHTTPi++;
      print IPTSH "$IPFW add $ipfw_CAPDBi allow udp from me to $lh 514\n";
      $ipfw_CAPDBi++;
      print IPTSH "$IPFW add $ipfw_CAPDBi allow udp from $lh 514 to me\n";
      $ipfw_CAPDBi++;
      print IPTSH "$IPFW add $ipfw_CAPDNSi allow udp from me to $lh 514\n";
      $ipfw_CAPDNSi++;
      print IPTSH "$IPFW add $ipfw_CAPDNSi allow udp from $lh 514 to me\n";
      $ipfw_CAPDNSi++;
    }
  }
 }
 if ($IPTABLES)
 {
  print IPTSH "$IPTABLES -A CAPDB -j LOG --log-prefix \"tids:compromized capdb \"
$IPTABLES -A CAPDNS -j LOG --log-prefix \"tids:compromized capdns \"
$IPTABLES -A CAPHTTP -j LOG --log-prefix \"tids:compromized caphttp \"\n";
print IPTSH "$IPTABLES -A CAPDB -j REJECT
$IPTABLES -A CAPDNS -j REJECT
$IPTABLES -A CAPHTTP -j REJECT\n";
 }
 else
 {
      print IPTSH "$IPFW add $ipfw_CAPDBi unreach filter-prohib log ip from any to any\n";
      print IPTSH "$IPFW add $ipfw_CAPDNSi unreach filter-prohib log ip from any to any\n";
      print IPTSH "$IPFW add $ipfw_CAPHTTPi unreach filter-prohib log ip from any to any\n";
 }
 open(RESOL,"/etc/resolv.conf")|| die "Can't open /etc/resolv.conf\n";
 my $resolok=0;
 while (<RESOL>)
 {
  if (/^nameserver\s+(\d+\.\d+\.\d+\.\d+)\b/)
  {
    $resolok=1;
    if ($IPTABLES)
    {
     print IPTSH "$IPTABLES -A CAPFETCH -d $1 -p udp --dport 53 -j ACCEPT\n";
    }
    else
    {
      print IPTSH "$IPFW add $ipfw_CAPFETCHi allow udp from me to $1 53\n";
      $ipfw_CAPFETCHi++;
      print IPTSH "$IPFW add $ipfw_CAPFETCHi allow udp from $1 53 to me\n";
      $ipfw_CAPFETCHi++;
    } 
  }
 }
 unless ($resolok) {
  die "System has no nameserver specified in /etc/resolv.conf"; 
 }
 if ($IPTABLES) {
 print IPTSH "#You will want to replace this line with more restrictive filters that allow
#trafic only to the webservers and their specific ports we fetch our config from.
$IPTABLES -A CAPFETCH -p tcp -j ACCEPT
$IPTABLES -A CAPFETCH -j LOG --log-prefix \"tids:compromized capfetch \"
$IPTABLES -A CAPFETCH -j REJECT\n";
print IPTSH "$IPTABLES -A OUTPUT -m owner --uid-owner $USERS{capdb} -j CAPDB\n";
print IPTSH "$IPTABLES -A OUTPUT -m owner --uid-owner $USERS{capdns} -j CAPDNS\n";
print IPTSH "$IPTABLES -A OUTPUT -m owner --uid-owner $USERS{caphttp} -j CAPHTTP\n";
print IPTSH "$IPTABLES -A OUTPUT -m owner --uid-owner $USERS{capfetch} -j CAPFETCH\n";
 }
 else
 {
   print IPTSH "#You will want to replace this line with more restrictive filters that allow
   #trafic only to the webservers and their specific ports we fetch our config from.\n";
   print IPTSH "$IPFW add $ipfw_CAPFETCHi allow tcp from me to any\n";
   $ipfw_CAPFETCHi++;
   print IPTSH "$IPFW add $ipfw_CAPFETCHi allow tcp from any to me established\n";
   $ipfw_CAPFETCHi++;
   print IPTSH "$IPFW add $ipfw_CAPFETCHi unreach filter-prohib log ip from any to any\n";
   print IPTSH "$IPFW add $ipfw_startnum skipto $ipfw_CAPDB ip from any to any uid $USERS{capdb} \n";
   $ipfw_startnum++;
   print IPTSH "$IPFW add $ipfw_startnum skipto $ipfw_CAPDNS ip from any to any uid $USERS{capdns} \n";
   $ipfw_startnum++;
   print IPTSH "$IPFW add $ipfw_startnum skipto $ipfw_CAPHTTP ip from any to any uid $USERS{caphttp} \n";
   $ipfw_startnum++;
   print IPTSH "$IPFW add $ipfw_startnum skipto $ipfw_CAPFETCH ip from any to any uid $USERS{capfetch} \n";
 }
 close(IPTSH);
 chmod(0700,"${IDSDIR}/bin/capcontain.sh");
}
print "Gathering information on required libs\n";
my @mainobjects;
my @inclibs=();
my %inclibs=();
my %libs=();
my %startlib=();
$startlib{"DB_File.so"}=1;
$startlib{"Fcntl.so"}=1;
$startlib{"POSIX.so"}=1;
$startlib{"Socket.so"}=1;
$startlib{"Hostname.so"}=1;
$startlib{"Syslog.so"}=1;
$startlib{"libperl.so"}=1;
$startlib{"Heavy.pm"}=1;
$startlib{"Symbol.pm"}=1;
$startlib{"SelectSaver.pm"}=1;
$startlib{"IO.pm"}=1;
$startlib{"Errno.pm"}=1;
$startlib{"Config.pm"}=1;
$startlib{"INET.pm"}=1;
$startlib{"UNIX.pm"}=1;
my $perldir="/usr/lib/perl5";
unless(-e "/usr/lib/perl5")
{
  $perldir="/usr/local/lib/perl5";
}
open(FIND,"$FIND $perldir |")|| die "Cant spawn $FIND on $perldir";
while(<FIND>)
{
  if ((/\/([^\/]+\.so)$/)||(/\/([^\/]+\.pm)$/)||(/\/([^\/]+\.so\.\d+)$/))
  {
     if (($startlib{"$1"})||
         (/Carp\/([^\/]+)$/)||
         (/URI\/([^\/]+)$/)||
         (/LWP\/([^\/]+\.pm)$/)||
         (/HTTP\/([^\/]+)$/)||
         (/IO\/([^\/]+)$/)||
         (/LWP\/Protocol\/([^\/]+)$/)
        )
     { 
       chomp(); 
       push(@mainobjects,$_);
       push(@inclibs,$_);
     }
  }
}
close(FIND);

my $searchdir;
foreach $searchdir ("/lib","/usr/lib","/usr/local/lib")
{
  if (-e $searchdir)
  {
   open(FIND,"$FIND $searchdir -type f |")||die "Cant spawn $FIND on $searchdir";
   while(<FIND>)
   {
     if (/\/([^\/]+\.so[0-9\.]*)$/)
     {
       my $filename=$1;
       if (
	   ($filename =~ /^libresolv/)||
	   ($filename =~ /^libnss_dns/)||
           ($filename =~ /^libnss_files/)||
           ($filename =~ /^libsafe/)||
           ($filename =~ /^ISO8859-1\./))
       {
          chomp(); 
          push(@mainobjects,$_);
          push(@inclibs,$_);
       }
     }
   }  
   open(FIND,"$FIND $searchdir -type l |")||die "Cant spawn $FIND on $searchdir";
   while(<FIND>)
   {
     if (/\/([^\/]+\.so[0-9\.]*)$/)
     {
       my $filename=$1;
       if (
	   ($filename =~ /^libresolv/)||
	   ($filename =~ /^libnss_dns/)||
           ($filename =~ /^libnss_files/)||
           ($filename =~ /^libsafe/)||
           ($filename =~ /^ISO8859-1\./))
       {
          chomp(); 
          push(@mainobjects,$_);
          push(@inclibs,$_);
       }
     }
   }
  }  
}
push(@mainobjects,"/usr/bin/perl");
my $someobject;
foreach $someobject (@mainobjects)
{
  #print "Object dumping $someobject\n";
  unless ($someobject =~ /\.pm$/)
  {
    open(OBJDUMP,"$OBJDUMP -p  $someobject|")|| die "Can't spawn $OBJDUMP on $someobject";
    my $rpath="";
    while(<OBJDUMP>)
    {
      chomp;
      if (/^\s*NEEDED\s+(\S+)/) {$libs{$1}=1;}
      #if (/^\s*RPATH\s+(\S+)/) { $rpath=$1;}
    }
    close(OBJDUMP);
  }
};
my $somelib;
foreach $somelib (keys %libs)
{
  my @libpaths=("/lib","/usr/lib","/usr/local/lib");
  my $libpath;
  foreach $libpath (@libpaths)
  { 
    if (-f "${libpath}/$somelib")
    {
       push(@inclibs,"${libpath}/$somelib");
       $inclibs{"$somelib"}="${libpath}/$somelib";
    }
  }
}
my $found=1;
FIND: while($found)
{
  $found=0;
  foreach $somelib (@inclibs)
  {
    #print "Object dumping lib $somelib\n";
    unless ($somelib =~ /\.pm$/)
    {                              
    open(OBJDUMP,"$OBJDUMP -p  $somelib|")|| die "Cant spawn $OBJDUMP on $somelib";
    while(<OBJDUMP>)
    {
       if (/^\s*NEEDED\s+(\S+)/) 
       {
          unless ($inclibs{"$1"})
          {
              my $somelib=$1;
              my @libpaths=("/lib","/usr/lib","/usr/local/lib");
              my $libpath;
              foreach $libpath (@libpaths)
              { 
                 if (-f "${libpath}/$somelib")
                 {
                    $found=1;
                    push(@inclibs,"${libpath}/$somelib");
                    $inclibs{"$somelib"}="${libpath}/$somelib";
                    next FIND;
                 }
              }
          }
       }
    }
    }
  }
}

print "Copiing required files and dirs\n";
my $reqlib="";
foreach $reqlib (@inclibs)
{
  #print "\t$reqlib , copiing\n";
  my $libstr=$reqlib;
  $reqlib =~ s/^.//;
  my @libtokens=split(/\//,$reqlib);
  my $filename=pop(@libtokens);
  my $maindir="";
  my $token;
  foreach $token (@libtokens)
  {
     $maindir .= "\/$token";
     unless (-e "$INSTDIR$maindir")
     {
       #print "\t\tCreating dir \'$INSTDIR$maindir\'\n";
       mkdir("$INSTDIR$maindir",0755);
     }     
  }
  #print "Copiing \'$libstr\' to \'${INSTDIR}$libstr\'\n";
  if (-e "${INSTDIR}$libstr") {unlink("${INSTDIR}$libstr");}
  copy($libstr,"${INSTDIR}$libstr");
  chmod 0644, "${INSTDIR}$libstr";   
}
unless (-e "${INSTDIR}/etc/protocols")
{
  copy("/etc/protocols","${INSTDIR}/etc/protocols");
  copy("/etc/services","${INSTDIR}/etc/services");
  copy("/etc/resolv.conf","${INSTDIR}/etc/resolv.conf");
}
{
 my (@INSTDIRPARTS)=split(/\//,$INSTDIR);
 my ($CHDLINK)="";
 my ($i1);
 foreach $i1 (0 .. $#INSTDIRPARTS-1)
 {
  if ($INSTDIRPARTS[$i1])
  {
    $CHDLINK .= "/" . $INSTDIRPARTS[$i1];
    mkdir("$INSTDIR$CHDLINK");
  }
 }
 $CHDLINK .= "/" . $INSTDIRPARTS[$#INSTDIRPARTS];
 symlink("/","$INSTDIR$CHDLINK");
}
mkdir("$INSTDIR/dev",0755);
my $dir;
foreach $dir ("$INSTDIR/dev","$INSTDIR/etc","$INSTDIR/bin","$INSTDIR/db","$INSTDIR/icsh","$INSTDIR/tmp","$INSTDIR/tmp2","$INSTDIR/usr")
{
  open(IDSBAIT,">$dir/$IDS{chroot}")|| die "Cant open $dir/$IDS{chroot} for writing";
  print IDSBAIT "$IDS{chroot}\n";
  print IDSBAIT "This file is meant for trivial intrusion detection by the captids process\n";
  close(IDSBAIT);
}
unlink("dyn/idscleanup.sh")|| die "Can't remove dyn/idscleanup.sh\n";
open(UNINSTALL,">dyn/idscleanup.sh")||die "Can't rewrite dyn/idscleanup.sh script $!";
print UNINSTALL "#!/bin/sh\n";
print UNINSTALL "/bin/rm -rf /usr/local/capibara\n";
foreach $dir ("/etc","/bin","/usr")
{
  print UNINSTALL "/bin/rm $dir/$IDS{system}\n";
  open(IDSBAIT,">$dir/$IDS{system}")|| die "Can't open $dir/$IDS{system} for writing";
  print IDSBAIT "$IDS{system}\n";
  print IDSBAIT "This file is meant for trivial intrusion detection by the captids process\n";
  close(IDSBAIT);
}
close(UNINSTALL);
chmod 0755,"dyn/idscleanup.sh";
open(IDSBAIT,">$INSTDIR/etc/hosts")|| die "Cant open $INSTDIR/etc/hosts for writing";
print IDSBAIT  "127.0.0.1               localhost.localdomain localhost $HOSTNAME\n";
print IDSBAIT  "$bindip             www.dummy1.org dummy1\n";
if ($bindip ne $extip)
{
  print IDSBAIT  "$extip             www.dummy2.org dummy1\n";
}
print IDSBAIT  "192.168.1.1             www.$IDS{chroot}.org www\n";
close(IDSBAIT);
unless (-e "${IDSDIR}/etc/loghost")
{
  unless (link("/dev/log","${INSTDIR}/dev/log"))
  {
    print "\n\nWARNING: Unable to hardlink ${INSTDIR}/dev/log to /dev/log\n\n";
    my ($syslogsock)=IO::Socket::UNIX->new( Type => SOCK_DGRAM,Local=>"${INSTDIR}/dev/log");
    chmod(0622,"${INSTDIR}/dev/log");
    print "********************************************************************\n";
    print "* You will need to add the option '-a ${INSTDIR}/dev/log' (Linux)\n"; 
    print "*                              or '-l ${INSTDIR}/dev/log' (FreeBSD)\n";
    print "* to the rc startup script of your syslogd !!!\n";
    print "* YOU MUST RESTART THE SYSLOGD FIRST NOW BEFORE YOU CAN START CDUCK !!!\n";
    print "********************************************************************\n";
  }
}
unless ($NOFIREWALL)
{
  POSIX::mkfifo("${IDSDIR}/io/ids",0600);
  print "********************************************************************\n";
  print "* You will need to add the folowing line to your /etc/syslog.conf\n";
  print "* 'before' you restart your syslogd:\n";
  print "* 'kern.*		|/usr/local/capibara/security/io/ids\n";
  print "* For FreeBSD try using:\n";
  print "* 'security.*		/usr/local/capibara/security/io/ids\n";
  print "* You may need to play a litle with the startup sequence for\n";
  print "* syslogd and tids and perhaps with -1 signals to your syslogd\n";
  print "********************************************************************\n";
}
my ($file1);
foreach $file1 ("capcron.pl","capdb.pl","capdns.pl", "caphttp.pl")
{
  open (OUT,">>${INSTDIR}/bin/$file1");
  print OUT "# $IDS{src}\n";
  close(OUT);
}
print "containment installed.\n\n";
print "You now may wish to test the chrooted enviroment for the correct working\n";
print "off the daemons and the capcron.pl script\n\n";
print "If the subsystems work dont forget to ";
unless ($NOFIREWALL)
{
  print "incorporate ${IDSDIR}/bin/capcontain.sh into your\n";
  print "$FIREWALL configuration, and to ";
}
print "ad rc/tids to your rc startup scripts\n";
print "in order to run the trivial intrusion detection system\n\n";
