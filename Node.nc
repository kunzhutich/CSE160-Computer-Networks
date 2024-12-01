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
#include "includes/socket.h"

module Node{
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;

    uses interface NDisc;
    uses interface Flood;
    uses interface Routing;
    uses interface Transport;
}

implementation{
    pack sendPackage;

    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    event void Boot.booted(){
        call AMControl.start();

        call NDisc.start();         // When doing flooding module, should comment this line
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
            call NDisc.nDiscovery(myMsg);
        } else {
            call Routing.routed(myMsg);
            // call Flood.flood(myMsg);
        }
        return msg;
    }


    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        call Routing.ping(destination, payload);

        // // Clear hashmap if needed before sending a new ping
        // call Flood.init();

        // makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        // call Sender.send(sendPackage, destination);
        // call Flood.ping(destination, payload);
    }

    event void CommandHandler.printNeighbors(){
        call NDisc.print();
    }

    event void CommandHandler.printRouteTable(){
        call Routing.printTable();
    }

    event void CommandHandler.printLinkState(){}

    event void CommandHandler.printDistanceVector(){}



    event void CommandHandler.setTestServer(uint8_t port) {
        socket_t serverSocket = call Transport.socket();        // Allocate a socket
        socket_addr_t serverAddr;       // Bind the socket to the port

        dbg(TRANSPORT_CHANNEL, "Setting up a test server on port %d\n", port);
        
        if (serverSocket == NULL_SOCKET) {
            dbg(TRANSPORT_CHANNEL, "Failed to allocate a socket for the server\n");
            return;
        }

        serverAddr.addr = TOS_NODE_ID; // The server's node ID
        serverAddr.port = port;
        if (call Transport.bind(serverSocket, &serverAddr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to bind socket to port %d\n", port);
            return;
        }

        // Start listening on the socket
        if (call Transport.listen(serverSocket) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to set the server socket to listen\n");
            return;
        }

        dbg(TRANSPORT_CHANNEL, "Server setup complete on port %d\n", port);
    }



    event void CommandHandler.setTestClient(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer) {
        socket_t clientSocket = call Transport.socket();
        socket_addr_t clientAddr;
        socket_addr_t serverAddr;        // Connect to the destination

        uint8_t payload[16];
        uint16_t i;
        uint16_t len;
        uint8_t j;

        dbg(TRANSPORT_CHANNEL, "Setting up a test client to Node %d, Port %d (from Port %d), transferring %d bytes\n",
            dest, destPort, srcPort, transfer);

        if (clientSocket == NULL_SOCKET) {
            dbg(TRANSPORT_CHANNEL, "Failed to allocate a socket for the client\n");
            return;
        }
   

        clientAddr.addr = TOS_NODE_ID; // The client's node ID
        clientAddr.port = srcPort;
        if (call Transport.bind(clientSocket, &clientAddr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to bind socket to port %d\n", srcPort);
            return;
        }


        serverAddr.addr = dest;      // The server's node ID
        serverAddr.port = destPort;  // The server's port
        if (call Transport.connect(clientSocket, &serverAddr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to connect to Node %d, Port %d\n", dest, destPort);
            return;
        }

        // Simulate data transfer
        dbg(TRANSPORT_CHANNEL, "Client connection established, starting data transfer\n");
       
        for (i = 0; i < transfer; i += sizeof(payload)) {
            len = (transfer - i > sizeof(payload)) ? sizeof(payload) : (transfer - i);
            for (j = 0; j < len; j++) {
                payload[j] = (i + j) & 0xFF; // Fill payload with data
            }
            call Transport.write(clientSocket, payload, len);
        }
        dbg(TRANSPORT_CHANNEL, "Data transfer complete\n");
    }



    event void CommandHandler.clientClose(uint16_t dest, uint8_t srcPort, uint8_t destPort) {
        dbg(TRANSPORT_CHANNEL, "Closing client connection to destination %d\n", dest);

        // Close the socket (logic may vary based on your implementation)
        call Transport.close(dest);
    }


    event void CommandHandler.clientWrite(uint16_t dest, uint8_t *payload) {
        socket_t clientSocket = dest; // Use dest as the socket descriptor (or modify based on your logic)
        uint16_t payloadLength = strlen((char*)payload);

        dbg(TRANSPORT_CHANNEL, "Client writing to destination %d\n", dest);

        if (call Transport.write(clientSocket, payload, payloadLength) == SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Client write successful\n");
        } else {
            dbg(TRANSPORT_CHANNEL, "Client write failed\n");
        }
    }


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
