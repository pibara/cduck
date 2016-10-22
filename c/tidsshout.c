#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include "breach.h"

int main (int argc, char **argv) {
  struct hostent *hp;
  struct sockaddr_in addr;
  struct sockaddr_in waddr;
  int sock;
  if(!(hp=gethostbyname(SERVER)))
  {
    return(0);
  }
  memset(&addr,0,sizeof(addr));
  addr.sin_addr=*(struct in_addr*) hp->h_addr_list[0];
  addr.sin_family=AF_INET;
  addr.sin_port=htons(SERVERPORT);
  if((sock=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP))<0)
  {
    return(0);
  } 
  sendto(sock,BREACH,strlen(BREACH),0,(struct sockaddr *)&addr,sizeof(addr));
}
