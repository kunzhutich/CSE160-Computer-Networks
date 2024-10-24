#ifndef NEIGHBOR_DISCOVERY_H
#define NEIGHBOR_DISCOVERY_H

#include "packet.h"
#include "channels.h"

enum {
    NEIGHBOR_TIMEOUT = 5000,  // example
};

typedef struct neighborData {
    uint16_t totalPacketsSent;
    uint16_t totalPacketsReceived;
    uint8_t missedResponses;
    bool isActive;
} neighborData;

#endif /* NEIGHBOR_DISCOVERY_H */
