#include "../../includes/socket.h"

configuration ChatClientC {
    provides interface ChatClient;
}

implementation {
    components ChatClientP;
    ChatClient = ChatClientP.ChatClient;

    // Wire Transport for TCP connections
    components TransportC;
    ChatClientP.Transport -> TransportC.Transport;

    // Wire components for sending messages
    components new SimpleSendC(AM_PACK);
    ChatClientP.Sender -> SimpleSendC;

    // For timers to handle reconnection attempts
    components new TimerMilliC() as ClientTimer;
    ChatClientP.ClientTimer -> ClientTimer;
}