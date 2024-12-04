configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components IPC;
    TransportP.IP -> IPC;

    components new TimerMilliC() as TransportTimer;
    TransportP.Timer -> TransportTimer;
}
