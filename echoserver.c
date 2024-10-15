#!/usr/local/bin/tcc -run 
#include <stdio.h>        /* printf() */
#include <unistd.h>       /* read(), write() */
#include <strings.h>      /* bzero(), */
#include <stdlib.h>       /* atoi() */
#include <sys/types.h>    /* accept(), connect() */
#include <sys/socket.h>   /* socket(), struct sockaddr_in, etc*/
#include <sys/errno.h>    /* perror() */
#include <netinet/in.h>   /* htonl() */


// output error messages and exit.
void error(char *errormsg) {
  perror(errormsg);
  exit(1);
}

// main
int main(int argc, char *argv[])
{
  int socketfd;             /* socket file descriptor */
  int connfd;               /* connection file descriptor */  
  int portno;
  socklen_t clientlen;
  char buffer[256];
  struct sockaddr_in serv_addr, cli_addr;
  int n;
  char usage[] = "./servertcp portno\0";


  // check command args 
  if (argc < 2) { 
    printf ("%s\n", usage);
    return 0;
  }
  // create a listening socket 
  socketfd = socket(PF_INET, SOCK_STREAM, 0);
  if (socketfd < 0) 
    error("ERROR opening socket");

  // specify local address 
  bzero((char *) &serv_addr, sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  serv_addr.sin_addr.s_addr = htonl(INADDR_ANY); 
  portno = atoi(argv[1]);
  serv_addr.sin_port = htons(portno);

  // bind the address to the listening socket 
  if (bind(socketfd, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) 
    error("ERROR on binding");

  // specify a queue length for the server 
  listen(socketfd, 2);

  // accept connections
  clientlen = sizeof(cli_addr);
  connfd = accept(socketfd, (struct sockaddr *) &cli_addr, &clientlen);
  if (connfd < 0) 
    error("ERROR on accept");

  // start to receive data
  bzero(buffer, 256);
  n = read(connfd, buffer, sizeof(buffer)-1);
  if (n < 0) 
    error("ERROR reading from socket");
  printf("Here is the message: %s\n", buffer);
  fflush(stdout);

  // start to reply to client
  n = write(connfd, "I got your message", 18);
  if (n < 0) 
    error("ERROR writing to socket");

  return 0; 
}