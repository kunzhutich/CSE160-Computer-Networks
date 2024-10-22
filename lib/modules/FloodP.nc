// #include <Timer.h>
// #include "../../includes/channels.h"
// #include "../../includes/packet.h"
// #include "../../includes/protocol.h"


// module FloodP {
//     provides interface Flood;
//     uses interface SimpleSend as Sender;
//     uses interface Hashmap<uint16_t> as fMap;
// }

// implementation {
//     pack pck;
//     uint16_t sequenceNum = 0;
//     uint32_t createKey(uint16_t src, uint16_t seq) {
//         return ((uint32_t)src << 16) | (uint32_t)seq;
//     }

//     typedef struct {
//         uint16_t src;
//         uint16_t seqNum;
//         neighborData neighbors[10];  // Store neighbor data for LSAs
//     } LSA;

//     void createLSA(pack *lsaPacket);

//     command void Flood.startFlooding() {
//         // Create and send the LSA packet
//         pack lsaPacket;
//         createLSA(&lsaPacket);  // Fill the packet with node's neighbor info
//         call Sender.send(lsaPacket, AM_BROADCAST_ADDR);  // Flood LSA to all nodes
//         dbg(FLOODING_CHANNEL, "LSA flooding started\n");
//     }

//     // Unpacking the neighbor data
//     void unpackNeighborData(uint32_t packedData, uint16_t *totalPacketsSent, uint16_t *totalPacketsReceived, uint8_t *missedResponses, bool *isActive) {
//         *totalPacketsSent = (packedData >> 24) & 0xFF;
//         *totalPacketsReceived = (packedData >> 16) & 0xFF;
//         *missedResponses = (packedData >> 8) & 0xFF;
//         *isActive = packedData & 0x1;
//     }

//     void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
//         Package->src = src;
//         Package->dest = dest;
//         Package->TTL = TTL;
//         Package->seq = seq;
//         Package->protocol = protocol;
//         memcpy(Package->payload, payload, length);
//     }

//     void createLSA(pack *lsaPacket) {
//         // Populate the LSA packet with the necessary information
//         lsaPacket->src = TOS_NODE_ID;
//         lsaPacket->protocol = PROTOCOL_LINKSTATE;

//         uint32_t* keys = call fMap.getKeys();
//         uint32_t packedData;

//         uint8_t i;
//         for (i = 0; i < fMap.size(); i++) {
//             if (keys[i] != 0) {
//                 packedData = call fMap.get(keys[i]); 
                
//                 // Unpack the neighbor data into the LSA packet
//                 unpackNeighborData(packedData, &lsaPacket->neighbors[i].totalPacketsSent, 
//                                    &lsaPacket->neighbors[i].totalPacketsReceived, 
//                                    &lsaPacket->neighbors[i].missedResponses, 
//                                    &lsaPacket->neighbors[i].isActive);
//             }
//         }
//     }


//     command void Flood.init() {
//         call fMap.clear();          // Clear hashmap entries on startup
//         sequenceNum = 0;
//         dbg(FLOODING_CHANNEL, "Flood module initialized\n");
//     }
    
//     command void Flood.ping(uint16_t destination, uint8_t *payload) {
//         dbg(FLOODING_CHANNEL, "SOURCE %d\n", TOS_NODE_ID);
//         dbg(FLOODING_CHANNEL, "DESTINATION %d\n", destination);
//         makePack(&pck, TOS_NODE_ID, destination, 10, PROTOCOL_PING, sequenceNum, payload, PACKET_MAX_PAYLOAD_SIZE);
//         call Sender.send(pck, AM_BROADCAST_ADDR);
//         // sequenceNum++;
//     }

//     command void Flood.flood(pack* myMsg) {
//         uint32_t key = createKey(myMsg->src, myMsg->seq);

//         // dbg(FLOODING_CHANNEL, "Received packet: Src: %d, Dest: %d, Seq: %d, TTL: %d, Protocol: %d\n",
//         //     myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL, myMsg->protocol);

//         if (call fMap.contains(key)) { 
//             dbg(FLOODING_CHANNEL, "Packet already seen!\n");
//             // dbg(FLOODING_CHANNEL, "Packet already seen! Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
//             return;
//         } else if (myMsg->TTL == 0) {
//             dbg(FLOODING_CHANNEL, "TTL expired!\n");    
//             // dbg(FLOODING_CHANNEL, "TTL expired for packet: Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
//             return;
//         } else if (myMsg->src == TOS_NODE_ID) {
//             dbg(FLOODING_CHANNEL, "Circular flood detected, dropping packet!\n");
//             // dbg(FLOODING_CHANNEL, "Circular flood detected! Dropping packet: Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
//             return;
//         } else if (myMsg->dest == TOS_NODE_ID) {
//             if (myMsg->protocol == PROTOCOL_PING) {
//                 dbg(FLOODING_CHANNEL, "Ping received!\n");
//                 // dbg(FLOODING_CHANNEL, "Ping received for this node. Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
//                 logPack(myMsg);
//                 call fMap.insert(key, 1);

//                 // Increment the sequence number for the reply
//                 sequenceNum++;

//                 // Send a reply back to the original sender
//                 makePack(&pck, myMsg->dest, myMsg->src, 10, PROTOCOL_PINGREPLY, sequenceNum, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
//                 // dbg(FLOODING_CHANNEL, "Sending Ping Reply to Src: %d\n", myMsg->src);
//                 call Sender.send(pck, AM_BROADCAST_ADDR);
//                 dbg(FLOODING_CHANNEL, "Reply Sent!\n");
//             } else if (myMsg->protocol == PROTOCOL_PINGREPLY) {
//                 dbg(FLOODING_CHANNEL, "Reply received!\n");
//                 // dbg(FLOODING_CHANNEL, "Ping Reply received! Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);

//                 logPack(myMsg);
//                 call fMap.insert(key, 1);
//             }
//             return;
//         } else {
//             // Forward the packet
//             myMsg->TTL -= 1;
//             call fMap.insert(key, 1);
//             dbg(FLOODING_CHANNEL, "Forwarding Paket!\n");
//             // dbg(FLOODING_CHANNEL, "Forwarding packet: Src: %d, Dest: %d, Seq: %d, TTL: %d\n",
//             //     myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL);
            
//             call Sender.send(*myMsg, AM_BROADCAST_ADDR);
//             // dbg(FLOODING_CHANNEL, "Packet forwarded\n");
//         }
//     }

//     void updateNeighborEntry(uint16_t neighborID, uint32_t packedData) {
//         uint16_t totalPacketsSent, totalPacketsReceived;
//         uint8_t missedResponses;
//         bool isActive;

//         // Unpack the current neighbor data
//         unpackNeighborData(packedData, &totalPacketsSent, &totalPacketsReceived, &missedResponses, &isActive);

//         // Logic for updating neighbor entry
//         if (missedResponses >= 5) {
//             isActive = FALSE;  // Mark as inactive if too many responses are missed
//             dbg(NEIGHBOR_CHANNEL, "Neighbor %d is now inactive\n", neighborID);
//         } else {
//             missedResponses = 0;  // Reset missed responses
//             totalPacketsReceived++;
//             isActive = TRUE;
//         }

//         // Pack and store the updated neighbor data
//         packedData = packNeighborData(totalPacketsSent, totalPacketsReceived, missedResponses, isActive);
//         call ndMap.insert(neighborID, packedData);
//     }

// }



#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module FloodP {
    provides interface Flood;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint16_t> as fMap;
}

implementation {
    pack pck;
    uint16_t sequenceNum = 0;

    typedef struct {
        uint16_t totalPacketsSent;
        uint16_t totalPacketsReceived;
        uint8_t missedResponses;
        bool isActive;
    } neighborData;

    typedef struct {
        uint16_t src;
        uint16_t seqNum;
        neighborData neighbors[10];  // Store neighbor data for LSAs
    } LSA;

    uint32_t createKey(uint16_t src, uint16_t seq) {
        return ((uint32_t)src << 16) | (uint32_t)seq;
    }

    void createLSA(pack *lsaPacket);

    command void Flood.startFlooding() {
        pack lsaPacket;
        createLSA(&lsaPacket);  // Create LSA
        call Sender.send(lsaPacket, AM_BROADCAST_ADDR);  // Flood LSA
        dbg(FLOODING_CHANNEL, "LSA flooding started\n");
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

    void createLSA(pack *lsaPacket) {
        lsaPacket->src = TOS_NODE_ID;
        lsaPacket->protocol = PROTOCOL_LINKSTATE;

        uint32_t* keys = call fMap.getKeys();  // Obtain the keys from fMap
        uint32_t packedData;

        for (uint8_t i = 0; i < call fMap.size(); i++) {  // Declare and use `i`
            if (keys[i] != 0) {
                packedData = call fMap.get(keys[i]);

                // Unpack neighbor data into LSA
                unpackNeighborData(packedData, &lsaPacket->neighbors[i].totalPacketsSent,
                                   &lsaPacket->neighbors[i].totalPacketsReceived,
                                   &lsaPacket->neighbors[i].missedResponses,
                                   &lsaPacket->neighbors[i].isActive);
            }
        }
    }

    command void Flood.init() {
        call fMap.clear();
        sequenceNum = 0;
        dbg(FLOODING_CHANNEL, "Flood module initialized\n");
    }

    command void Flood.ping(uint16_t destination, uint8_t *payload) {
        dbg(FLOODING_CHANNEL, "SOURCE %d\n", TOS_NODE_ID);
        dbg(FLOODING_CHANNEL, "DESTINATION %d\n", destination);
        makePack(&pck, TOS_NODE_ID, destination, 10, PROTOCOL_PING, sequenceNum, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(pck, AM_BROADCAST_ADDR);
    }

    command void Flood.flood(pack* myMsg) {
        uint32_t key = createKey(myMsg->src, myMsg->seq);

        if (call fMap.contains(key)) { 
            dbg(FLOODING_CHANNEL, "Packet already seen!\n");
            return;
        } else if (myMsg->TTL == 0) {
            dbg(FLOODING_CHANNEL, "TTL expired!\n");
            return;
        } else if (myMsg->src == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL, "Circular flood detected, dropping packet!\n");
            return;
        } else if (myMsg->dest == TOS_NODE_ID) {
            if (myMsg->protocol == PROTOCOL_PING) {
                dbg(FLOODING_CHANNEL, "Ping received!\n");
                logPack(myMsg);
                call fMap.insert(key, 1);

                // Increment the sequence number for the reply
                sequenceNum++;

                // Send a reply back to the original sender
                makePack(&pck, myMsg->dest, myMsg->src, 10, PROTOCOL_PINGREPLY, sequenceNum, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                call Sender.send(pck, AM_BROADCAST_ADDR);
                dbg(FLOODING_CHANNEL, "Reply Sent!\n");
            } else if (myMsg->protocol == PROTOCOL_PINGREPLY) {
                dbg(FLOODING_CHANNEL, "Reply received!\n");
                logPack(myMsg);
                call fMap.insert(key, 1);
            }
            return;
        } else {
            // Forward the packet
            myMsg->TTL -= 1;
            call fMap.insert(key, 1);
            dbg(FLOODING_CHANNEL, "Forwarding Packet!\n");
            call Sender.send(*myMsg, AM_BROADCAST_ADDR);
        }
    }
}
