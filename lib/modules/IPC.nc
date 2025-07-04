configuration IPC {
    provides interface IP;
}

implementation {
    components IPP;
    components new SimpleSendC(AM_PACK);
    components RoutingC;

    IP = IPP.IP;
    
    IPP.Sender -> SimpleSendC;
    IPP.Routing -> RoutingC;
}