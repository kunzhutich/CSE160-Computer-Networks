#ifndef NEIGHBOR_DISCOVERY_H
#define NEIGHBOR_DISCOVERY_H

#include "packet.h"
#include "channels.h"

enum {
    // MAX_NEIGHBOR_COUNT = 10,
    NEIGHBOR_TIMEOUT = 5000,  // Example: Timeout value in milliseconds
};


typedef struct neighborData {
    uint16_t totalPacketsSent;
    uint16_t totalPacketsReceived;
    uint8_t missedResponses;
    bool isActive;
} neighborData;

// Function declarations for neighbor discovery
// void handleNeighborDiscovery(pack* receivedPack);
// void updateNeighborStatus(uint16_t neighborId, bool isActive);

#endif /* NEIGHBOR_DISCOVERY_H */
