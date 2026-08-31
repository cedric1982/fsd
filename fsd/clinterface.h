#ifndef CLINTERFACEHH
#define CLINTERFACEHH

#include <ctime>
#include <unordered_map>
#include <chrono>

#include "interface.h"
#include "user.h"
#include "client.h"
#include "wprofile.h"

// Struktur für gecachte Pilotpositionen
struct PilotPosData {
    std::string data;
    std::chrono::steady_clock::time_point lastUpdate;
};

class clinterface : public tcpinterface
{
private:
    time_t prevwinddelta;

    int getbroad(char*);

    // Cache für Pilotpositionen (Tick-System)
    std::unordered_map<std::string, PilotPosData> posCache;

    // Hilfsfunktion: Client anhand Callsign finden
    client* findClientByCallsign(const std::string& callsign);

public:
    clinterface(int, char*, char*);

    virtual int run();
    virtual void newuser(int, char*, int, int);

    void sendaa(client*, absuser*);
    void sendap(client*, absuser*);
    void sendda(client*, absuser*);
    void senddp(client*, absuser*);
    void sendgeneric(char*, client*, absuser*, client*, char*, char*, int);
    void sendpilotpos(client*, absuser*);
    void sendatcpos(client*, absuser*);
    void sendplan(client*, client*, int);
    void sendweather(client*, wprofile*);
    void sendmetar(client*, char*);
    void sendnowx(client*, char*);
    void sendpacket(client*, client*, absuser*, int, int, int, char*);
    void sendwinddelta();
    void handlekill(client*, char*);
    int calcrange(client*, client*, int, int);

    friend class cluser;
};

#endif
