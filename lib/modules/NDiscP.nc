#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/nDisc.h"


module NDiscP {
    provides interface NDisc;
    uses interface Timer<TMilli> as Timer;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint32_t> as ndMap;
}

implementation {
    pack pck;

    uint32_t packNeighborData(uint16_t totalPacketsSent, uint16_t totalPacketsReceived, uint8_t missedResponses, bool isActive) {
        uint32_t packedData = 0;
        packedData |= (totalPacketsSent & 0xFF) << 24;
        packedData |= (totalPacketsReceived & 0xFF) << 16;
        packedData |= (missedResponses & 0xFF) << 8;
        packedData |= (isActive & 0x1);  // Store isActive in the lowest bit
        return packedData;
    }

    void unpackNeighborData(uint32_t packedData, uint16_t *totalPacketsSent, uint16_t *totalPacketsReceived, uint8_t *missedResponses, bool *isActive) {
        *totalPacketsSent = (packedData >> 24) & 0xFF;
        *totalPacketsReceived = (packedData >> 16) & 0xFF;
        *missedResponses = (packedData >> 8) & 0xFF;
        *isActive = packedData & 0x1;
    }

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
        uint32_t packedData;
        uint16_t totalPacketsSent, totalPacketsReceived;
        uint8_t missedResponses;
        bool isActive;
        
        if(ndMsg->protocol == PROTOCOL_PING && ndMsg->TTL > 0) {
            // dbg(NEIGHBOR_CHANNEL, "BEFORE: src is %d and dest is %d\n", ndMsg->src, ndMsg->dest);
            ndMsg->dest = ndMsg->src;
            ndMsg->src = TOS_NODE_ID; 
            // dbg(NEIGHBOR_CHANNEL, "AFTER: src is %d and dest is %d\n", ndMsg->src, ndMsg->dest);

            // ndMsg->TTL -= 1;     // decrements time to live //we decided to use fixed TTL=255
            ndMsg->protocol = PROTOCOL_PINGREPLY;

            call Sender.send(*ndMsg, AM_BROADCAST_ADDR);
            // makePack(&pck, ndMsg->dest, ndMsg->src, ndMsg->TTL, PROTOCOL_PINGREPLY, 0, (uint8_t *) ndMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
        } else if(ndMsg->protocol == PROTOCOL_PINGREPLY && ndMsg->dest == TOS_NODE_ID) {
            dbg(NEIGHBOR_CHANNEL,"Found Neighbor %d\n", ndMsg->src);

            if (call ndMap.contains(ndMsg->src)) {
                packedData = call ndMap.get(ndMsg->src);
                unpackNeighborData(packedData, &totalPacketsSent, &totalPacketsReceived, &missedResponses, &isActive);
            } else {
                totalPacketsSent = 0;
                totalPacketsReceived = 0;
                missedResponses = 0;
                isActive = TRUE;
            }
            
            // Update the neighbor data
            totalPacketsSent++;
            totalPacketsReceived++;
            missedResponses = 0;
            packedData = packNeighborData(totalPacketsSent, totalPacketsReceived, missedResponses, isActive);
            call ndMap.insert(ndMsg->src, packedData);
            
            call NDisc.print();  // Print neighbor table
        }
    }

    command void NDisc.print() {
        uint16_t i = 0;
        uint32_t* keys = call ndMap.getKeys();
        
        uint32_t packedData;
        uint16_t totalPacketsSent, totalPacketsReceived;
        uint8_t missedResponses;
        bool isActive;

        float linkQuality;

        dbg(NEIGHBOR_CHANNEL, "Printing Neighbors of %d:\n", TOS_NODE_ID);
        for (i = 0; i < call ndMap.size(); i++) {
            if (keys[i] != 0) {
                packedData = call ndMap.get(keys[i]);
                unpackNeighborData(packedData, &totalPacketsSent, &totalPacketsReceived, &missedResponses, &isActive);
                linkQuality = (totalPacketsSent == 0) ? 0.0 :
                                    (float)totalPacketsReceived / totalPacketsSent;
                dbg(NEIGHBOR_CHANNEL, "\tNode %d: Link Quality: %.2f, Active: %s\n",
                    keys[i], linkQuality, isActive ? "Yes" : "No");
            }
        }
    }

    event void Timer.fired() {
        uint16_t i = 0;
        uint32_t* keys = call ndMap.getKeys();

        uint32_t packedData;
        uint16_t totalPacketsSent, totalPacketsReceived;
        uint8_t missedResponses;
        bool isActive;

        uint8_t payload = 0;

        // Check the status of each neighbor
        for (i = 0; i < call ndMap.size(); i++) {
            if (keys[i] != 0) {
                packedData = call ndMap.get(keys[i]);
                unpackNeighborData(packedData, &totalPacketsSent, &totalPacketsReceived, &missedResponses, &isActive);

                if (missedResponses >= 5) {
                    isActive = FALSE;
                    dbg(NEIGHBOR_CHANNEL, "Neighbor %d is inactive, removing from table.\n", keys[i]);
                    call ndMap.remove(keys[i]);

                    dbg(NEIGHBOR_CHANNEL, "Printing Neighbors again after removing a neighbor.\n");
                    call NDisc.print();
                } else {
                    missedResponses++;
                    totalPacketsSent++;
                    packedData = packNeighborData(totalPacketsSent, totalPacketsReceived, missedResponses, isActive);
                    call ndMap.insert(keys[i], packedData);
                }
            }
        }

        // Send a PING to discover neighbors
        makePack(&pck, TOS_NODE_ID, 0, 255, PROTOCOL_PING, 0, &payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(pck, AM_BROADCAST_ADDR);
    }

    command uint32_t NDisc.getNeighbors() {
        return call ndMap.getKeys();
    }

    command uint16_t NDisc.getSize() {
        return call ndMap.size();
    }

}