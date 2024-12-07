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
#include "includes/transport.h"


module Node{
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;

    uses interface NDisc;
    uses interface Flood;
    uses interface Routing;

    uses interface IP;
    uses interface Transport;
    uses interface Timer<TMilli> as ServerTimer;
    uses interface Timer<TMilli> as ClientTimer;
}

implementation{
    pack sendPackage;

    socket_t server_fd = -1;
    socket_t client_fd = -1;
    uint16_t client_transfer_amount = 0;
    uint16_t client_data_sent = 0;
    bool client_socket_established = FALSE;


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

        }
        else if (myMsg->protocol == PROTOCOL_LINKSTATE){
            call Routing.linkState(myMsg);
        }
        else if (myMsg->protocol == PROTOCOL_TCP) {
            if (myMsg->dest == TOS_NODE_ID) {
                dbg(GENERAL_CHANNEL, "TCP packet received at destination node %d\n", TOS_NODE_ID);
                call Transport.receive(myMsg);
            } else {
                // Forward the TCP packet towards its destination
                dbg(TRANSPORT_CHANNEL, "Forwarding TCP packet from %d to %d\n", myMsg->src, myMsg->dest);
                call IP.send(myMsg);
            }
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




    event void ServerTimer.fired() {
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint16_t bytesRead, i;

        socket_t new_fd = call Transport.accept(server_fd);

        if (new_fd != (socket_t)-1) {
            dbg(TRANSPORT_CHANNEL, "Accepted connection on socket %d\n", new_fd);

            // Read data from the new socket
            bytesRead = call Transport.read(new_fd, buffer, SOCKET_BUFFER_SIZE);
            if (bytesRead > 0) {
                // Process the received data
                dbg(TRANSPORT_CHANNEL, "Received data on socket %d:\n", new_fd);
                for (i = 0; i < bytesRead; i++) {
                    dbg(TRANSPORT_CHANNEL, "Data[%d]: %d\n", i, buffer[i]);
                }
            }
        }
    }

    event void CommandHandler.setTestServer(uint16_t src, uint8_t port){
        socket_addr_t serverAddr;
        serverAddr.port = port;
        serverAddr.addr = src;

        server_fd = call Transport.socket();

        dbg(COMMAND_CHANNEL, "Setting up Test Server at port %d\n", port);

        if (call Transport.bind(server_fd, &serverAddr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to bind socket\n");
            return;
        }

        if (call Transport.listen(server_fd) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to listen on socket\n");
            return;
        }

        // Start a timer to accept connections periodically
        call ServerTimer.startPeriodic(1000);
    }
    



    event void Transport.clientConnected(socket_t fd) {
        dbg(TRANSPORT_CHANNEL, "Client socket %d connected\n", fd);
        client_socket_established = TRUE;

        // Start the client timer to write data periodically
        call ClientTimer.startPeriodic(1000);
    }

    event void ClientTimer.fired() {
        uint8_t buffer[TRANSPORT_MAX_PAYLOAD_SIZE];
        uint16_t bytesToSend = (client_transfer_amount - client_data_sent) * 2; // 2 bytes per integer
        uint16_t i = 0;
        uint16_t bytesWritten;
        

        if (!client_socket_established) {
            dbg(TRANSPORT_CHANNEL, "Client socket not established yet\n");
            return;
        }

        if (client_data_sent >= client_transfer_amount) {
            // All data sent
            dbg(TRANSPORT_CHANNEL, "All data sent by client\n");
            call ClientTimer.stop();
            return;
        }

        if (bytesToSend > TRANSPORT_MAX_PAYLOAD_SIZE) {
            bytesToSend = TRANSPORT_MAX_PAYLOAD_SIZE;
        }

        // Prepare data to send
        while (i < bytesToSend && client_data_sent < client_transfer_amount) {
            buffer[i++] = (client_data_sent >> 8) & 0xFF; // High byte
            buffer[i++] = client_data_sent & 0xFF;        // Low byte
            client_data_sent++;
        }

        if (i > 0) {
            bytesWritten = call Transport.write(client_fd, buffer, i);
            dbg(TRANSPORT_CHANNEL, "Client wrote %d bytes\n", bytesWritten);
        } else {
            dbg(TRANSPORT_CHANNEL, "No data to send\n");
        }
    }

    event void CommandHandler.setTestClient(uint16_t src, uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer){
        socket_addr_t clientAddr;
        socket_addr_t destAddr;

        clientAddr.port = srcPort;
        clientAddr.addr = src;
        
        destAddr.port = destPort;
        destAddr.addr = dest;

        client_fd = call Transport.socket();

        dbg(COMMAND_CHANNEL, "Setting up Test Client to %d:%d from port %d\n", dest, destPort, srcPort);

        if (call Transport.bind(client_fd, &clientAddr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to bind socket\n");
            return;
        }

        if (call Transport.connect(client_fd, &destAddr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to connect\n");
            return;
        }

        client_transfer_amount = transfer;
        client_data_sent = 0;

        // call ClientTimer.startPeriodic(1000);
    }



    event void CommandHandler.clientClose(uint16_t src, uint8_t dest, uint8_t srcPort, uint8_t destPort){
        dbg(COMMAND_CHANNEL, "Closing Client connection to %d:%d from port %d\n", dest, destPort, srcPort);

        if (client_fd != -1) {
            if (call Transport.close(client_fd) != SUCCESS) {
                dbg(TRANSPORT_CHANNEL, "Failed to close client socket\n");
            } else {
                dbg(TRANSPORT_CHANNEL, "Client socket closed successfully\n");
            }
            client_fd = -1;
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
