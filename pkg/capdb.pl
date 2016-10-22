#!/usr/bin/perl
#
##########################################
#     Capibara DB  0.9.6		 # 
#                                        #
# This server is the beta version of the #
# Database part of the distributed       #
# cloaking server.                       #
#                                        #
##########################################
use Socket;
use English;
use DB_File;
use Sys::Syslog qw( :DEFAULT setlogsock);
#use Fcntl 'F_DUPFD';
use strict;
use warnings;
$|=1;
my $software="CapiDB";
my $version="0.9.6";
my $BASEDIR="/usr/local/capibara/cduck/";

my (%BINPATH);
{
  my ($path,$bin);
  my (@binlist)=("ps");
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
       unless ($path =~ /ucb/) #Nasty patch
       {
        if (-f "${path}/$bin")
        {
           $BINPATH{$bin}="${path}/$bin";
        }
       }
     }
     unless ($BINPATH{$bin})
     {
        die "Binary $bin not found";
     }
  }
}
my ($PS)=$BINPATH{"ps"};
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

if (open(PID,"${BASEDIR}tmp/capdb.pid"))
{
  syslog "debug", "PID file found\n";
  my $opid=<PID>;
  chomp($opid);
  close(PID);
  unless ($opid =~ /^\d+$/)
  {
    syslog "crit", "HEY, SOMEONE FUCKED UP MY PIDFILE ${BASEDIR}tmp/capdb.pid";
    print  "FAIL: HEY, SOMEONE FUCKED UP MY PIDFILE ${BASEDIR}tmp/capdb.pid";
    exit;
  }
  syslog "debug", "Checking for process with pid $opid";
  open(PS,"$PS -p $opid|");
  my $killit=0;
  while (<PS>)
  {
     if (/capdb/)
     {
       $killit=1;
     }
  }
  close(PS);
  if ($killit)
  {
    syslog "debug", "Killing old instance";
    kill(9,$opid);
    sleep(1);
  }
  else
  {
    syslog "debug", "pid file apears to be old";    
  }
} 
my $port=9595;
my $udp=getprotobyname('udp');
unless (socket(UDPH, PF_INET, SOCK_DGRAM, $udp))
{
           syslog "crit", "$software $version : Unable to create udp socket";
           print "FAIL: $software $version : Unable to create udp socket";
	   exit;
}  
unless (bind(UDPH, sockaddr_in($port, INADDR_LOOPBACK)))
{
           syslog "crit", "$software $version : Unable to bind to socket";
           print "FAIL: $software $version : Unable to bind to socket";
           exit;
}
my ($pnam,$myuid,$mygid);
($pnam,undef,$myuid,$mygid)=getpwnam("capdb");
unless ($pnam)
{
    syslog "crit", "User capdb not defined, exiting";
    print "FAIL : User capdb not defined, exiting\n";
    exit;
}
unless (($> == 0)||($> == $myuid))
{
    syslog "crit", "Started as non-root, non capdb user, exiting";
    print "FAIL : Started as non-root, non capdb user, exiting\n";
    exit;
}
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
    print "Unable to set uid/gid to secure combination, exiting\n";
    exit;
  }
  syslog "debug", "UID set to $<";
}
my $pid;
unless (defined($ARGV[0]) && ($ARGV[0] eq "nobg")){
if ($pid = fork)
{
  print "$software $version to background\n";
  exit;
}
unless (defined $pid)
{
  print "$software $version FORK ERROR\n";
  exit;
}
}
open(PIDFIL,">${BASEDIR}tmp/capdb.pid");
print PIDFIL "$$\n";
close(PIDFIL);
my %MAPPER=();
no warnings;
no strict;
unless (tie(%MAPPER,  'DB_File',"${BASEDIR}db/db_current",0, 0, $DB_BTREE))
{
  use warnings;
  use strict;
  syslog "crit", "Cant open db file";
  print "FAIL: $software $version , Cant open db file ${BASEDIR}db/db_current\n";
  exit;
}
use warnings;
use strict;
my @dbstatold=stat("${BASEDIR}db/db_current");
while(1)
{
  my $data="";
  my $sender=recv(UDPH,$data,128,0);
  if ($sender && $data)
  {
       my($rport, $raddr) = sockaddr_in($sender);
       my $peer_addr = inet_ntoa($raddr); 
       if ($peer_addr eq "127.0.0.1")
       {
         my $host=$data;
         my $html="";
         $host =~ s/[^a-zA-Z0-9_\-]+/\./;
         my @dbstatnew=stat("${BASEDIR}db/db_current");
         if ($dbstatold[9] != $dbstatnew[9])
         {
           no warnings;
           no strict;
           untie(%MAPPER);
           syslog "debug", "DB file change detected, reopening database\n";
	   unless(tie(%MAPPER,  'DB_File',"${BASEDIR}db/db_current",0, 0,$DB_BTREE))
	   {
                # Could be race condition, lets wait and try again
                sleep(2);
		unless(tie(%MAPPER,  'DB_File',"${BASEDIR}db/db_current",0, 0,$DB_BTREE))
	   	{
   		  syslog "crit", "Cant re-open db file ${BASEDIR}db/db_current";
  		  exit;
                }
	   }
           use warnings;
           use strict;
           @dbstatold=@dbstatnew;
         }
         no warnings;
         no strict;
         if ($MAPPER{$host} == 1)
         {
           use warnings;
           use strict;
           my $keywords=$MAPPER{"keywords:$host"};
           unless ($keywords) {$keywords="xcapi";}
           my $title=$MAPPER{"titel:$host"};
           unless($title) {$title=$host;}
           my $url=$MAPPER{"url:$host"};
           if ($url)
           {
             $html="<HTML><HEAD><TITLE>$title</TITLE></HEAD><META name=\"keywords\" content=\"$keywords\">
		  <FRAMESET rows=\"*,0\" frameborder=no border=0>
		  <FRAME name=\"webmapper\" src=\"$url\" noresize></FRAMESET></HTML>\n";
              syslog "debug", "Successfull request for $host from $peer_addr";
           }
           else
           {
             syslog "debug", "Incomplete mapper for $host requested from from $peer_addr";
             $html="ERR:1";
           }
         }
         elsif ($MAPPER{$host} == 2)
         {
             syslog "debug", "Request for banned mapper $host requested from from $peer_addr";
             $html="ERR:2";
         }
         unless ($html)
         {
            syslog "debug", "Non existing mapper $host requested from from $peer_addr";
            $html="ERR:3";
         }
         send(UDPH,$html,0,$sender);
         use warnings;
         use strict;
       }
  }
}

