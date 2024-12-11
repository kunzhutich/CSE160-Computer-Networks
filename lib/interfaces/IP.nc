#include "../../includes/packet.h"

interface IP {
    command error_t send(pack* packet);
}
