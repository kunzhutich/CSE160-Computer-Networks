#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"
#define LS_MAX_ROUTES 256


configuration LinkStateC {
    provides interface LinkState;
}

implementation {
    components LinkStateP;
    LinkState = LinkStateP;

    components new SimpleSendC(AM_PACK);
    LinkStateP.Sender -> SimpleSendC;

    components new HashmapC(uint32_t, 100);
    LinkStateP.rMap -> HashmapC;

    components NDiscC;
    LinkStateP.NDisc -> NDiscC;    

    components FloodC;
    LinkStateP.Flood -> FloodC;

    components new TimerMilliC() as LSRTimer;
    LinkStateP.LSRTimer -> LSRTimer;

    components RandomC as Random;
    LinkStateP.Random -> Random;
}
