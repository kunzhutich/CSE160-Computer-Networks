/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}

implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
    
    components NDiscC;
    Node.NDisc -> NDiscC;

    components FloodC;
    Node.Flood -> FloodC;

    components RoutingC;
    Node.Routing -> RoutingC;

    components TransportC;
    Node.Transport -> TransportC;

    components new TimerMilliC() as ServerTimer;
    Node.ServerTimer -> ServerTimer;

    components new TimerMilliC() as ClientTimer;
    Node.ClientTimer -> ClientTimer;

    components IPC;
    Node.IP -> IPC;
}
