#!/usr/bin/perl
#
##########################################
#     Capibara CGI  0.9.6		 # 
#                                        #
# This script is the cgi replacement of  #
# the webserver part of the Capibara     #
# Distributed URL  cloaking server.      #
# It is meant to let CDUCK co-exist with #
# apache.                                #
#                                        #
##########################################
use Socket;
use English;
use strict;
use warnings;
our $rp="changethis\@yourdomain.com";
my $html;
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
sub timeout {
  $html=&htmlcode("Database timeout","Connection to database timed out");
  print "$html";
  exit(0);
}
$|=1;
print "Content-type: text/html\n\n";
$SIG{"ALRM"}='timeout';
alarm(20);
my $host=$ENV{"HTTP_HOST"};
$host =~ s/:.*//;
if ($host)
{
       $host=lc($host);
       $host =~ s/^www\.//;
       my $sport=9595;
       my $udp=getprotobyname('udp');
       unless (socket(UDPH, PF_INET, SOCK_DGRAM, $udp))
       {
           $html=&htmlcode("Database Error","type 0");
       }  
       $|=1;
       my $destpaddr=sockaddr_in($sport,INADDR_LOOPBACK);
       unless (send(UDPH,$host,0,$destpaddr))
       {
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
             $html=&htmlcode("Database Error","type 2");
           }
         }
         else
         {
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
#      my $key;
#      foreach $key (keys %ENV) {$html .= "$key : $ENV{$key} \n";}
#      print "$html : $host\n";
       print "$html\n";
}
else
{
        $html=&htmlcode("Browser problem","Your browser did not send a HTTP/1.1 compliant query");
        print "$html";
}
