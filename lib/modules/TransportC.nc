#include <AM.h>

configuration TransportC {
    provides interface Transport;
    // uses interface Boot;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components new TimerMilliC() as TransportTimer;
    TransportP.RetransmitTimer -> TransportTimer;

    components new SimpleSendC(AM_PACK);
    TransportP.Sender -> SimpleSendC;

    components ActiveMessageC;
    TransportP.Receive -> ActiveMessageC.Receive[AM_PACK];

    components MainC;
    TransportP.Boot -> MainC.Boot;
}
