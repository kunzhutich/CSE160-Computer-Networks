#include "../../includes/packet.h"
interface Routing{
    command void start();
    command void ping(uint16_t destination, uint8_t *payload);
    command void routed(pack *myMsg);
    command void print();
}