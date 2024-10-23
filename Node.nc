/*
* ANDES Lab - University of California, Merced
* This class provides the basic functions of a network node.
*
* @author UCM ANDES Lab
* @date   2013/09/03
*
*/
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;

    uses interface NeighborDiscovery;
    uses interface Flood;
    uses interface Routing;
}

implementation{
    pack sendPackage;

    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    event void Boot.booted(){
        call AMControl.start();

        call NeighborDiscovery.start();         // When doing flooding module, should comment this line
        call Routing.start();
        dbg(GENERAL_CHANNEL, "Booted\n");
    }

    event void AMControl.startDone(error_t err){
        if(err == SUCCESS){
            dbg(GENERAL_CHANNEL, "Radio On\n");
        }else{
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err){}


    // from SKELETON CODE:
    // event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
    //     dbg(GENERAL_CHANNEL, "Packet Received\n");
    //     if(len==sizeof(pack)){
    //         pack* myMsg=(pack*) payload;
    //         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
    //         return msg;
    //     }
    //     dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
    //     return msg;
    // }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* myMsg = (pack*) payload;
        if(len!=sizeof(pack)) {
            dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
            dbg(GENERAL_CHANNEL, "Dropping the Unknown Packet\n");
            return msg;         // Drop packet

        }else if (myMsg->protocol == PROTOCOL_LINKSTATE){
            call Routing.linkState(myMsg);
        } 
        else if(myMsg->dest == 0) {
            call NeighborDiscovery.handleNeighbor(myMsg);
        } else {
            call Routing.routed(myMsg);
        }
        return msg;
    }


    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        call Routing.ping(destination, payload);
        // Clear hashmap if needed before sending a new ping
    //     call Flood.init();

    //     makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);

    //     call Sender.send(sendPackage, destination);
    //     call Flood.ping(destination, payload);
    }

    event void CommandHandler.printNeighbors(){
        call NeighborDiscovery.printNeighbors();
    }

    event void CommandHandler.printRouteTable(){
        call Routing.printTable();
    }

    event void CommandHandler.printLinkState(){}

    event void CommandHandler.printDistanceVector(){}

    event void CommandHandler.setTestServer(){}

    event void CommandHandler.setTestClient(){}

    event void CommandHandler.setAppServer(){}

    event void CommandHandler.setAppClient(){}

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
}
