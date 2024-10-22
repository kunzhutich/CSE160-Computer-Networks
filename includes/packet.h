//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H
// #define PROTOCOL_LINKSTATE 2

#include "protocol.h"
#include "channels.h"
#include "constants.h" 

enum{
	PACKET_HEADER_LENGTH = 8,
	PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH,
	MAX_TTL = 15
};


typedef nx_struct pack{
	nx_uint16_t dest;
	nx_uint16_t src;
	nx_uint16_t seq;		//Sequence Number
	nx_uint8_t TTL;		//Time to Live
	nx_uint8_t protocol;
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}pack;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input){
	dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol: %hhu   Payload: %s\n",
	input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
}

enum{
	AM_PACK=6
};


typedef struct {
    uint16_t neighbor;
    uint16_t cost;
} NeighborInfo;

typedef struct {
    uint16_t nodeID;
    uint16_t seqNum;
    uint8_t numNeighbors;
    NeighborInfo neighbors[MAX_NEIGHBORS];
} LSAPayload;


#endif
