configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components new TimerMilliC() as TransportTimer;
    TransportP.RetransmitTimer -> TransportTimer;

    components new SimpleSendC(AM_PACK);
    TransportP.Sender -> SimpleSendC;

    // components CommandHandlerC;
    // TransportP.CommandHandler -> CommandHandlerC;
}
