#!/usr/bin/perl
use LWP::UserAgent;
use LWP::Protocol::http;
use DB_File;
use Sys::Syslog qw( :DEFAULT setlogsock);
use strict;
use warnings;
my $software="CapCron";
my $VERSION="0.9.6";
my $MAPLIMITDEFAULT=20000;
my $ZONELIMITDEFAULT=200;
my @include=();
my %MAPLIST=();
my %ZONELIST=();
my %MAPLIMIT=();
my %ZONELIMIT=();
my %SERVERS=();
my $BASEDIR="/usr/local/capibara/cduck/";

sub parsegroup {
  my @group=@_;
  my($line);
  foreach $line (@group)
  {
    if ($line =~ /^include\s+(http:\/\/\S+)/)
    {
      push(@include,$1);
      syslog "debug", "INC : $1\n";
    }
    elsif ($line =~ /map\s+(\S+)\s+(http:\/\/\S+)(.*)/)
    {
      unless ($MAPLIST{$1}) {
        $MAPLIST{$1}=$2;
        my $map1=$1;
	my $rest=$3;
        if ($rest =~ /^\s+(\d+)/)
        {
           $MAPLIMIT{$map1}=$1;
        }
        else
        {
           $MAPLIMIT{$map1}=$MAPLIMITDEFAULT;
        }
      } 
      else
      {
        syslog "debug", "$1 map redefined, ignoring\n";
      }     
    }
    elsif ($line =~ /zone\s+(\S+)\s+(http:\/\/\S+)(.*)/)
    {
      unless ($ZONELIST{$1}) {
          $ZONELIST{$1}=$2;
          my $zone1=$1;
  	  my $rest=$3;
          if ($rest =~ /^\s+(\d+)/)
          {
             $ZONELIMIT{$zone1}=$1;
          }
          else
          {
             $ZONELIMIT{$zone1}=$MAPLIMITDEFAULT;
          }
      } 
      else
      {
        syslog "debug", "$1 zone redefined, ignoring\n";
      }     
    }
    elsif ($line =~ /server\s+(\S+)\s+(\S+)/)
    {
       unless ($SERVERS{$1}) {$SERVERS{$1}=$2;}
       else
       {
          syslog "debug", "$1 server redefined, ignoring\n";
       }
    }
    else
    {
       syslog "debug", "ERR: $line\n";
    }
  }
}
my ($pnam,$myuid,$mygid);
($pnam,undef,$myuid,$mygid)=getpwnam("capfetch");
unless ($pnam)
{
    syslog "crit", "User capfetch not defined, exiting";
    exit;
}
my $facility="user";
if (-e "${BASEDIR}etc/ilog")
{
  setlogsock('inet');
  if (open(LCONF,"${BASEDIR}etc/ilog"))
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
  if (open(LCONF,"${BASEDIR}etc/ulog"))
  {
    my $facility=<LCONF>;
    close(LCONF);
    chop($facility);
    chomp($facility);
  }
}
my $ok=0;
my ($f1);
foreach  $f1 ("daemon","local0","local1","local2","local3","local4","local5","local6","local7","user")
{ 
  if ($facility eq $f1) {$ok=1;}
}
unless ($ok) {$facility="user";}
openlog("$software","",$facility);
syslog "debug", "Started";
if ($> == 0)
{
  if (-e "${BASEDIR}lib")
  {
    chroot($BASEDIR) || die "Problem with chrooted enviroment\n";
  }
  $(=$mygid;
  $)=$mygid;
  $>=$myuid;
  $<=$myuid;
  unless(($>==$myuid)&&($)==$mygid))
  {                                     
    syslog "crit", "Unable to set uid/gid to secure combination, exiting";
    exit;
  }
  syslog "debug", "UID set to $<";
}     



my $ua=new LWP::UserAgent;
$ua->agent("CapCron/$VERSION " . $ua->agent);
unless (chdir("${BASEDIR}tmp"))
{
  syslog "crit", "Unable to change dir to ${BASEDIR}tmp\n";
  exit;
}
unless (open(GROUP,"${BASEDIR}etc/cduck.conf"))
{
  syslog "crit", "Unable to read ${BASEDIR}etc/cduck.conf\n";
  exit;
}
my @group=<GROUP>;
close(GROUP);
&parsegroup(@group);
my $includecount=0;
while((@include) && ($includecount < 40))
{
   $includecount++;
   my $response;
   my $include=pop(@include);
   my $icsh=$include;
   $icsh =~ s/^......./group_/;
   $icsh=~ s/[^\w]/_/g;
   my $req= new HTTP::Request("GET",$include);
   $response = $ua->request($req);
   if ($response->is_success)
   {
     my $cnt=$response->content;
     $cnt=~ s/\r//g;
     @group=split(/\n/,$cnt);
     &parsegroup(@group);
     open(ICSH,">${BASEDIR}icsh/$icsh");
     print ICSH "$cnt";
     close(ICSH);
   }
   else
   {
     syslog "debug", "Fetch error: $include\n";
     if (open(ICSH,"${BASEDIR}icsh/$icsh"))
     { 
       @group=<ICSH>;
       close(ICSH);
       syslog "debug", "Falling back on cached value\n";
       &parsegroup(@group);
     }
   }
}
open(ZONES,">zones.txt");
open(ZONEINDEX,">zoneindex.txt");
{
my $zone;
foreach $zone (keys %ZONELIST)
{
   print ZONEINDEX "$zone\n";
   my $nslist="";
   {
   my $server;
   foreach $server (keys %SERVERS)
   {
      my $sip=$SERVERS{$server};
      print ZONES "$server\.$zone\tA\t$sip\n";
      $nslist .= "\t$server\t$sip";      
   }
   }
   print ZONES "$zone\tNS\t$nslist\n";
   my $url=$ZONELIST{$zone};
   my $icsh= "zone_$zone";
   $icsh=~ s/[^\w]/_/g;
   my $req= new HTTP::Request("GET",$url);
   my $response = $ua->request($req);
   if ($response->is_success)
   {
     my $cnt=$response->content;
     $cnt=~ s/\r//g;
     my @cnt=split(/\n/,$cnt);
     syslog "debug", "zonefile $zone $#cnt -> $ZONELIMIT{$zone}\n";
     if (scalar(@cnt) > $ZONELIMIT{$zone})
     {
       splice(@cnt,$ZONELIMIT{$zone}+1);
     }
     open(ICSH,">${BASEDIR}icsh/$icsh");
     $cnt=join("\n",@cnt);
     print ICSH "$cnt";
     close(ICSH);
     {
     my $line;
     foreach $line (@cnt)
     {
       if ($line =~ /^(\w+)(\s+)(.*)/)
       { 
         my $lname=$1;
         my $mspace=$2;
         my $rest=$3;
         my $ok=0;
         if ($rest =~ /NS\s+\w+\s+\d+\.\d+\.\d+\.\d+/) {$ok=1;} 
         if ($rest =~ /A\s+\d+\.\d+\.\d+\.\d+/) {$ok=1;}
         #FIXME: this needs to be a bit stricter, need to test all
         #       name/IP combinations for conformance 
         if ($rest =~ /MX\s+[a-zA-Z0-9_\-\.]+\s+\d+\.\d+\.\d+\.\d+/) {$ok=1;} 
         if ($ok)
         {
               if ($lname eq "_")
               {
                 print ZONES "$zone$mspace$rest\n";
               }
               else
               {
                 print ZONES "$lname.$zone$mspace$rest\n";
               }
         }
       }
     }
     }
   }
   else
   {
     syslog "debug",  "Fetch error zone $zone: $url\n";
     if (open(ICSH,"${BASEDIR}icsh/$icsh"))
     { 
       my @cnt=<ICSH>;
       close(ICSH);
       syslog "debug", "Falling back on cached value\n";
       {
       my $line;
       foreach $line (@cnt)
       {
         if ($line =~ /^(\w+)(\s+)(.*)/)
         { 
           my $lname=$1;
           my $mspace=$2;
           my $rest=$3;
           my $ok=0;
           if ($rest =~ /NS\s+\w+\s+\d+\.\d+\.\d+\.\d+/) {$ok=1;} 
           if ($rest =~ /A\s+\d+\.\d+\.\d+\.\d+/) {$ok=1;} 
           if ($rest =~ /MX\s+\d+\s+\w+\s+\d+\.\d+\.\d+\.\d+/) {$ok=1;} 
           if ($ok)
           {
               if ($lname eq "_")
               {
                 print ZONES "$zone$mspace$rest\n";
               }
               else
               {
                 print ZONES "$lname.$zone$mspace$rest\n";
               }
           }
         }
       }
       }
     }

   }
}
}
print ZONES "\n";
close(ZONES);
close(ZONEINDEX);
my %MAPDB;
my $X;
$X = tie(%MAPDB,  'DB_File',"db_current",O_CREAT|O_RDWR, 0640, $DB_BTREE);
{
my $zone;
foreach $zone ("\*",keys %ZONELIST)
{
   my $icsh= "map_$zone";
   if ($zone eq "*") {$icsh= "map_wildcard";}
   $icsh=~ s/[^\w]/_/g;
   my $url=$MAPLIST{$zone};
   if ($url)
   {
   my $req= new HTTP::Request("GET",$url);
   my $response = $ua->request($req);
   if ($response->is_success)
   {
     my $cnt=$response->content;
     $cnt=~ s/\r//g;
     my @lines=split(/\n/,$cnt);
     syslog "debug", "mapfile $zone $#lines -> $MAPLIMIT{$zone}\n";
     if (scalar(@lines) > $MAPLIMIT{$zone})
     {
       splice(@lines,$MAPLIMIT{$zone}+1);
     }
     open(ICSH,">${BASEDIR}icsh/$icsh");
     $cnt=join("\n",@lines);
     print ICSH "$cnt";
     close(ICSH);
     {
     my $line;
     foreach $line (@lines) {
       my ($key,$val)=split(/\;/,$line,2);
       if (($key)&&($val)&&(($zone =~ /\*/) || ($key =~ /${zone}$/)))
       {
         $MAPDB{$key}=$val;
       }
     }
     }
   }
   else
   {
     syslog "debug","Fetch error map $zone: $url\n";
     if (open(ICSH,"${BASEDIR}icsh/$icsh"))
     { 
       my @lines=<ICSH>;
       close(ICSH);
       syslog "debug", "Falling back on cached value\n";
       {
       my $line;
       foreach $line (@lines) {
         my ($key,$val)=split(/\;/,$line,2);
         if (($zone =~ /\*/) || ($key =~ /${zone}$/))
         {
           $MAPDB{$key}=$val;
         }
       }
       }
     }
   }
   }
}
}
undef $X;
untie(%MAPDB);
unlink("${BASEDIR}db/db_current");
rename("${BASEDIR}tmp/db_current","${BASEDIR}db/db_current");
unlink("${BASEDIR}db/zones.txt");
rename("${BASEDIR}tmp/zones.txt","${BASEDIR}db/zones.txt");
unlink("${BASEDIR}db/zoneindex.txt");
rename("${BASEDIR}tmp/zoneindex.txt","${BASEDIR}db/zoneindex.txt");
syslog "debug","done";
