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

    uses interface ChatClient;
    uses interface ChatServer;
}

implementation{
    pack sendPackage;

    // Project 3 stuff
    socket_t server_fd = -1;
    socket_t client_fd = -1;
    uint16_t client_transfer_amount = 0;
    uint16_t client_data_sent = 0;
    bool client_socket_established = FALSE;


    // Project 4 stuff
    bool isServer = FALSE;
    bool isClient = FALSE;
    uint8_t clientUsername[16];
    uint8_t clientPort;

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
        }
        else if (myMsg->protocol == PROTOCOL_LINKSTATE){
            call Routing.linkState(myMsg);
        }
        // else if (myMsg->protocol == PROTOCOL_TCP) {
        //     if (myMsg->dest == TOS_NODE_ID) {
        //         dbg(GENERAL_CHANNEL, "TCP packet received at destination node %d\n", TOS_NODE_ID);
        //         call Transport.receive(myMsg);
        //     } else {
        //         // Forward the TCP packet towards its destination
        //         dbg(TRANSPORT_CHANNEL, "Forwarding TCP packet from %d to %d\n", myMsg->src, myMsg->dest);
        //         call IP.send(myMsg);
        //     }

        //     if (isServer || isClient) {
        //         call Transport.receive(myMsg);
        //     }

        //     if (myMsg->dest != TOS_NODE_ID) {
        //         call IP.send(myMsg);
        //     }
        // }
        else if (myMsg->protocol == PROTOCOL_TCP) {
            // Handle TCP packets
            if (isServer || isClient) {
                // If we're a server or client, process the packet through Transport
                call Transport.receive(myMsg);
            }
            
            // Forward if not destined for us (this happens after processing in case we need to handle and forward)
            if (myMsg->dest != TOS_NODE_ID) {
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




    // Add these new event handlers for CommandHandler:
    event void CommandHandler.setAppServer() {
        dbg(COMMAND_CHANNEL, "Starting Chat Server\n");
        isServer = TRUE;
        call ChatServer.start();
    }

    event void CommandHandler.setAppClient() {
        dbg(COMMAND_CHANNEL, "Starting Chat Client\n");
        isClient = TRUE;
        strcpy((char*)clientUsername, "defaultUser");  // You can modify this as needed
        clientPort = 50;  // Default client port
    }

    event void CommandHandler.handleHello(uint16_t src, uint8_t *username, uint8_t port) {
        if (!isClient) {
            dbg(COMMAND_CHANNEL, "Error: Node is not initialized as client\n");
            return;
        }
        call ChatClient.connect(username, port);
    }

    event void CommandHandler.handleMsg(uint16_t src, uint8_t *message) {
        if (!isClient) {
            dbg(COMMAND_CHANNEL, "Error: Node is not initialized as client\n");
            return;
        }
        call ChatClient.sendMessage(message);
    }

    event void CommandHandler.handleWhisper(uint16_t src, uint8_t *username, uint8_t *message) {
        if (!isClient) {
            dbg(COMMAND_CHANNEL, "Error: Node is not initialized as client\n");
            return;
        }
        call ChatClient.whisper(username, message);
    }

    event void CommandHandler.handleListUsers(uint16_t src) {
        if (!isClient) {
            dbg(COMMAND_CHANNEL, "Error: Node is not initialized as client\n");
            return;
        }
        call ChatClient.listUsers();
    }

    // Event handlers for ChatClient:
    event void ChatClient.messageReceived(uint8_t *sender, uint8_t *message) {
        dbg(GENERAL_CHANNEL, "Message from %s: %s\n", sender, message);
    }

    event void ChatClient.connectionComplete() {
        dbg(GENERAL_CHANNEL, "Connected to chat server!\n");
    }

    event void ChatClient.userListReceived(uint8_t *users) {
        dbg(GENERAL_CHANNEL, "Connected users: %s\n", users);
    }

    // Event handlers for ChatServer:
    event void ChatServer.clientConnected(uint16_t clientId, uint8_t *username) {
        dbg(GENERAL_CHANNEL, "Client %d connected with username: %s\n", clientId, username);
    }

    event void ChatServer.clientDisconnected(uint16_t clientId) {
        dbg(GENERAL_CHANNEL, "Client %d disconnected\n", clientId);
    }

    event void ChatServer.messageReceived(uint16_t clientId, uint8_t *message) {
        dbg(GENERAL_CHANNEL, "Message from client %d: %s\n", clientId, message);
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
}
