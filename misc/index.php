<?php
##########################################
#     Capibara PHP-fe  0.9.6             #
#                                        #
# This script is the php replacement of  #
# the webserver part of the Capibara     #
# Distributed URL  cloaking server.      #
# It is meant to let CDUCK co-exist with #
# apache.                                #
# The index.cgi is more complete than the#
# php version, Only use the .php if      # 
# unable to use the .cgi                 #
#                                        #
##########################################
function htmlcode ($head,$content) {
  #Please change this folowing line
  $rp="defaultconfig@defaultconfig.net";
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
$starttime=time();
$fp = fsockopen("udp://127.0.0.1", 9595, $errno, $errstr);
if (!$fp) {
    $buf=htmlcode("Database error", "Type 0");
} else {
    $host = getenv ("HTTP_HOST");
    
    $host=eregi_replace(":.*","",$host);
    $host=eregi_replace("www\.","",$host);
    fwrite($fp,"$host");
    socket_set_blocking($fp,FALSE);
    $time=time() - $starttime;
    while ((!$buf) AND ($time < 20))
    {
      $buf=fread($fp,2096);
    }
    if (!$buf)
    {
      $buf=htmlcode("Database timeout","Connection to database timed out");
    }
    else
    {
      if(preg_match("/^ERR:1/", $buf))
        {$buf=htmlcode("Database Error","Type 4");}
      if(preg_match("/^ERR:2/", $buf))
        {$buf=htmlcode("Banned","The requested url mapper has been banned dueue to abusive behaviour");}
      if(preg_match("/^ERR:3/", $buf))
        {$buf=htmlcode("Not in database","The requested domain ($host) was not found in the cduck datbas");}
    }
}
echo "$buf\n";
?>


