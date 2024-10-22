#include "../../includes/packet.h"
interface Flood{
    command void init();
    command void ping(uint16_t dest, uint8_t *payload);
    command void flood(pack* msg);
    command void startFlooding();
}