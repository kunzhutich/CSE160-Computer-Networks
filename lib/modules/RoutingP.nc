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
    uses interface NDisc as ND;
}

implementation{
    uint8_t count = 0;
    pack rt;
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
        call ND.start();
        call rTimer.startPeriodic(10000);
        dbg(ROUTING_CHANNEL, "Starting Routing");
    }

        command void Routing.ping(uint16_t destination, uint8_t *payload) {
        makePack(&rt, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %d TO %d\n", TOS_NODE_ID, destination);
        logPack(&rt);
        call Routing.routed(&rt);
    }    


    command void Routing.routed(pack *myMsg){
        dbg(ROUTING_CHANNEL, "work");
    }   
    
    void floodRouting(uint16_t lost){
        uint16_t neighbors = call ND.getNeighbors();
        uint16_t nSize = call ND.getSize();

    }

    void addRouting(uint8_t nextHop, uint8_t cost, uint8_t dest;){
            RoutingTable[count].dest = dest;
			RoutingTable[count].cost = cost;	
			RoutingTable[count].nextHop = nextHop;	
			count++;
    }

    event void rTimer.fired(){
        call Routing.print();
    }

    command void Routing.print(){
		uint32_t i = 0;
		
		dbg(ROUTING_CHANNEL, "Printing Routing Table\n");
		dbg(ROUTING_CHANNEL, "Dest\tHop\tCount\n");
    }
}