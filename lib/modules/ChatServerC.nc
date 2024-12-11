#include "../../includes/socket.h"

configuration ChatServerC {
    provides interface ChatServer;
}

implementation {
    components ChatServerP;
    ChatServer = ChatServerP.ChatServer;
    
    components TransportC;
    ChatServerP.Transport -> TransportC.Transport;
    
    components RoutingC;
    ChatServerP.Routing -> RoutingC.Routing;

    components NDiscC;
    ChatServerP.NDisc -> NDiscC.NDisc;
    
    components new SimpleSendC(AM_PACK);
    ChatServerP.Sender -> SimpleSendC;
    
    // For managing connected clients list
    components new HashmapC(socket_store_t*, 20) as ConnectedClients;
    ChatServerP.ConnectedClients -> ConnectedClients;
    
    // Timer for periodic cleanup of disconnected clients
    components new TimerMilliC() as ServerTimer;
    ChatServerP.ServerTimer -> ServerTimer;
}