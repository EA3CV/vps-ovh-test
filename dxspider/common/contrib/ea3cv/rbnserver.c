/*
 RBN Filter / Server
 See http://fkurz.net/ham/stuff.html?rbnfilter
 By Fabian Kurz, DJ1YFK
 fabian@fkurz.net
 2012-10-22
 2012-12-10 (update)
 Modify by EA3CV
 ea3cv@cronux.net
 v4.1
 2020-01-24
  Code is in the public domain.
*/

#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <ctype.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <errno.h>


void prompt (char *usercall, char *argv[]);
void clean (char *text);
int iscall (char *call);

int main (int argc, char *argv[]) {
	int i, j, k;
	char command[80];
	char line[100];
	char usercall[80];
	char *root = "/home/sysop/spider/contrib/ea3cv";
	static char tmp[100];
	FILE *gw;
	FILE *fh;

	pid_t pid;

	if (argc==1) {
	       printf("rbnserver is a Gateway between a RBN server and a DXSpider server.\n\n"
		      "You must enter the parameters...\n"
                      "rbnserver 'Cluster Callsign' 'Cluster Prompt' 'RBN Server' 'RBN Port' 'RBN User Callsign'\n\n"
                      "Example:\n"
                      "rbnserver EA0XX-1 rbn-gw-spider telnet.reversebeacon.net 7000 EA0XYZ\n\n");

	       return 1;
	}

	printf("Welcome ...\r\n"
	       "%s %s\r\n\r\n"
	       "Please enter your callsign: ", argv[1], argv[2]);
	fflush(stdout);

	if ((fgets(usercall, 64, stdin) == NULL) &&(strlen(usercall) < 4) ) {
		printf("Error.\r\n"
		       "Please log in with a valid callsign. Bye.\r\n");
		exit(0);
	}
        else {
		/* Si your_call correcto enviamos PC18 */
                printf("PC18^DXSpider Version: 1.55 Build: 0.166 Git: 4868adf[i] pc9x^5455^\n");
                fflush(stdout);
        }

	clean(usercall);

	/* remove \r\n */
	for (i=0; i < strlen(usercall); i++) {
		usercall[i] = toupper(usercall[i]);
		if (isspace(usercall[i])) {
				usercall[i] = '\0';
		}
	}

	prompt(usercall, argv);

	pid = fork();

	/* Child process: rbnspots.pl */
	if (pid == 0) {
		char cmd_rbn[100];
		snprintf(cmd_rbn, sizeof(cmd_rbn), "%s/rbnspots.pl -s %s -p %s -u %s", root, argv[3], argv[4], argv[5]);
		gw = popen(cmd_rbn, "r");

		while (fgets(line, 80, gw)) {
			printf("%s", line);
			fflush(stdout);
		}
	}
	/* Parent process: Handle user input */
	else {
		fflush(stdin);
		while (fgets(command, 60, stdin)) {
			command[strlen(command)] = '\0';
			fflush(stdout);
			fflush(stdin); 
			if (strstr(command, "bye") == command) {
				printf("bye!\r\n");
				fflush(stdout);
				kill(pid , SIGKILL);
				exit(0);
			}
			else {
				/* PC51 */
                               	if (strstr(command, "PC51") == command) {
					char *pc51 = strtok(command, "^"); 
		                        char *my_call = strtok(NULL, "^");
               	                        char *your_call = strtok(NULL, "^");
                       	                char *flag = strtok(NULL, "^");
					/* Respondemos al PC51 ping */
                               	        printf("%s^%s^%s^0^\n", pc51, your_call, my_call);
                                        fflush(stdout);
				}
				else {
                                        /* si PC20 se envia PC22 */
       	                                if (strstr(command, "PC20") == command) {
                                                printf("PC22^\n");
						printf("###### %s Initialized protocol between clusters ######\n", argv[1]);
       	                                        fflush(stdout);
					}
				}
			}
/*		prompt(usercall, argv); */
		fflush(stdout);
		}
	}
}

void prompt (char *usercall, char *argv[]) {
	time_t t;
	struct tm *timestruct;
	char timestring[255];

	t = time(NULL);
	timestruct = gmtime(&t);
	strftime(timestring, sizeof(timestring), "%d-%b-%Y %H%M", gmtime(&t));
	printf("%s de %s %sZ %s >\r\n", usercall, argv[1], timestring, argv[2]);
}

int iscall (char *call) {
	return 1;
}

/* Remove telnet control sequences
 * Format: 0xFF 0x.. 0x.. */
void clean (char *txt) {
	int i,l;
	l = strlen(txt);
	for ( ; l ; l--) {
		if ((unsigned char) txt[l] == 0xFF) {
			break;
		}
	}

	if (l == 0) {
		return;
	}

	l += 2;

	for (i=0; i < strlen(txt)-l; i++) {
		txt[i] = txt[i+l];
	}
}
