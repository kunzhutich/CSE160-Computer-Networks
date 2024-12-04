#ifndef TRANSPORT_H
#define TRANSPORT_H

#include "packet.h"

#define MIN(a, b) ((a) < (b) ? (a) : (b))

#define FLAG_SYN 0x01
#define FLAG_ACK 0x02
#define FLAG_FIN 0x04
#define WINDOW_SIZE 4 

// Transport header stored in the payload of a packet
typedef struct transport_header_t {
    uint8_t flags;           // Transport flags (e.g., SYN, ACK, FIN)
    uint16_t seqNum;         // Sequence number
    uint16_t advertisedWindow; // Flow control window size
} transport_header_t;

// Socket metadata for managing transport-specific data
typedef struct socket_metadata_t {
    socket_t socketId;       // Associated socket ID
    uint8_t state;           // Connection state (e.g., SYN_SENT, ESTABLISHED, FIN_WAIT)
    uint8_t retries[WINDOW_SIZE]; // Retransmission attempts for each packet
    uint8_t acked[WINDOW_SIZE];   // ACK tracking for each packet
} socket_metadata_t;

// Helper functions
// void createTransportHeader(transport_header_t *header, uint8_t flags, uint16_t seqNum, uint16_t window);
// void createTransportHeader(pack* packet, uint16_t srcPort, uint16_t destPort, uint8_t flags) {
//     packet->src = srcPort;
//     packet->dest = destPort;
//     packet->protocol = PROTOCOL_TCP | flags;
//     packet->TTL = 255; // Default Time-to-Live
//     packet->seq = 0;   // Default sequence number
//     memset(packet->payload, 0, sizeof(packet->payload)); // Clear payload
// }

void createTransportHeader(pack *packet, uint16_t srcPort, uint16_t destPort, uint8_t flags, uint16_t seqNum, uint16_t window) {
    // Populate the transport header
    transport_header_t header = {
        .flags = flags,
        .seqNum = seqNum,
        .advertisedWindow = window
    };
    
    // Ensure the packet structure is zeroed out before use
    memset(packet, 0, sizeof(pack));
    
    // Add the transport header to the payload
    memcpy(packet->payload, &header, sizeof(header));

    // Populate remaining packet fields
    packet->src = srcPort;
    packet->dest = destPort;
    packet->protocol = PROTOCOL_TCP;
    packet->TTL = 255;  // Default Time-to-Live
    packet->seq = seqNum;
}

// void initTransportHeader(pack *packet);

// void parseTransportHeader(pack *packet, transport_header_t *header);

// Inline implementation of transport functions
static inline void initTransportHeader(pack *packet) {
    memset(packet, 0, sizeof(pack));
    packet->protocol = PROTOCOL_TCP; // Default protocol
    packet->TTL = 255;              // Default TTL
}

static inline void parseTransportHeader(pack *packet, transport_header_t *header) {
    memcpy(header, packet->payload, sizeof(transport_header_t));
}

#endif
