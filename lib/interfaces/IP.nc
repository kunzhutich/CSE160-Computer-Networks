#include "../../includes/packet.h"

interface IP {
    command void send(pack* myMsg);
    command void forward(pack* myMsg);
}
