#!/usr/bin/perl
require 5.6.0;
use File::Copy;
use strict;
use warnings;
my $BASEDIR="/usr/local/capibara";
my $INSTDIR="${BASEDIR}/cduck";
my $IDSDIR="${BASEDIR}/security";
my $MANDIR="/usr/share/man";
my %GROUPS=();
my %USERS=();
my %USERSG=();
if ($> !=0)
{
  print "You need to run install as root\n";
  exit;
}
my (%BINPATH);
{
  my ($path,$bin);
  my (@binlist)=("uname");
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
my ($UNAME)=$BINPATH{"uname"};
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
mkdir("$BASEDIR",0755)|| die "Cant create capibara dir $BASEDIR : $!\n";                 
if (-e "$INSTDIR")
{
  print "Cloaking server already installed\n";
  exit;
}
mkdir("$INSTDIR",0755)|| die "Cant create cduck dir\n";
my $subdir;
foreach $subdir ("bin","db","tmp","etc","tmp2","icsh")
{
  mkdir("${INSTDIR}/$subdir",0755)|| die "Cant create $subdir subdir for $INSTDIR\n";
  chown($USERS{"capsys"},$GROUPS{"capibara"},"${INSTDIR}/$subdir");
}
chown($USERS{"capfetch"},$GROUPS{"capibara"},"${INSTDIR}/icsh");
my $target;
foreach $target ("capdb.pl","capdns.pl","caphttp.pl","capcron.pl","snowball.pl")
{
   copy("pkg/$target","${INSTDIR}/bin/$target")|| die "Cant copy pkg/$target to ${INSTDIR}/bin/$target";
   chmod 0700, "${INSTDIR}/bin/$target";  
}
copy("etc/cduck.conf","${INSTDIR}/etc/cduck.conf")|| die "Cant copy etc/cduck.conf to ${INSTDIR}/etc/\n";
chmod 0640, "${INSTDIR}/etc/cduck.conf";
chown(0,$GROUPS{"capibara"},"${INSTDIR}/etc/cduck.conf");
chown($USERS{"capfetch"},$GROUPS{"capibara"},"${INSTDIR}/db");
chown($USERS{"caphttp"},$GROUPS{"capiweb"},"${INSTDIR}/tmp2");
chmod 01770, "${INSTDIR}/tmp";
chmod 0750, "${INSTDIR}/db";
chmod 0755, "${INSTDIR}/bin/capcron.pl";
while (!(-d $MANDIR))
{
  print "\'$MANDIR\' not found, \nplease specify where man files should go:";
  $MANDIR=<>;
  chop($MANDIR);
  unless ($MANDIR) { $MANDIR="[undef]";}
}
if (-e "${MANDIR}/man1/cduck.1")
{
  unlink("${MANDIR}/man1/cduck.1");
  unlink("${MANDIR}/man1/capcron.pl.1");
  unlink("${MANDIR}/man1/capdb.pl.1");
  unlink("${MANDIR}/man1/capns.pl.1");
  unlink("${MANDIR}/man1/caphttp.pl.1");
  unlink("${MANDIR}/man1/captids.pl.1");
  unlink("${MANDIR}/man5/cduck.conf.5");
  unlink("${MANDIR}/man5/tids.conf.5");
  unlink("${MANDIR}/man5/cduck_node.conf.5");
}
unless (-e "${MANDIR}/man1")
{
  mkdir("${MANDIR}/man1",0755);
}
unless (-e "${MANDIR}/man5")
{
  mkdir("${MANDIR}/man5",0755);
}
opendir(MANDIR,"man")|| die "Cant open man dir";
my @manpages=readdir(MANDIR);
closedir(MANDIR);
my $manfile;
foreach $manfile (@manpages)
{
  if ($manfile =~ /^(\w+.*\.(\d))$/)
  {
    copy("man/$1","${MANDIR}/man${2}/$1")|| die "Cant copy man/$1 to ${MANDIR}/man$2/ dir";
    chmod 0644, "${MANDIR}/man${2}/$1";
  }
}
mkdir("$IDSDIR",0700);
mkdir("${IDSDIR}/etc",0700);
mkdir("${IDSDIR}/bin",0700);
mkdir("${IDSDIR}/io",0700);
mkdir("${IDSDIR}/dump",0700);
copy("pkg/captids.pl","${IDSDIR}/bin/captids.pl")|| die "Cant copy pkg/captids.pl to ${IDSDIR}/bin/ dir";
chmod 0700, "${IDSDIR}/bin/captids.pl";
open(HOSTS,"/etc/hosts")|| die "Can't read /etc/hosts\n";
my $loghost="";
while(<HOSTS>)
{
  if (/(^\d+\.\d+\.\d+\.\d+)\s+.*\bloghost\b/)
  {
    $loghost=$1;
  }
}
#unless ($loghost)
#{
#  my ($uname)=`$UNAME -s`;
#  if ($uname =~ /BSD/i)
#  {
#    $loghost="127.0.0.1";
#  }
#}
if ($loghost)
{
  open(OF1,">${IDSDIR}/etc/loghost");
  print OF1 "$loghost\n";
  close(OF1);
  open(OF1,">${INSTDIR}/etc/ilog");
}
else
{
  open(OF1,">${INSTDIR}/etc/ulog");
}
print OF1 "user\n";
close(OF1);
print "DONE\n";

