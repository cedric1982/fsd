#include <ctime>

#include "server.h"
#include <string>
#include <list>

#ifndef CLIENTHH
#define CLIENTHH

#define CLIENT_PILOT 1
#define CLIENT_ATC   2
#define CLIENT_ALL   3

class flightplan
{
   public:
   char *callsign;
   int revision;
   char type;
   char *aircraft;
   int tascruise;
   char *depairport;
   int deptime;
   int actdeptime;
   char *alt;
   char *destairport;
   int hrsenroute, minenroute;
   int hrsfuel, minfuel;
   char *altairport;
   char *remarks;
   char *route;
   flightplan(char *, char, char *, int, char *, int, int, char *, char *,
      int, int, int, int, char *, char *, char *);
   ~flightplan();
   
};
class client
{
   public:
   time_t starttime;
   flightplan *plan;
   int type, rating;
   unsigned int pbh;
   int flags;
   time_t alive;
   char *cid, *callsign, *protocol, *realname, *sector, *identflag;
   double lat,lon;
   int transponder, altitude, groundspeed, frequency, facilitytype;
   int positionok, visualrange, simtype;
   server *location;
   client *next, *prev;
   client(char *, server *, char *, int, int, char *, char *, int);
   ~client();
   void updatepilot(char **);
   void updateatc(char **);
   void handlefp(char **);
   void setalive();
   double distance(client *);
   int getrange();
   double prev_lat;
   double prev_lon;
   double heading;
   void updateHeading();
   std::list<std::string> infolines;
   bool fpModed = false;
};
extern client *rootclient;
client *getclient(char *);
#endif
