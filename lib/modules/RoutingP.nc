#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"


module RoutingP {
    provides interface Routing;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint16_t> as rMap;
    uses interface Flood as flo;
    uses interface Timer<TMilli> as rTimer;
    uses interface NDisc as NDisc;
}

implementation{
    uint8_t count = 0;
    typedef struct{
        uint8_t nextHop;
        uint8_t cost;
        uint8_t dest;
    } Route;
    Route RoutingTable[100];
     void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    command void Routing.start(){
        call nDisc.start();
        call rTimer.startPeriodic(10000);
        dbg(ROUTING_CHANNEL, "Starting Routing");
    }

    command void floodRouting(uint16_t lost){
        uint16_t neighbors = call NDisc.nDiscovery();
        uint16_t nSize = call NDisc.print();

    }

    command void addRouting(uint8_t nextHop, uint8_t cost, uint8_t dest;){
            RoutingTable[count].dest = dest;
			RoutingTable[count].cost = cost;	
			RoutingTable[count].nextHop = nextHop;	
			count++;
    }

    command void Routing.print(){
		uint32_t i = 0;
		
		dbg(ROUTING_CHANNEL, "Printing Routing Table\n");
		dbg(ROUTING_CHANNEL, "Dest\tHop\tCount\n");
    }
}