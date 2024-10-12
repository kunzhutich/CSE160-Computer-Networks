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
    uint32_t createKey(uint16_t src, uint16_t seq) {
        return ((uint32_t)src << 16) | (uint32_t)seq;
    }

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
    
    command void Flood.ping(uint16_t destination, uint8_t *payload) {
        dbg(FLOODING_CHANNEL, "SOURCE %d\n", TOS_NODE_ID);
        dbg(FLOODING_CHANNEL, "DESTINATION %d\n", destination);
        makePack(&pck, TOS_NODE_ID, destination, 10, PROTOCOL_PING, sequenceNum, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(pck, AM_BROADCAST_ADDR);
        sequenceNum++;
    }

    command void Flood.flood(pack* myMsg) {
        uint32_t key = createKey(myMsg->src, myMsg->seq);

        if(call fMap.contains(key)) { 
            dbg(FLOODING_CHANNEL, "Packet already seen!\n");
        }
        else if(myMsg->TTL == 0) {
            dbg(FLOODING_CHANNEL, "TTL expired!\n");
        } 
        else if(myMsg->dest == TOS_NODE_ID) {
            if(myMsg->protocol == PROTOCOL_PING) {
                dbg(FLOODING_CHANNEL, "Ping received!\n");
                logPack(myMsg);
                call fMap.insert(key, 1);
                makePack(&pck, myMsg->dest, myMsg->src, 10, PROTOCOL_PINGREPLY, sequenceNum++,(uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                call Sender.send(pck, AM_BROADCAST_ADDR);
                dbg(FLOODING_CHANNEL, "Reply Sent!\n");
            } 
            else if(myMsg->protocol == PROTOCOL_PINGREPLY) {
                dbg(FLOODING_CHANNEL, "Reply received!\n");
                logPack(myMsg);
                call fMap.insert(myMsg->src, myMsg->seq);
            }
        } 
        else {
            myMsg->TTL -= 1;
            call fMap.insert(key, 1);
            // call Sender.send(*myMsg, AM_BROADCAST_ADDR);
            // dbg(FLOODING_CHANNEL, "Packet forwarded\n");
            if (myMsg->src != prevSender) {  // Ensuring not sending back to previous sender
                call Sender.send(*myMsg, AM_BROADCAST_ADDR);
                dbg(FLOODING_CHANNEL, "Packet forwarded\n");
            } else {
                dbg(FLOODING_CHANNEL, "Packet not forwarded back to sender\n");
            }
        }
    }

    
}