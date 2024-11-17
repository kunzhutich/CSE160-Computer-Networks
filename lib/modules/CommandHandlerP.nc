// /**
//  * @author UCM ANDES Lab
//  * $Author: abeltran2 $
//  * $LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
//  *
//  */


// #include "../../includes/CommandMsg.h"
// #include "../../includes/command.h"
// #include "../../includes/channels.h"

// module CommandHandlerP{
//    provides interface CommandHandler;
//    uses interface Receive;
//    uses interface Pool<message_t>;
//    uses interface Queue<message_t*>;
//    uses interface Packet;
// }

// implementation{
//     task void processCommand(){
//         if(! call Queue.empty()){
//             CommandMsg *msg;
//             uint8_t commandID;
//             uint8_t* buff;
//             message_t *raw_msg;
//             void *payload;

//             // Pop message out of queue.
//             raw_msg = call Queue.dequeue();
//             payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

//             // Check to see if the packet is valid.
//             if(!payload){
//                 call Pool.put(raw_msg);
//                 post processCommand();
//                 return;
//             }
//             // Change it to our type.
//             msg = (CommandMsg*) payload;

//             dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
//             buff = (uint8_t*) msg->payload;
//             commandID = msg->id;

//             //Find out which command was called and call related command
//             switch(commandID){
//                 // A ping will have the destination of the packet as the first
//                 // value and the string in the remainder of the payload
//                 case CMD_PING:
//                     dbg(COMMAND_CHANNEL, "Command Type: Ping\n");
//                     signal CommandHandler.ping(buff[0], &buff[1]);
//                     break;

//                 case CMD_NEIGHBOR_DUMP:
//                     dbg(COMMAND_CHANNEL, "Command Type: Neighbor Dump\n");
//                     signal CommandHandler.printNeighbors();
//                     break;

//                 case CMD_LINKSTATE_DUMP:
//                     dbg(COMMAND_CHANNEL, "Command Type: Link State Dump\n");
//                     signal CommandHandler.printLinkState();
//                     break;

//                 case CMD_ROUTETABLE_DUMP:
//                     dbg(COMMAND_CHANNEL, "Command Type: Route Table Dump\n");
//                     signal CommandHandler.printRouteTable();
//                     break;

//                 case CMD_TEST_CLIENT:
//                     dbg(COMMAND_CHANNEL, "Command Type: Client\n");
//                     signal CommandHandler.setTestClient();
//                     break;

//                 case CMD_TEST_SERVER:
//                     dbg(COMMAND_CHANNEL, "Command Type: Client\n");
//                     signal CommandHandler.setTestServer();
//                     break;

//                 case CMD_KILL:
//                     dbg(COMMAND_CHANNEL, "Command Type: Kill\n");
//                     signal CommandHandler.close();
//                     break;


//                 default:
//                     dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
//                     break;
//             }
//             call Pool.put(raw_msg);
//         }

//         if(! call Queue.empty()){
//             post processCommand();
//         }
//     }
//     event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len){
//         if (! call Pool.empty()){
//             call Queue.enqueue(raw_msg);
//             post processCommand();
//             return call Pool.get();
//         }
//         return raw_msg;
//     }
// }



#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"
#include "../../includes/socket.h"

#define NULL_SOCKET -1
#define ATTEMPT_CONNECTION_TIME 1000  // might adjust this later
#define TRANSFER_SIZE 128  // shoudn't adjust right?


module CommandHandlerP {
    provides interface CommandHandler;
    uses interface Receive;
    uses interface Pool<message_t>;
    uses interface Queue<message_t*>;
    uses interface Packet;
    uses interface Transport;
    uses interface Timer<TMilli> as ConnectionTimer;
}

implementation {
    socket_t serverFd = -1;  // Server socket descriptor
    socket_t clientFd = -1;  // Client socket descriptor

    task void processCommand() {
        if (!call Queue.empty()) {
            CommandMsg *msg;
            uint8_t commandID;
            uint8_t* buff;
            message_t *raw_msg;
            void *payload;

            raw_msg = call Queue.dequeue();
            payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

            if (!payload) {
                call Pool.put(raw_msg);
                post processCommand();
                return;
            }

            msg = (CommandMsg*) payload;
            dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
            buff = (uint8_t*) msg->payload;
            commandID = msg->id;

            switch (commandID) {
                case CMD_TEST_SERVER:
                    dbg(COMMAND_CHANNEL, "Command Type: Test Server\n");
                    serverFd = call Transport.socket();
                    if (serverFd != NULL_SOCKET) {
                        socket_addr_t addr = { .port = buff[0] };
                        if (call Transport.bind(serverFd, &addr) == SUCCESS) {
                            call Transport.listen(serverFd);
                            dbg(COMMAND_CHANNEL, "Server listening on port %d\n", addr.port);
                            call ConnectionTimer.startOneShot(ATTEMPT_CONNECTION_TIME);
                        }
                    }
                    break;

                case CMD_TEST_CLIENT:

                    dbg(COMMAND_CHANNEL, "Command Type: Test Client\n");
                    clientFd = call Transport.socket();
                    if (clientFd != NULL_SOCKET) {
                        socket_addr_t srcAddr = { .port = buff[1] };
                        socket_addr_t destAddr = { .addr = buff[0], .port = buff[2] };
                        if (call Transport.bind(clientFd, &srcAddr) == SUCCESS &&
                            call Transport.connect(clientFd, &destAddr) == SUCCESS) {
                            uint8_t data[TRANSFER_SIZE] = {0};
                            
                            dbg(COMMAND_CHANNEL, "Client connected to server %d on port %d\n", destAddr.addr, destAddr.port);
                            // Send initial data after connection is established
                            // data[TRANSFER_SIZE] = {0};
                            call Transport.write(clientFd, data, TRANSFER_SIZE);
                        }
                    }
                    break;

                case CMD_KILL:
                    dbg(COMMAND_CHANNEL, "Command Type: Kill\n");
                    if (clientFd != -1) {
                        call Transport.close(clientFd);
                        dbg(COMMAND_CHANNEL, "Client connection closed.\n");
                        clientFd = -1;
                    }
                    if (serverFd != -1) {
                        call Transport.close(serverFd);
                        dbg(COMMAND_CHANNEL, "Server connection closed.\n");
                        serverFd = -1;
                    }
                    break;

                default:
                    dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
                    break;
            }
            call Pool.put(raw_msg);
        }

        if (!call Queue.empty()) {
            post processCommand();
        }
    }

    event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len) {
        if (!call Pool.empty()) {
            call Queue.enqueue(raw_msg);
            post processCommand();
            return call Pool.get();
        }
        return raw_msg;
    }

    event void ConnectionTimer.fired() {
        socket_t newFd = call Transport.accept(serverFd);
        if (newFd != NULL_SOCKET) {
            dbg(COMMAND_CHANNEL, "New connection accepted on server.\n");
            serverFd = newFd;  // Update to handle new connection
        } else {
            dbg(COMMAND_CHANNEL, "No connection available at timer expiration.\n");
        }
    }
}
