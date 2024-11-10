#ifndef UTILS_H
#define UTILS_H

#include <string.h>
#include <stdint.h>
#include "packet.h"

inline void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
    Package->src = src;
    Package->dest = dest;
    Package->TTL = TTL;
    Package->seq = seq;
    Package->protocol = protocol;
    memcpy(Package->payload, payload, length);
}

static inline uint32_t createSeqKey(uint16_t src, uint16_t seq) {
    return ((uint32_t)src << 16) | (uint32_t)seq;
}

static inline uint32_t createLinkKey(uint16_t src, uint16_t dest) {
    return ((uint32_t)src << 16) | (uint32_t)dest;
}

#endif // UTILS_H
