#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <cstdint>
#ifndef WIN32
	#include <unistd.h>
#endif
#include <sys/stat.h>
#include "client.h"
#include "fsd.h"
#include "manage.h"
#include "support.h"
#include "global.h"
#include "server.h"
#include "mm.h"
#include "config.h"
#include "protocol.h"
#include <jsoncpp/json/json.h>
#include <fstream>
#include <unistd.h>
#include <filesystem>
#include <limits.h>
#include <stdexcept>
#include <GeographicLib/MagneticModel.hpp>
#include <cmath>
#include <chrono>


clinterface *clientinterface=NULL;
servinterface *serverinterface=NULL;
sysinterface *systeminterface=NULL;
configmanager *configman=NULL;

namespace fs = std::filesystem;

// File-scope: wird einmal im Konstruktor gesetzt und dann z.B. in writestatus() verwendet
static fs::path g_log_dir;

// --- Heading ("wie im Simulator") ---
// Simulator/Kompass arbeitet praktisch immer magnetisch.
// Daher: hdg_sim = dekodiertes PBH-Heading – ohne zusätzliche WMM-Korrektur.
j["pbh"] = (Json::UInt64)c->pbh;
const double hdg_sim = heading_from_pbh((uint32_t)c->pbh);
j["hdg_sim"] = hdg_sim;

// Track (Kurs über Grund) aus Positionsänderung – hilfreich zum Debuggen
if (c->computed_hdg >= 0)
    j["track_deg"] = c->computed_hdg;

// --- WMM / Missweisung (nur Diagnose & optional True) ---
double decl = 0.0;
bool wmm_ok = false;
try {
    const double alt_m = (double)c->altitude * 0.3048;
    decl = declination_deg(c->lat, c->lon, alt_m);
    wmm_ok = declination_is_plausible(decl);
} catch (...) {
    wmm_ok = false; // Wenn Missweisung fehlschlägt, auf false setzen
}

j["wmm_ok"] = wmm_ok;
if (wmm_ok) {
    j["decl_deg"] = decl;  // Missweisung ausgeben
    // true = magnetic + decl (east-positive)
    j["hdg_true"] = wrap360(hdg_sim + decl);  // True Heading nur, wenn WMM valide
} else {
    j["decl_deg"] = Json::nullValue;  // Wenn WMM fehlschlägt, null setzen
    j["hdg_true"] = Json::nullValue;  // True Heading nur bei validem WMM
}


static inline double wrap360(double x)
{
    while (x < 0.0) x += 360.0;
    while (x >= 360.0) x -= 360.0;
    return x;
}


static inline double current_decimal_year()
{
    using namespace std::chrono;
    const auto now = system_clock::now();
    std::time_t t = system_clock::to_time_t(now);
    std::tm gmt{};
    gmtime_r(&t, &gmt);

    // grob-gut: Dezimaljahr aus (Year + DayOfYear/365.25)
    const int year = gmt.tm_year + 1900;
    const int yday = gmt.tm_yday; // 0..365
    return year + (yday / 365.25);
}


static double declination_deg(double lat, double lon, double alt_m)
{
    static GeographicLib::MagneticModel model("wmm2020"); // falls nötig: wmm2025
    const double t = current_decimal_year();

    double Bx, By, Bz;
    model(t, lat, lon, alt_m, Bx, By, Bz);

    const double pi = std::acos(-1.0);
    return std::atan2(By, Bx) * 180.0 / pi;
}



static fs::path getExecutableDir()
{
#ifndef WIN32
    char buf[PATH_MAX];
    ssize_t len = ::readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (len <= 0) {
        throw std::runtime_error("readlink(/proc/self/exe) failed");
    }
    buf[len] = '\0';
    return fs::path(buf).parent_path(); // .../bin
#else
    // Falls du später Windows willst, müsste hier eine Windows-Implementierung rein.
    return fs::current_path();
#endif
}

static fs::path getBaseDir()
{
    // Annahme Layout: <base>/bin/fsd  -> base = <base>
    return getExecutableDir().parent_path();
}

static void ensureDir(const fs::path& p)
{
    std::error_code ec;
    fs::create_directories(p, ec);
    if (ec) {
        throw std::runtime_error("create_directories failed for " + p.string() + ": " + ec.message());
    }
}



fsd::fsd(char *configfile)
{
   certfile=NULL;
   whazzupfile=NULL;
   dolog(L_INFO,"Booting server");
   pmanager=new pman;

   /* Start the information manager */
   manager=new manage();
   
   configman=new configmanager(configfile);
   pmanager->registerprocess(configman);

   // Logs relativ zum Installationsort ermitteln und sicherstellen, dass das Verzeichnis existiert
	fs::path baseDir = getBaseDir();        // z.B. /opt/fsd
	g_log_dir = baseDir / "logs";           // z.B. /opt/fsd/logs
	ensureDir(g_log_dir);

	// Datei initial leeren/anlegen
	std::ofstream((g_log_dir / "fsd_output.log").string(), std::ios::trunc);

	
   /* Create the METAR manager */
   metarmanager=new mm;
   pmanager->registerprocess(metarmanager);

   /* Read the system configuration */
   configure();

   /* Create the management variables */
   createmanagevars();

   /* Create the server and the client interfaces */
   createinterfaces();

   /* Connect to the other server */
   makeconnections();

   dolog(L_INFO,"We are up");
   prevnotify=prevlagcheck=timer=mtime();

   prevwhazzup=mtime();
   fileopen=0;
}
fsd::~fsd()
{
   sqlite3_close(certdb);
   delete clientinterface;
   delete serverinterface;
   delete systeminterface;
   delete metarmanager;
   delete manager;
}

/* Here we do timeout checks. This function is triggered every second to
   reduce the load on the server */
void fsd::dochecks()
{
   time_t now=mtime();
	//status update
	if (difftime(time(NULL), prevnotify) <= 5)
	{
		writestatus();
		prevnotify = time(NULL);
	}
   if ((now-prevnotify)>NOTIFYCHECK)
   {
      configgroup *sgroup=configman->getgroup("system");
      if (sgroup&&sgroup->changed)
         configmyserver();
      serverinterface->sendservernotify("*", myserver, NULL);
      prevnotify=now;
   }
   if ((now-prevlagcheck)>LAGCHECK)
   { 
      char data[80];
      sprintf(data,"-1 %lu", mtime());
      serverinterface->sendping("*", data);
      prevlagcheck=now;
   }
   if ((now-prevcertcheck)>CERTFILECHECK)
   {
      configentry *entry;
      configgroup *sysgroup=configman->getgroup("system");
      if (sysgroup) if ((entry=sysgroup->getentry("certificates"))!=NULL)
      {
         if (certfile) free(certfile);
         certfile=strdup(entry->getdata());
         struct stat buf;
         prevcertcheck=now;
         if (!stat(certfile, &buf)) if (buf.st_mtime!=certfilestat)
         {
            certfilestat=buf.st_mtime;
            readcert();
         }
      }
   }
// WhazzUp Start
   if ((now-prevwhazzup)>=WHAZZUPCHECK)
   {
      configentry *entry;
      configgroup *sysgroup=configman->getgroup("system");
      if (sysgroup) if ((entry=sysgroup->getentry("whazzup"))!=NULL)
      {
         if (whazzupfile) free(whazzupfile);
         whazzupfile=strdup(entry->getdata());
         char whazzuptemp[100];
         sprintf(whazzuptemp,"%s%s", whazzupfile, ".tmp");
         prevwhazzup=now;
         if (fileopen==0)
         {
            FILE *wzfile=fopen(whazzuptemp, "w");
            if (wzfile)
            {
               //Ready to write data
               fileopen = 1;
               char s[32];
			   fprintf(wzfile,"%s%s\n","![DateStamp]",sprintgmtdate(now,s));
               fprintf(wzfile,"%s\n","!GENERAL");
               fprintf(wzfile,"%s = %d\n", "VERSION", 1);
               fprintf(wzfile,"%s = %d\n", "RELOAD", 1);
               fprintf(wzfile,"%s = %s\n", "UPDATE", sprintgmt(now, s));
               client *tempclient;
               flightplan *tempflightplan;
               server *tempserver;
               int clients=0;
               for (tempclient=rootclient;tempclient;tempclient=tempclient->next)
                  clients++;
               fprintf(wzfile,"%s = %d\n", "CONNECTED CLIENTS", clients);
               int servers=0;
               for (tempserver=rootserver;tempserver;tempserver=tempserver->next)
                  servers++;
               fprintf(wzfile,"%s = %d\n", "CONNECTED SERVERS", servers);
               fprintf(wzfile,"%s\n","!CLIENTS");
               char dataseg1[150]; char dataseg2[150]; char dataseg3[150]; char dataseg4[150]; char dataseg5[150]; char dataseg6[2000]; char dataseg7[50];
               for (tempclient=rootclient;tempclient;tempclient=tempclient->next)
               {
                  sprintf(dataseg1,"%s:%s:%s:%s", tempclient->callsign, tempclient->cid, tempclient->realname, tempclient->type==CLIENT_ATC?"ATC":"PILOT");
                  if (tempclient->frequency!=0 && tempclient->frequency<100000 && tempclient)
                     sprintf(dataseg2,"1%02d.%03d", tempclient->frequency/1000, tempclient->frequency%1000);
                  else
                     sprintf(dataseg2,"%s","");
                  tempflightplan=tempclient->plan;
                  if (tempclient->lat!=0 && tempclient->altitude < 100000 && tempclient->lon != 0)
                     sprintf(dataseg3,"%f:%f:%d:%d", tempclient->lat, tempclient->lon, tempclient->altitude, tempclient->groundspeed);
                  else
                     sprintf(dataseg3,"%s",":::");
                  if (tempflightplan)
                     sprintf(dataseg4,"%s:%d:%s:%s:%s", tempflightplan->aircraft, tempflightplan->tascruise, tempflightplan->depairport, tempflightplan->alt, tempflightplan->destairport);
                  else
                     sprintf(dataseg4,"%s","::::");
                  sprintf(dataseg5,"%s:%s:%d:%d:%d:%d", tempclient->location->ident, tempclient->protocol, tempclient->rating, tempclient->transponder, tempclient->facilitytype, tempclient->visualrange);
                  if (tempflightplan)
                     sprintf(dataseg6,"%d:%c:%d:%d:%d:%d:%d:%d:%s:%s:%s", tempflightplan->revision, tempflightplan->type, tempflightplan->deptime, tempflightplan->actdeptime, tempflightplan->hrsenroute, tempflightplan->minenroute, tempflightplan->hrsfuel, tempflightplan->minfuel, tempflightplan->altairport, tempflightplan->remarks, tempflightplan->route);
                  else
                     sprintf(dataseg6,"%s","::::::::::");
                  sprintf(dataseg7,"::::::%s", sprintgmt(tempclient->starttime,s));
                  fprintf(wzfile,"%s:%s:%s:%s:%s:%s:%s\n", dataseg1, dataseg2, dataseg3, dataseg4, dataseg5, dataseg6, dataseg7);
               }
               char dataline[150]; 
               fprintf(wzfile,"%s\n","!SERVERS");
               for (tempserver=rootserver;tempserver;tempserver=tempserver->next)
                  if (strcmp(tempserver->hostname,"n/a") != 0)
                  {
                     sprintf(dataline,"%s:%s:%s:%s:%d", tempserver->ident, tempserver->hostname, tempserver->location, tempserver->name, tempserver->flags&SERVER_SILENT?0:1);
                     fprintf(wzfile,"%s\n",dataline);
                  }; 
               fclose(wzfile);
			   remove(whazzupfile);
               rename(whazzuptemp, whazzupfile);
				// --- Pilot Snapshot JSON (im selben Ordner wie whazzup.txt) ---
try {
    fs::path wzPath(whazzupfile);
    fs::path outDir = wzPath.parent_path();

    fs::path jsonPath    = outDir / "pilot_snapshot.json";
    fs::path tmpJsonPath = outDir / "pilot_snapshot.json.tmp";

    Json::Value root;
    root["ts"] = (Json::Int64)time(NULL);

    Json::Value clients(Json::arrayValue);

    for (client *c = rootclient; c; c = c->next) {
        // nur Piloten
        if (c->type != CLIENT_PILOT) continue;

        // nur plausible Positionsdaten (analog zu whazzup-Logik)
        if (c->lat == 0.0 || c->lon == 0.0) continue;
        if (c->altitude >= 100000) continue;

        Json::Value j;
        j["callsign"] = c->callsign ? c->callsign : "";
        j["lat"]      = c->lat;
        j["lon"]      = c->lon;
        j["alt"]      = c->altitude;
        j["gs"]       = c->groundspeed;

        // PBH + dekodiertes Heading
        j["pbh"]      = (Json::UInt64)c->pbh;
        const double hdg_tru = heading_from_pbh((uint32_t)c->pbh);
		j["hdg_tru"] = hdg_tru;

		double decl = 0.0;
		try {
   		 // altitude in Metern (wenn du nur feet hast: feet * 0.3048)
    		// Wenn du keine zuverlässige Höhe hast, ist 0.0 m ok.
    		decl = declination_deg(c->lat, c->lon, 0.0);
		} catch (...) {
    		decl = 0.0; // Fallback: keine Korrektur
		}

		const double hdg_mag = wrap360(hdg_tru - decl);

		j["decl_deg"] = decl;      // fürs Debuggen extrem hilfreich
		j["hdg_mag"]  = hdg_mag;   // sollte eher zur Simulator-Anzeige passen


        clients.append(j);
    }

    root["clients"] = clients;

    // atomisch schreiben (tmp + rename), wie whazzup
    {
        std::ofstream jf(tmpJsonPath.string(), std::ios::trunc);
        Json::StreamWriterBuilder builder;
        builder["indentation"] = ""; // kompakt (eine Zeile)
        std::unique_ptr<Json::StreamWriter> writer(builder.newStreamWriter());
        writer->write(root, &jf);
        jf << "\n";
    }

    // rename ist atomar, wenn im gleichen FS/Dir
    std::error_code ec;
    fs::remove(jsonPath, ec); // optional (verhindert rename-Probleme bei manchen Setups)
    fs::rename(tmpJsonPath, jsonPath, ec);
    if (ec) {
        // Fallback
        std::rename(tmpJsonPath.string().c_str(), jsonPath.string().c_str());
    }
} catch (...) {
    // Snapshot darf den Serverbetrieb nicht stören
}

               fileopen=0;
            }
            else
               fileopen=0;
         }
      }
   }
// WhazzUp End
   server *tempserver=rootserver;
   while (tempserver)
   {
      server *next=tempserver->next;
      if ((now-tempserver->alive)>SERVERTIMEOUT&&(tempserver!=myserver))
         delete tempserver;
      tempserver=next;
   }
   client *tempclient=rootclient;

   /* Check for client timeouts. We should not drop clients if we are in
      silent mode; If we are in silent mode, we won't receive updates, so
      every client would timeout. When we are a silent server, the limit
      will be SILENTCLIENTTIMEOUT, which is about 10 hours  */
   int limit=(myserver->flags&SERVER_SILENT)?SILENTCLIENTTIMEOUT:CLIENTTIMEOUT;
   while (tempclient)
   {
      client *next=tempclient->next;
      if (tempclient->location!=myserver)
      if ((now-tempclient->alive)>limit)
         delete tempclient;
      tempclient=next;
   }
}
void fsd::run()
{
   pmanager->run();
   if (timer!=mtime())
   {
      timer=mtime();
      dochecks();
   }
}
void fsd::configmyserver()
{
   int mode=0;
   char *serverident=NULL, *servername=NULL;
   char *servermail=NULL, *serverhostname=NULL;
   char *serverlocation=NULL;
   configentry *entry;
   configgroup *sysgroup=configman->getgroup("system");
   if (sysgroup)
   {
      sysgroup->changed=0;
      if ((entry=sysgroup->getentry("ident"))!=NULL)
         serverident=entry->getdata();
      if ((entry=sysgroup->getentry("name"))!=NULL)
         servername=entry->getdata();
      if ((entry=sysgroup->getentry("email"))!=NULL)
         servermail=entry->getdata();
      if ((entry=sysgroup->getentry("hostname"))!=NULL)
         serverhostname=entry->getdata();
