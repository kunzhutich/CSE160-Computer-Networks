#include "../../includes/packet.h"
#include "../../includes/protocol.h"


module NDiscP {
    provides interface NDisc;
    uses interface Timer<TMilli> as Timer;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint32_t> as ndMap;
}

implementation {
    pack pck;
    
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    command void NDisc.start() {
        call Timer.startPeriodic(5000); // Start periodic timer every 5 second
        dbg(NEIGHBOR_CHANNEL, "Starting NDiscovery!\n");
    }

    command void NDisc.stop() {
        call Timer.stop(); // func to stop neighbor discovery
        dbg(NEIGHBOR_CHANNEL, "Stopping NDiscovery!\n");
    }


    command void NDisc.nDiscovery(pack* ndMsg) {
        if(ndMsg->protocol == PROTOCOL_PING && ndMsg->TTL > 0) {
            ndMsg->TTL -= 1; // decrements time to live
            ndMsg->src = TOS_NODE_ID; // 
            ndMsg->protocol = PROTOCOL_PINGREPLY;
            call Sender.send(*ndMsg, AM_BROADCAST_ADDR);
            // makePack(&pck, ndMsg->dest, ndMsg->src, ndMsg->TTL, PROTOCOL_PINGREPLY, 0, (uint8_t *) ndMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
        } else if(ndMsg->protocol == PROTOCOL_PINGREPLY && ndMsg->dest == 0) {
            dbg(NEIGHBOR_CHANNEL,"Found Neighbor %d\n", ndMsg->src);
            // call Sender.send(*ndMsg, AM_BROADCAST_ADDR);
            if(!call ndMap.contains(ndMsg->src)) {
                call ndMap.insert(ndMsg->src, ndMsg->TTL);
                
            } else {
                call ndMap.insert(ndMsg->src, ndMsg->TTL);
            }
            call NDisc.print();
        }
    }
    command void NDisc.print() {
        uint16_t i = 0;
        uint32_t* keys = call ndMap.getKeys();    
        // Print neighbors
        dbg(NEIGHBOR_CHANNEL, "Printing Neighbors of %d:\n", TOS_NODE_ID);
        for(i = 0; i < call ndMap.size(); i++) {
            if(keys[i] != 0) {
                dbg(NEIGHBOR_CHANNEL, "\tNode %d\n", keys[i]);
            }
        }
    }
    event void Timer.fired() {
        uint16_t i = 0;
        uint8_t payload = 0;
        uint32_t* keys = call ndMap.getKeys();
        // call NDisc.print();
        // Remove old neighbors
        for(i = 0; i < call ndMap.size(); i++) {
            if(keys[i] != 0) {
                dbg(NEIGHBOR_CHANNEL, "Checking Neighbor\n");
                if (call ndMap.get(keys[i]) - call Timer.getNow() < 1000){
                    dbg(NEIGHBOR_CHANNEL, "Removing Neighbor %d\n", keys[i]);
                    call ndMap.remove(keys[i]);
                }
            }
        }
    
        makePack(&pck, TOS_NODE_ID, 0, 1, PROTOCOL_PING, 0, &payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(pck, AM_BROADCAST_ADDR);
    
    }
}