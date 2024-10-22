configuration LinkStateC {
    provides interface LinkState;
}

implementation {
    components LinkStateP;
    LinkState = LinkStateP;

    components new HashmapC(uint16_t, 20) as LSASequenceMap;
    LinkStateP.LSASeqMap -> LSASequenceMap;

    components new HashmapC(uint16_t, 20) as RoutingTableMap;
    LinkStateP.RoutingTable -> RoutingTableMap;

    components FloodC;
    LinkStateP.Flood -> FloodC;

    components new TimerMilliC() as LSTimer;
    LinkStateP.Timer -> LSTimer;
}
