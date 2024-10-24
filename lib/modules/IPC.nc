configuration IPC {
    provides interface IP;
}

implementation {
    components IPP;
    IP = IPP;

    components new SimpleSendC(AM_PACK);
    IPP.Sender -> SimpleSendC;

    components RoutingC;
    IPP.Routing -> RoutingC;
}
