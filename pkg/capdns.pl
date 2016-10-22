#!/usr/bin/perl
#
##########################################
#     Capibara DNS 0.9.6		 # 
#                                        #
# This server is the beta version of the #
# DNS part of the distributed cloaking   #
# server.                                #
#                                        #
##########################################
use Socket;
use English;
use Sys::Syslog qw( :DEFAULT setlogsock);
use strict;
use warnings;
#use Fcntl 'F_DUPFD';
$|=1;
my $software="CapiDNS";
my $version="0.9.6";
our @mytopdomains=();
our $servername="";
our %ZONE=();
our %ISTOPDOMAIN=();
our $defaultip;
our $res_pers;
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
my $PS=$BINPATH{"ps"};

sub readzones {
  @mytopdomains=();
  unless (open(ZONEINDEX,"${BASEDIR}db/zoneindex.txt"))
  {
    #Could be race condition, lets wait and try again
    sleep(2);
    unless (open(ZONEINDEX,"${BASEDIR}db/zoneindex.txt"))
    {
       syslog "crit", "Cant open ${BASEDIR}db/zoneindex.txt";
       print "FAIL: Cant open ${BASEDIR}db/zoneindex.txt $! $?\n";
       exit;
    }
  }
  while(<ZONEINDEX>)
  {
    chomp();
    chomp();
    if ($_)
    {
      push(@mytopdomains,$_);
      $servername="ns.$_";
      $ISTOPDOMAIN{$_}=1;
    }
  }
  close(ZONEINDEX);
  unless (open(ZONES,"${BASEDIR}db/zones.txt"))
  {
    #Could be race condition, lets wait and try again
    sleep(2);
    unless (open(ZONES,"${BASEDIR}db/zones.txt"))
    {
      syslog "crit", "Cant open ${BASEDIR}db/zones.txt";
      print "FAIL: Cant open ${BASEDIR}db/zones.txt\n";
      exit;
    }
 }
 while(<ZONES>)
 {
  chomp();
  my @parts=split(/\s+/,$_);
  {
  if ($parts[2])
  {
    my @otherparts=@parts;
    shift(@otherparts);
    shift(@otherparts);
    if ($parts[1] eq "NS")
    {
      {
      my $num;
      foreach $num (0 .. $#otherparts)
      {
        unless ($otherparts[$num] =~ /^\d+\.\d+\.\d+\.\d+$/)
        {
          $ZONE{"A:$otherparts[$num]"} = $otherparts[$num+1];
        }
      }
      }
      $ZONE{"NS:$parts[0]"}=join(" ",@otherparts);     
    }
    elsif ($parts[1] eq "A")
    {
      $ZONE{"A:$parts[0]"}=join(" ",@otherparts);     
    }
    elsif ($parts[1] eq "MX")
    {
      $ZONE{"MX:$parts[0]"}=join(" ",@otherparts);     
    }
  }
  }
 }
 close(ZONES);
}
sub refresh {
  syslog "debug", "Refreshing zone hash";
  %ZONE=();
  &readzones();
  $SIG{"HUP"}=\&refresh;
}
sub getnsrec {
  my ($name)=@_;
  while ($name =~ /\./)
  {
     if ($ZONE{"NS:$name"})
     {
        return ($ZONE{"NS:$name"}, $name);
     }
     $name =~ s/^[^\.]*\.//;
  }
  return ("","");
}
sub mytopzone {
  my ($name)=@_;
  while ($name =~ /\./)
  {
     if ($ISTOPDOMAIN{"$name"})
     {
        return ($name);
     }
     $name =~ s/^[^\.]*\.//;
  }
  return "";
}

sub getmxrec {
  my ($name)=@_;
  return ($ZONE{"MX:$name"});
}

sub nametoip {
  my ($name)=@_;
  my (@parts,$part,@parts2,$found,$index,$nsrec,$nsdrec);
  $found=0;
  {
  my $mytopdomain;
  foreach $mytopdomain (@mytopdomains)
  {
    if ($name =~ /(.*)\.$mytopdomain/)
    {
              $nsdrec=$ZONE{"NS:$mytopdomain"};
              my ($nsrec,$auth)=getnsrec($name);
              if ($nsrec eq $nsdrec)
              {
                if ($ZONE{"A:$name"})
                {
                  return $ZONE{"A:$name"}
                }
                else
                {
                  return $defaultip;
                }
              }
              else
              {
                return ("N:$nsrec",$auth);
              }
    } 
    elsif ($name eq $mytopdomain)
    {
       return $defaultip;
    }
  }
  }
  return "E";
}

sub unpackname {
  my ($packedname)=@_;
  my ($index,$lastindex,$len,@packedname);
  @packedname=split(//,$packedname);
  $len=length($packedname);
  $index=0;
  while(($index < $len))
  {
     $lastindex=$index;
     $index+=1+ord($packedname[$index]);
     $packedname[$lastindex]=".";
  }
  shift(@packedname);
  $packedname=join('',@packedname);
  return lc($packedname);
}

sub packname {
  my ($unpackedname)=@_;
  my(@unpackedname,$count,$kar,$packedname);
  $packedname="";
  if ($unpackedname =~ /(.*)\.+$/) {$unpackedname=$1;}
  @unpackedname=split(/\./,$unpackedname);
  {
    my $part;
    foreach $part (@unpackedname)
    {
      $packedname .= pack("C",length($part)) . $part;
    }
  }
  $packedname .= pack("C",0);
}
# MAIN
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

unless (open(MYIP,"${BASEDIR}etc/cduck_node.conf"))
{
   syslog "crit", "Cant open ${BASEDIR}etc/cduck_node.conf";
   print "FAIL: Cant open ${BASEDIR}etc/cduck_node.conf\n";
   exit;
}
my $bindip;
while (<MYIP>)
{
  chomp();
  if (/^bindip\t+(\d+\.\d+\.\d+\.\d+)$/) {$bindip=$1;}
  if (/^extip\t+(\d+\.\d+\.\d+\.\d+)$/) {$defaultip=$1;}
  if (/^rp\s+([a-z0-9A-Z\._-]+)$/) {$res_pers=$1;}
}
close(MYIP);
unless ($defaultip =~ /^\d+\.\d+\.\d+\.\d+$/)
{
  syslog "crit", "No valid ext IP adress in ${BASEDIR}etc/cduck_node.conf";
  print "No valid ext IP adress in ${BASEDIR}etc/cduck_node.conf\n";
  exit;
}
unless ($bindip =~ /^\d+\.\d+\.\d+\.\d+$/)
{
  syslog "crit", "No valid bind IP adress in ${BASEDIR}etc/cduck_node.conf";
  print "No valid bind IP adress in ${BASEDIR}etc/cduck_node.conf\n";
  exit;
}
unless ($res_pers)
{
  syslog "crit", "No valid RP adress in ${BASEDIR}etc/cduck_node.conf";
  print "No valid RP adress in ${BASEDIR}etc/cduck_node.conf\n";
  exit;
}

if (open(PID,"${BASEDIR}tmp/capdns.pid"))
{
  syslog "debug", "PID file found\n";
  my $opid=<PID>;
  chomp($opid);
  close(PID);
  unless ($opid =~ /^\d+$/)
  {
    syslog "crit", "HEY, SOMEONE FUCKED UP MY PIDFILE ${BASEDIR}tmp/capdns.pid";
    print  "FAIL: HEY, SOMEONE FUCKED UP MY PIDFILE ${BASEDIR}tmp/capdns.pid";
    exit;
  }
  syslog "debug", "Checking for process with pid $opid";
  open(PS,"$PS -p $opid|");
  my $killit=0;
  while (<PS>)
  {
     if (/capdns/)
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
my ($pnam,$myuid,$mygid);
($pnam,undef,$myuid,$mygid)=getpwnam("capdns");
unless ($pnam)
{
  syslog "crit", "No user capdns defined, exiting";
  print  "FAIL: No user capdns defined, exiting";
  exit;
}
if ($>!=0)
{
  syslog "crit", "$software $version : I need to be started as root.";
  print  "FAIL: $software $version : I need to be started as root.";
  exit; 
} 
my $port=53;
my $udp=getprotobyname('udp');
unless (socket(UDPH, PF_INET, SOCK_DGRAM, $udp))
{
           syslog "crit", "$software $version : Unable to create udp socket";
           print  "FAIL: $software $version : Unable to create udp socket";
	   exit;
}  
#unless (setsockopt(UDPH, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)))
#{
#           syslog "crit", "$software $version : Unable to set reuse option on socket";
#           print "FAIL: $software $version : Unable to set reuse option on socket";
#	   exit;         
#}
unless (bind(UDPH, sockaddr_in($port, inet_aton($bindip))))
{
           syslog "crit", "$software $version : Unable to bind to socket";
           print  "FAIL: $software $version : Unable to bind to socket";
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
&readzones();
my $pid;
unless ((defined $ARGV[0]) && ($ARGV[0] eq "nobg"))
{
if ($pid = fork)
{
  print "$software $version started\n";
  exit;
}
unless (defined $pid)
{
  print "$software $version FORK ERROR\n";
  exit;
}
}
my @oldstat=stat("${BASEDIR}db/zones.txt");
open(PIDFIL,">${BASEDIR}tmp/capdns.pid");
print PIDFIL "$$\n";
close(PIDFIL);
$SIG{"HUP"}=\&refresh;
while(1)
{
  my $data;
  my $sender=recv(UDPH,$data,1024,0);
  if ($sender && $data)
  {
            my ($rport, $raddr) = sockaddr_in($sender);
            my $peer_addr = inet_ntoa($raddr); 
            my $question=$data;
            my @dnsheader=unpack("nCCnnnn",$data);
            my $qr=int($dnsheader[1]/128);
            my $oc=int(($dnsheader[1]%128)/8);
            my $rd=($dnsheader[1]%2);
            my $qdcount=$dnsheader[3];  
            my $ancount=$dnsheader[4];  
            my $nscount=$dnsheader[5];  
            my $arcount=$dnsheader[6];
            my @newstat=stat("${BASEDIR}db/zones.txt");
            if ($newstat[9] != $oldstat[9])
            {
               syslog "debug", "dns zonefile has chaned, updating";
               %ZONE=();
	       &readzones();
               @oldstat=@newstat;
            }
            if (($qr ==0)&&($oc==0)&&($qdcount==1)&&($ancount==0))
            {
		(undef,undef,undef,undef,undef,undef,undef,undef,undef,undef,undef,undef,$question)=split(//,$question,13); 
		$question=~s/\x00/a4aIkn0/;
		my ($dnsname,$dnsrest)=split(/a4aIkn0/,$question); 
		my ($qtype,$class)=unpack("nn",$dnsrest);
                $question= $dnsname . pack("cnn",0,$qtype,$class);
                 if ($class == 1) #A
                 {
                    $dnsname=&unpackname($dnsname);
                    if ($qtype==1)
                    {
                        my ($ph,$rdat);
			syslog "debug", "A request for $dnsname ($peer_addr)";
                        my ($r1,$auth)=&nametoip($dnsname);
                        if ($r1 =~ /^N(.*)/)
                        {
                          my %NSRS=split(/\s+/,$1);
                          my $rdatns="";
                          my $rdatad="";
                          my $nscount=0;
                          {
                          my $key;
                          foreach $key (keys %NSRS)
                          {
                            my $val=$NSRS{$key};
                            if ($val =~ /^\d+\.\d+\.\d+\.\d+$/)
                            {
                             $nscount++;
			     my $pname=packname($key);
                             $rdatns .= &packname($auth) . pack("nnNn",2,1,60,length($pname)) . $pname;
                             $rdatad .= $pname . pack("nnNn",1,1,60,4) .inet_aton($val);
                            }
                          }
                          }
			  $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,0,1,0,$nscount,$nscount);
                          $rdat=$rdatns . $rdatad;
                        }
                        elsif ($r1 eq "E")
                        {
			  $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,3,1,0,0,0);
			  $rdat="";
                        }
                        else
                        {
			  $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,0,1,1,0,0);
			  $rdat=pack("nnnNn",49164,$qtype,1,60,4) .inet_aton(nametoip($dnsname));
                        }
		        my $response=$ph . $question . $rdat;
			send(UDPH,$response,0,$sender);	
                    }
                    elsif ($qtype == 12) #PTR
                    {
		        #If we get these reqests, they are likely to
                        #be a request for 'our' name, so we can now
                        #shortcut it to a standard response.
                        my ($ph,$rdat);
			syslog "debug", "PTR request for $dnsname ($peer_addr)\n";
		        my $tname;
                        if ($dnsname =~ /(.*)\.in-addr\.arpa/i)
                        {
                          # $tname="host-".join('.',reverse(split(/\./,$1))).".$mytopdomain";
                          $tname=$servername;
                        }
			$ph=pack("nCCnnnn",$dnsheader[0],132+$rd,0,1,1,0,0);
			my $pname=packname($tname);
			$rdat=pack("nnnNn",49164,$qtype,1,21600,length($pname));
		        my $response=$ph . $question . $rdat . $pname;
			send(UDPH,$response,0,$sender);		
                    }
                    elsif ($qtype==2) #NS
                    {
                      my ($ph,$rdat);
                      #$name=&unpackname($dnsname);
                      my $name=$dnsname;
                      my ($nsrec,$auth)=getnsrec($name);
                      syslog "debug", "NS req for $name ($nsrec -> $auth) ($peer_addr)\n";
                      unless ($nsrec)
                      {
			$ph=pack("nCCnnnn",$dnsheader[0],132+$rd,3,1,0,0,0);
                        $rdat=""
                      }
                      else
                      {
                        my %NSRS=split(/\s+/,$nsrec);
                        my $rdatns="";
                        my $rdatad="";
                        my $nscount=0;
                        {
                        my $key;
                        foreach $key (keys %NSRS)
                        {
                            my $val=$NSRS{$key};
                            if ($val =~ /^\d+\.\d+\.\d+\.\d+$/)
                            {
                             $nscount++;
			     # my $pname=packname($key);
                             my $pname=  packname($key . "." . &mytopzone($dnsname));
                             $rdatns .=&packname($auth) . pack("nnNn",2,1,60*60*24*2,length($pname)) . $pname;
                             $rdatad .= $pname . pack("nnNn",1,1,60*60*24*2,4) .inet_aton($val);
                            }
                        }
                        }
		        $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,0,1,$nscount,0,$nscount);
                        $rdat=$rdatns . $rdatad;
                      }
 		      my $response=$ph . $question . $rdat;
		      send(UDPH,$response,0,$sender);
                    }
                    elsif ($qtype==6) #SOA
                    {
                       my ($ph,$rdat);
                       my $name=$dnsname;
		       syslog "debug", "SOA request for $dnsname ($peer_addr)\n";
                       if ($ISTOPDOMAIN{$name})
                       {
			  my $rdatsoa=packname("ns.$name") . packname("$res_pers") . pack("NNNNN",$^T/256,60,60,300,60);
                          $rdat = &packname($name) . pack("nnNn",6,1,60*60*24,length($rdatsoa)) . $rdatsoa;
                          $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,0,1,1,0,0); 
                       }
                       else
                       {
  			  $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,3,1,0,0,0);
                          $rdat=""
                       }
                       my $response=$ph.$question.$rdat;
		       send(UDPH,$response,0,$sender);
                    }
                    elsif ($qtype==15) #MX
                    {
                        my ($ph,$rdat);
                        my $nscount=0;
                        my $name=$dnsname;
                        syslog "debug", "MX request for $dnsname ($peer_addr)\n";
                        my ($mxrec)=getmxrec($name);
                        unless($mxrec)
                        {
  			  $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,3,1,0,0,0);
                          $rdat=""
                        }
                        else
                        {
                          my @MXRS=split(/\s+/,$mxrec);
                          my (%MXPREF,$name,$ip,$pref);
                          my $rdatmx="";
                          my $rdatad="";
			  while (($name=shift(@MXRS)) && ($ip=shift(@MXRS))) {
                             if ($ip =~ /^\d+\.\d+\.\d+\.\d+$/)
                             { 
                               $pref+=10;
            		       $nscount++;
                               #crude patch for external MX needs
			       # if name has more than two tokens we
                               # asume it to be external
			       my $pname= "";
                               if ($name =~ /\..*\./)
                               {
                                 $pname= packname($name);
                               }
			       else
                               {
                                 $pname= packname($name . "." . &mytopzone($dnsname));
                               }
  			       my $ppref= pack("n",$pref); 
                               $rdatad .= $pname . pack("nnNn",1,1,60*60*24*2,4) .inet_aton($ip);
                               $rdatmx .=&packname($dnsname) . pack("nnNn",15,1,60*60*24*2,length($pname)+2) . $ppref . $pname;
                             }
                          }
  		          $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,0,1,$nscount,0,$nscount);
                          $rdat=$rdatmx . $rdatad;
                        }
			# $ph=pack("nCCnnnn",$dnsheader[0],132+$rd,3,1,0,0,0);
			my $response=$ph.$question.$rdat;
			send(UDPH,$response,0,$sender);
                    }
                    else
                    {
                        my ($ph,$rdat);
                        syslog "debug", "TYPE $qtype not supported for $dnsname ($peer_addr)";
			$ph=pack("nCCnnnn",$dnsheader[0],132+$rd,4,1,0,0,0);
			my $response=$ph.$question;
			send(UDPH,$response,0,$sender);		
                    }
                 }
                 else
                 {
                    syslog "debug", "Class $class not supported ($peer_addr)";
                 }
	    }
            else
            {
               syslog "debug", "Invalid request $peer_addr $rport qr=$qr oc=$oc rd=$rd";
               syslog "debug", "qc $qdcount an $ancount ns $nscount ar $arcount\n";
            }
  }
}

