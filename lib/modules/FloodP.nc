#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/utils.h"


module FloodP {
    provides interface Flood;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint16_t> as Hashmap;
}

implementation {
    pack pck;
    uint16_t sequenceNum = 0;

    command void Flood.init() {
        call Hashmap.clear();          // Clear hashmap entries on startup
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
        uint32_t key = createSeqKey(myMsg->src, myMsg->seq);

        // dbg(FLOODING_CHANNEL, "Received packet: Src: %d, Dest: %d, Seq: %d, TTL: %d, Protocol: %d\n",
        //     myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL, myMsg->protocol);

        if (call Hashmap.contains(key)) { 
            dbg(FLOODING_CHANNEL, "Packet already seen!\n");
            // dbg(FLOODING_CHANNEL, "Packet already seen! Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
            return;
        } else if (myMsg->TTL == 0) {
            dbg(FLOODING_CHANNEL, "TTL expired!\n");    
            // dbg(FLOODING_CHANNEL, "TTL expired for packet: Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
            return;
        } else if (myMsg->src == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL, "Circular flood detected, dropping packet!\n");
            // dbg(FLOODING_CHANNEL, "Circular flood detected! Dropping packet: Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
            return;
        } else if (myMsg->dest == TOS_NODE_ID) {
            if (myMsg->protocol == PROTOCOL_PING) {
                dbg(FLOODING_CHANNEL, "Ping received!\n");
                // dbg(FLOODING_CHANNEL, "Ping received for this node. Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);
                logPack(myMsg);
                call Hashmap.insert(key, 1);

                sequenceNum++;

                // Send a reply back to the original sender
                makePack(&pck, myMsg->dest, myMsg->src, 10, PROTOCOL_PINGREPLY, sequenceNum, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                // dbg(FLOODING_CHANNEL, "Sending Ping Reply to Src: %d\n", myMsg->src);
                call Sender.send(pck, AM_BROADCAST_ADDR);
                dbg(FLOODING_CHANNEL, "Reply Sent!\n");
            } else if (myMsg->protocol == PROTOCOL_PINGREPLY) {
                dbg(FLOODING_CHANNEL, "Reply received!\n");
                // dbg(FLOODING_CHANNEL, "Ping Reply received! Src: %d, Seq: %d\n", myMsg->src, myMsg->seq);

                logPack(myMsg);
                call Hashmap.insert(key, 1);
            }
            return;
        } else {
            // Forward the packet
            myMsg->TTL -= 1;
            call Hashmap.insert(key, 1);
            dbg(FLOODING_CHANNEL, "Forwarding Paket!\n");
            // dbg(FLOODING_CHANNEL, "Forwarding packet: Src: %d, Dest: %d, Seq: %d, TTL: %d\n",
            //     myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL);
            
            call Sender.send(*myMsg, AM_BROADCAST_ADDR);
            // dbg(FLOODING_CHANNEL, "Packet forwarded\n");
        }
    }
}