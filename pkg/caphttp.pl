#!/usr/bin/perl
#
##########################################
#     Capibara HTTP  0.9.6		 # 
#                                        #
# This server is the beta version of the #
# Webserver part of the distributed      #
# cloaking server.                       #
#                                        #
##########################################
use Socket;
use English;
use POSIX ":sys_wait_h";
use Sys::Syslog qw( :DEFAULT setlogsock);
use strict;
use warnings;
#use Fcntl 'F_DUPFD';
our $childs;
our $rp="";

sub htmlcode {
 my ($head,$content)=@_;
 return "<HTML><HEAD><TITLE>$head</TITLE></HEAD>
<BODY bgcolor=\"#ffffff\">
<CENTER>
<A HREF=\"http://cduck.sourceforge.net/\">
<IMG border=0 SRC=\"http://www.xs4all.nl/~rmeijer/cduck.gif\"></A>
<br>
<H1>$head</H1>$content<br><hr><A HREF=\"mailto:$rp\">node admin</A>.
</CENTER></HTML>
";
}

sub childhnd {
  my $kid;
  do {
     $kid = waitpid(-1,&WNOHANG);
     if($kid > 0)
     {
       $childs--;
     }
  } until $kid == -1;
  return;
}
sub timeout {
  exit(0);
}
$|=1;
my $software="CapHTTP";
my $version="0.9.6";
my $BASEDIR="/usr/local/capibara/cduck/";
# MAIN

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
my($PS)=$BINPATH{"ps"};

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

if (open(PID,"${BASEDIR}tmp2/caphttp.pid"))
{
  syslog "debug", "PID file found\n";
  my $opid=<PID>;
  chomp($opid);
  close(PID);
  unless ($opid =~ /^\d+$/)
  {
    syslog "crit", "HEY, SOMEONE FUCKED UP MY PIDFILE ${BASEDIR}tmp2/caphttp.pid";
    print  "FAIL: HEY, SOMEONE FUCKED UP MY PIDFILE ${BASEDIR}tmp2/caphttp.pid";
    exit;
  }
  syslog "debug", "Checking for process with pid $opid";
  open(PS,"$PS -p $opid|");
  my $killit=0;
  while (<PS>)
  {
     if (/caphttp/)
     {
       $killit=1;
     }
  }
  close(PS);
  if ($killit)
  {
    syslog "debug", "Killing old instance";
    kill(9,$opid);
    sleep(3);
  }
  else
  {
    syslog "debug", "pid file apears to be old";    
  }
}
unless (open(MYIP,"${BASEDIR}etc/cduck_node.conf"))
{
   syslog "crit", "Cant open ${BASEDIR}etc/cduck_node.conf";
   print "FAIL: Cant open ${BASEDIR}etc/cduck_node.conf\n";
   exit;
}
my $defaultip="";
while (<MYIP>)
{
  chomp();
  if (/^bindip\s+(\d+\.\d+\.\d+\.\d+)/)
  {
    $defaultip=$1;
  }
  if (/^rp\s+(\S+)/)
  {
    $rp=$1;
    $rp =~ s/\./\@/;
  }
}
close(MYIP);
#chomp($defaultip);
unless ($defaultip =~ /^\d+\.\d+\.\d+\.\d+$/)
{
  syslog "crit", "No valid bind IP adress in ${BASEDIR}etc/cduck_node.conf";
  print "No valid bind IP adress in ${BASEDIR}etc/cduck_node.conf\n";
  exit;
} 
my ($pnam,$myuid,$mygid);
($pnam,undef,$myuid,$mygid)=getpwnam("caphttp");
unless ($pnam)
{
    syslog "crit", "User caphttp not defined, exiting";
    print "FAIL : User caphttp not defined, exiting\n";
    exit;
}
if ($< != 0)
{
  syslog "crit", "Need to be root to bind to the http port\n";
  print  "FAIL: Need to be root to bind to the http port\n";
  exit(0);
}

my $port=80;
my $proto=getprotobyname('tcp');
unless (socket(Server,PF_INET,SOCK_STREAM,$proto))
{
  syslog "crit", "Problem creating socket : $!";
  print "FAIL Problem creating socket : $!";
  exit;
}
unless (setsockopt(Server,SOL_SOCKET,SO_REUSEADDR,pack("l",1)))
{
  syslog "crit", "Problem setting socket options: $!";
  print "FAIL Problem setting socket options: $!";
  exit;
}
unless (bind(Server,sockaddr_in($port,inet_aton($defaultip))))
{
  syslog "crit", "Problem binding tcp socket : $!";
  print "FAIL Problem binding tcp socket : $!";
  exit;
}
unless (listen(Server,SOMAXCONN))
{
  syslog "crit", "Problem with listen call : $!";
  print "FAIL Problem with listen call : $!";
  exit;
}
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
{
  my $pid;
  unless (defined($ARGV[0]) && ($ARGV[0] eq "nobg"))
  {
  if ($pid = fork())
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
  open(PIDFIL,">${BASEDIR}tmp2/caphttp.pid");
  print PIDFIL "$$\n";
  close(PIDFIL);
}
$childs=0;
my $rcount=0;
$SIG{'CHLD'}='childhnd';
my $paddr;
my $html="";
my $headonly=0;
my $cl="";
while($paddr = accept(Client,Server))
{
   my ($remoteport,$remoteip)=sockaddr_in($paddr);
   $remoteip=unpack("L",$remoteip);
   #Limmited forking and extra sleeping, better for the service than the system to be dossed
   if ($childs < 20)
   {
   $rcount++;
   my $pid=fork();
   unless (defined($pid)) {
     print "ERR: Forking error\n";
     exit(0);
   }
   if ($pid==0)
   {
     select Client;$|=1;select(STDOUT);
     $SIG{"ALRM"}='timeout';
     alarm(20);
     my $cline="zzzz";
     my $host="";
     $headonly=0;
     while($cline)
     {
       $cline=<Client>;
       if (defined($cline))
       {
         if ($cline =~ /^Host:\s*(\S+)/i)
         {
           $host=$1;
         }
         if ($cline =~ /^HEAD\s/i)
         {
           $headonly=1;
         }
         $cline =~ s/\r//g;
         chomp($cline);
       }
     }
     
     if ($host)
     {
       $host=lc($host);
       $host =~ s/^www\.//;
       # Need to create a udp socket here and do the query       

       my $sport=9595;
       my $udp=getprotobyname('udp');
       unless (socket(UDPH, PF_INET, SOCK_DGRAM, $udp))
       {
           syslog "crit", "$software $version : Unable to create udp socket";
           print "FAIL: $software $version : Unable to create udp socket";
           $html=&htmlcode("Database Error","type 0");
       }  
       $|=1;
       my $destpaddr=sockaddr_in($sport,INADDR_LOOPBACK);
       unless (send(UDPH,$host,0,$destpaddr))
       {
           syslog "crit", "$software $version : Unable to send using udp socket";
           print "FAIL: $software $version : Unable to send using udp socket";
           $html=&htmlcode("Database Error","type 1");
       }
       unless ($html)
       {
         my $sender=recv(UDPH,$html,4096,0);
         if ($sender)
         {
           my ($rport2, $raddr2) = sockaddr_in($sender);
           my $peer_addr2 = inet_ntoa($raddr2); 
           unless ($peer_addr2 eq "127.0.0.1")
           {
             syslog "crit", "$software $version : Hmm, strange response from $peer_addr2";
             print "FAIL: $software $version : Hmm, strange response from $peer_addr2\n";
             $html=&htmlcode("Database Error","type 2");
           }
         }
         else
         {
             syslog "crit", "$software $version : Database error : Hmm, strange error on recv, possibly database server down";
             print "FAIL: $software $version : Database error : Hmm, strange error on recv, possibly database sever down\n";
             $html=&htmlcode("Database Error","type 3");
         }
       }
       #Chech the response
       if ($html =~ /^ERR:(\d+)/)
       {
           if ($1 == 1) { 
             $html=&htmlcode("Database Error","type 4");
           }
           if ($1 == 2) {$html=&htmlcode("Banned","The requested url mapper has been banned dueue to abusive behaviour");}
           if ($1 == 3) {$html=&htmlcode("Not in database","The requested domain ($host) was not found in the cduck datbase");}
       }
       unless ($html)
       {
         $html="FIXME";
       }
       $cl=length($html);
       print Client "HTTP/1.1 200 OK\n";
       print Client "Server: $software $version\n";
       print Client "Content-Length: $cl\n";
       print Client "Connection: close\n";
       print Client "Content-Type: text/html\n\n";
       unless ($headonly)
       {
         print Client "$html\n";
       }
     }
     else
     {
        $html=&htmlcode("Browser problem","Your browser did not send a HTTP/1.1 compliant query");
        $cl=length($html);
        print Client "HTTP/1.1 418 BROWSERFAIL\n";
        print Client "Server: $software $version\n";
        print Client "Content-Length: $cl\n";
        print Client "Connection: close\n";
        print Client "Content-Type: text/html\n\n";
        unless ($headonly)
        {
          print Client "$html";
        }
     }
     close(Client);
     exit(0);
   }
   else
   {
     $childs++;
   }
   }
   else
   {
     $html="The Server is having some load problems, maximum amounth of concurent processes reached, please come back later\n";
     $cl=length($html);
     print Client "HTTP/1.1 501 LOADPROBLEM\n";
     print Client "Server: $software $version\n";
     print Client "Content-Length: $cl\n";
     print Client "Connection: close\n";
     print Client "Content-Type: text/html\n\n";
     unless ($headonly)
     {
       print Client "$html";
     }
     close(Client);
   } 
}

