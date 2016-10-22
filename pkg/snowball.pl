#!/usr/bin/perl
# Simple wrapper script that assures that a half crashed node does not
# contaminate the total systems high q.o.s. It makes hals crashes full crashes.
use POSIX ":sys_wait_h";

if ($pid = fork())
{
    print "Capibara snowball to background\n";
    exit;
}
@childs=("capdb","caphttp","capdns");
if ((defined $ARGV[0]) && ($ARGV[0] eq "nohttp"))
{
  @childs=("capdb","capdns");
}
foreach $child (@childs){
   
   $pid = fork();
   unless (defined($pid)) {
     print "ERR: Forking error\n";
     exit(0);
   }
   if ($pid==0)
   {
      exec("/usr/local/capibara/cduck/bin/${child}.pl nobg");
      exit;
   }
   else
   {
      $process{$pid}=$child;
   }
} 
$kid = waitpid(-1,0);
$process=$process{$kid};
foreach $pid (keys %process)
{
  unless ($pid==$kid)
  {
     kill 9,$pid;
  }
}
