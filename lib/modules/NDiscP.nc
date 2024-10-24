#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/nDisc.h"


module NDiscP {
    provides interface NDisc;
    uses interface Timer<TMilli> as Timer;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint32_t> as Hashmap;
    uses interface Routing;
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
        call Timer.startPeriodic(5000);
        dbg(ROUTING_CHANNEL, "Starting NDiscovery!\n");
    }

    command void NDisc.stop() {
        call Timer.stop(); // func to stop neighbor discovery
        dbg(ROUTING_CHANNEL, "Stopping NDiscovery!\n");
    }

    command void NDisc.nDiscovery(pack* ndMsg) {
        uint32_t packedData;
        uint16_t totalPacketsSent, totalPacketsReceived;
        uint8_t missedResponses;
        bool isActive;
        
        if(ndMsg->protocol == PROTOCOL_PING && ndMsg->TTL > 0) {
            ndMsg->src = TOS_NODE_ID;
            ndMsg->TTL -= 1;
            ndMsg->protocol = PROTOCOL_PINGREPLY;

            call Sender.send(*ndMsg, AM_BROADCAST_ADDR);
        } else if(ndMsg->protocol == PROTOCOL_PINGREPLY && ndMsg->dest == 0) {
            // dbg(NEIGHBOR_CHANNEL, "PINGREPLY received from %d\n", ndMsg->src);
            dbg(NEIGHBOR_CHANNEL,"Found Neighbor %d\n", ndMsg->src);
            call Routing.foundNeighbor(); // comment line out mayybe

            if (call Hashmap.contains(ndMsg->src)) {
                // dbg(NEIGHBOR_CHANNEL, "Neighbor %d already in hashmap\n", ndMsg->src);
                packedData = call Hashmap.get(ndMsg->src);
                unpackNeighborData(packedData, &totalPacketsSent, &totalPacketsReceived, &missedResponses, &isActive);
            } else {
                // dbg(NEIGHBOR_CHANNEL, "Adding neighbor %d to hashmap\n", ndMsg->src);
                call Hashmap.insert(ndMsg->src, 1);

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
            call Hashmap.insert(ndMsg->src, packedData);
            
            call NDisc.print();
        }
    }

    command void NDisc.print() {
        uint16_t i = 0;
        uint32_t* keys = call Hashmap.getKeys();
        
        uint32_t packedData;
        uint16_t totalPacketsSent, totalPacketsReceived;
        uint8_t missedResponses;
        bool isActive;

        float linkQuality;

        dbg(NEIGHBOR_CHANNEL, "Printing Neighbors of %d:\n", TOS_NODE_ID);
        for (i = 0; i < call Hashmap.size(); i++) {
            if (keys[i] != 0) {
                packedData = call Hashmap.get(keys[i]);
                unpackNeighborData(packedData, &totalPacketsSent, &totalPacketsReceived, &missedResponses, &isActive);
                linkQuality = (totalPacketsSent == 0) ? 0.0 :
                (float)totalPacketsReceived / totalPacketsSent;
                dbg(NEIGHBOR_CHANNEL, "\tNode %d: Link Quality: %.2f, Active: %s, SeqNum: %d\n",
                    keys[i], linkQuality, isActive ? "Yes" : "No", totalPacketsSent);
            }
        }
    }

    event void Timer.fired() {
        uint16_t i = 0;
        uint32_t* keys = call Hashmap.getKeys();

        uint32_t packedData;
        uint16_t totalPacketsSent, totalPacketsReceived;
        uint8_t missedResponses;
        bool isActive;

        uint8_t payload = 0;

        // Check the status of each neighbor
        for (i = 0; i < call Hashmap.size(); i++) {
            if (keys[i] != 0) {
                packedData = call Hashmap.get(keys[i]);
                unpackNeighborData(packedData, &totalPacketsSent, &totalPacketsReceived, &missedResponses, &isActive);

                if (missedResponses >= 5) {
                    isActive = FALSE;
                    dbg(NEIGHBOR_CHANNEL, "Neighbor %d is inactive, removing from table.\n", keys[i]);
                    call Hashmap.remove(keys[i]);
                    call Routing.lostNeighbor(keys[i]); // comment line out maybe

                    dbg(NEIGHBOR_CHANNEL, "Printing Neighbors again after removing a neighbor.\n");
                    call NDisc.print();
                } else {
                    missedResponses++;
                    totalPacketsSent++;
                    packedData = packNeighborData(totalPacketsSent, totalPacketsReceived, missedResponses, isActive);
                    call Hashmap.insert(keys[i], packedData);
                }
            }
        }

        // Send a PING to discover neighbors
        makePack(&pck, TOS_NODE_ID, 0, 1, PROTOCOL_PING, totalPacketsSent, &payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(pck, AM_BROADCAST_ADDR);
    }

    command uint32_t* NDisc.getNeighbors() {
        return call Hashmap.getKeys();
    }

    command uint16_t NDisc.getSize() {
        return call Hashmap.size();
    }
}