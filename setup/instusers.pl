#!/usr/bin/perl
require 5.6.0;
use File::Copy;
use strict;
use warnings;
my $INSTDIR="/usr/local/capibara/cduck";
my $uname="";
my (%BINPATH);
{
  my ($path,$bin);
  my (@binlist)=("uname");
  my (@binlist2)=();
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
  $uname=`$BINPATH{"uname"} -s`;
  if ($uname =~ /Linux/)
  {
     print "Running in Linux mode\n"; 
     @binlist2=("useradd","groupadd");
  }
  elsif ($uname =~ /^FreeBSD/)
  {
     print "Running in FreeBSD mode\n"; 
     @binlist2=("vipw");
  }
  elsif ($uname =~ /SunOS/)
  {
     print "Running in Solaris mode\n"; 
     @binlist2=("useradd","groupadd");
  }
  elsif ($uname =~ /BSD/)
  {
     print "Only *BSD type currently tested is FreeBSD\n";
     print "Do you wish me to assume the freebsd defaults? (y/n) :";
     my $answer=<>;
     if ($answer =~ /y/i)
     {
        print "Assuming FreeBSD defaults, please keep the author posted\n";
        print "on your results with $uname\n";
        $uname="FreeBSD";
        @binlist2=("adduser");
     }
  }
  else
  {
     die "Unsupported platform $uname";
  }
  foreach $bin (@binlist2)
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
my($GROUPADD)=$BINPATH{"groupadd"};
my($USERADD)=$BINPATH{"useradd"};
my($ADDUSER)=$BINPATH{"adduser"};
my %GROUPS=();
my %USERS=();
my %USERSG=();
if ($> !=0)
{
  print "You need to run this script as root\n";
  exit 1;
}
print "This script will try to create new groups and users on your system\n";
print "Are you sure you want to do this ? (y/N):";
my $line = <>;
unless ($line =~ /[yY]/)
{
  print "Ok, please create the users and groups by hand\n";
  die "Died on user request";
}
my $group;
foreach $group ("capibara","capiweb")
{
  my $time;
  for $time (0,1)
  {
     (undef,undef,$GROUPS{$group})=getgrnam($group);
     unless ($GROUPS{$group})
     {
        if ($time == 1)
        {
           print "Oops, seems like creating the group $group failed, please fix manualy\n";
           exit;
        }
        else
        {
            print "Creating new group $group\n";
            if (($uname =~ /Linux/)||($uname =~ /SunOS/))
            {
              `$GROUPADD $group`;
            }
            else #FreeBSD
            {
               print "groupadd $group\n";
               # I don not like doing it this way and should not,
               # but i know to litle of *bsd to do it any better way.
               # please send me your briljant patches if you will ;-)
               open(GROUP,"/etc/group");
               my $exist=0;
               my $newid=1001;
               while(<GROUP>)
               {
                 my @grline=split(/:/);
                 my $grnam=$grline[0];
                 my $grnum=$grline[2];
                 if ($grnum)
                 {
                   if ($grnam eq $group) {$exist=1;}
                   if (($grnum >= $newid) && ($grnum < 19999))
                   {
                     $newid=$grnum+1;
                   }
                 }
               }
               close(GROUP);
               if ($newid < 20000)
               {
                 open(GROUP,">>/etc/group");
                 print GROUP "${group}:*:$newid:\n";
                 close(GROUP);
               }
            }
        }
     }
  }
}
my $user;
if ($uname =~ /FreeBSD/)
{
  open(PASSWD2,">passwd.addlines");
}
my $newid=1000;
foreach $user ("capdb","caphttp","capdns","capfetch","capsys")
{
  my $time;
  for $time (0,1)
  {

     (undef,undef,$USERS{$user},$USERSG{$user})=getpwnam($user);
     unless (($USERS{$user})&&($USERSG{$user}))
     {
        if ($time == 1)
        {
             if (   ($uname =~ /Linux/)
                 || ($uname =~ /SunOS/)
                )
             {
               print "Oops, seems like creating the user $user failed, please fix manualy\n";
               exit;
             }
        }
        else
        {
          $group=$GROUPS{"capibara"};
          my $shell;
          if (   ($uname =~ /Linux/)
              || ($uname =~ /SunOS/)
             )
          {
            $shell="/bin/true";
          }
          else #FreeBSD
          {
            $shell="/sbin/nologin";
          }
          if ($user eq "caphttp")
          {
             $group=$GROUPS{"capiweb"};
          }
          print "Creating new user $user\n";
          if ($uname =~ /Linux/)
          {
             `$USERADD -s $shell -g $group -d $INSTDIR -M -r $user`;
          }
          elsif ($uname =~ /SunOS/)
          {
             `$USERADD -s $shell -g $group -d $INSTDIR $user`;
          }
          else #FreeBSD
          {
               print "useradd $user\n";
               # I don not like doing it this way and should not, it is evill
               # but i know to litle of *bsd to do it any better way.
               # please send me your briljant patches if you will.
               open(PASSWD,"/etc/passwd");
               $newid++;
               my $exist=0;
               while(<PASSWD>)
               {
                 my @pwline=split(/:/);
                 my $pwnam=$pwline[0];
                 my $pwnum=$pwline[2];
                 if ($pwnum)
                 {
                   if ($pwnam eq $user) {$exist=1;}
                   if (($pwnum >= $newid) && ($pwnum < 19999))
                   {
                     $newid=$pwnum+1;
                   }
                 }
               }
               close(PASSWD);
               if ($newid < 20000)
               {
                 print PASSWD2 "${user}:*:${newid}:${group}::0:0:${user}:${INSTDIR}:$shell\n";
               }
          }
        }
     }
  }
}                         
if ($uname =~ /FreeBSD/)
{
  close(PASSWD2);
  print "The lines that are to be added to the password file are in passwd.addlines\n";
  print "Please use vipw to add this file to the end of your password file\n";
}
print "Done\n";
