#!/usr/bin/perl
require 5.6.0;
use strict;
use warnings;
use File::Copy;
my $BASEDIR="/usr/local/capibara";
my $INSTDIR="${BASEDIR}/cduck";
my $IDSDIR="${BASEDIR}/security";
my (%BINPATH);
{
  my ($path,$bin);
  my (@binlist)=("ifconfig","gcc","uname");
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
my ($GCC)=$BINPATH{"gcc"};
my ($uname)=`$BINPATH{"uname"} -s`;
open(IFC,"$IFCONFIG -a|")|| die "Can't spawn $IFCONFIG with -a option";
my $guesip="";
while(<IFC>)
{
  if ((/addr:(\d+\.\d+\.\d+\.\d+)/)||(/inet\s+(\d+\.\d+\.\d+\.\d+)\snetmask/))
  {
    my ($thisip)=$1;
    if (! ($guesip)) { $guesip=$thisip; }
    elsif ($guesip eq "127.0.0.1") {$guesip=$thisip; }
    elsif (($guesip =~ /^192\.168\./)||($guesip =~ /^10\./)||($guesip =~ /^172\.16\./))
    {
       unless ($thisip eq "127.0.0.1") { $guesip=$thisip;}
    }
  }
}
my $setip="";
while (! $setip)
{
  print "\n\nWhat IP should cduck listen on [$guesip] : ";
  my $sip1=<>;
  chomp($sip1);
  chomp($sip1);
  unless ($sip1) {$sip1=$guesip;}
  if ($sip1 =~ /^(\d+\.\d+\.\d+\.\d+)$/)
  {

    $setip=$1;
  }
  unless ($setip) {print "Invalis IP adress\n";}
}
print "Seting bind IP adress to $setip\n";
open(MYIP,">${INSTDIR}/etc/cduck_node.conf")|| die "Can't open ${BASEDIR}/etc/cduck_node.conf for writing";
print MYIP "bindip\t$setip\n";
open(MYFILT,">${IDSDIR}/etc/tids.conf")|| die "Can't open ${IDSDIR}/etc/tids.conf for writing";
print MYFILT "#Monitor config\n";
print MYFILT "mdevice lookup $setip\n";
print MYFILT "mfilter \"src host $setip and src port 80  or src host $setip and src port 53\"\n";
print MYFILT "mtablesfifo /usr/local/capibara/security/io/ids\n";
print MYFILT "#Monitor bait strings\n";
my $bait;
srand;
my $SRCBAIT="";
foreach $bait ("system","chroot","src")
{
  my ($index,$rand2,$max);
  $max=28 + int(rand(18));
  foreach $index (0 .. $max)
  {
    $rand2 .= ("a".."z","A".."Z")[int(rand(52))];
  }
  print MYFILT "$bait\t$rand2\n";
  if ($bait eq "src") {$SRCBAIT=$rand2;}
}
print MYFILT "#Shutdown config\n";
print MYFILT "device lookup $setip\n";
print MYFILT "tables CAPDB CAPDNS CAPHTTP CAPFETCH\n";
print MYFILT "users capdb capdns caphttp capfetch\n";
print MYFILT "#Logging Config\n";
print MYFILT "lfilter \"dst host $setip and dst port 80  or dst host $setip and dst port 53\"\n";
print MYFILT "lbuffer 1000\n";
print MYFILT "#Security breach actions\n";
print MYFILT "breach chroot tables users norestart\n";
print MYFILT "breach source tables users norestart\n";
print MYFILT "breach tables tables users norestart\n";
print MYFILT "breach system interface users norestart\n";
close(MYFILT);
$guesip=$setip;
$setip="";
while (! $setip)
{
  print "\n\nWhat is the 'externall' IP cduck is on [$guesip] : ";
  my $sip1=<>;
  chomp($sip1);
  chomp($sip1);
  unless ($sip1) {$sip1=$guesip;}
  if ($sip1 =~ /^(\d+\.\d+\.\d+\.\d+)$/)
  {

    $setip=$1;
  }
  unless ($setip) {print "Invalis IP adress\n";}
}
print "Seting ext IP adress to $setip\n";
print MYIP "extip\t$setip\n";
my $setemail="";
while(! $setemail)
{
  print "\n\nWhat is the email adress of the administrator : ";
  my $email=<>;
  chomp($email);
  if ($email)
  {
    my ($user,$domain) = split (/\@/,$email);
    if (($user =~ /^\w[a-zA-Z0-9\._-]*\w$/) &&($domain =~ /^\w[a-zA-Z0-9\._-]*\w$/))
    {
       $setemail="${user}.$domain";
    }
  } 
}
print MYIP "rp\t$setemail\n";
close(MYIP);
open(HEADER,">c/breach.h")|| die "CANT OPEN c/breach.h FOR WRITING\n";
print HEADER "#define SERVER      \"a-server.rootserver.net\"\n";
print HEADER "#define SERVERPORT  8888\n";
print HEADER "#define BREACH     \"$SRCBAIT\"\n";
close(HEADER);
my ($llib)="";
if ($uname =~ /SunOS/)
{
  $llib="-lnsl -lsocket";
}
`$GCC c/tidsshout.c -o c/tidsshout $llib`;
if (-f "c/tidsshout")
{
   copy("c/tidsshout","${INSTDIR}/bin/sh")|| die "Can't copy c/tidsshout to ${INSTDIR}/bin/sh";  
   chmod(0555,"${INSTDIR}/bin/sh"); 
}
print "Done\n";
