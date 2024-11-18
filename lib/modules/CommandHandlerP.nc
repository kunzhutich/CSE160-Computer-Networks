/**
 * @author UCM ANDES Lab
 * $Author: abeltran2 $
 * $LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
 *
 */


#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

module CommandHandlerP{
   provides interface CommandHandler;
   uses interface Receive;
   uses interface Pool<message_t>;
   uses interface Queue<message_t*>;
   uses interface Packet;
}

implementation{
    task void processCommand(){
        if(! call Queue.empty()){
            CommandMsg *msg;
            uint8_t commandID;
            uint8_t* buff;
            message_t *raw_msg;
            void *payload;

            // Pop message out of queue.
            raw_msg = call Queue.dequeue();
            payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

            // Check to see if the packet is valid.
            if(!payload){
                call Pool.put(raw_msg);
                post processCommand();
                return;
            }
            // Change it to our type.
            msg = (CommandMsg*) payload;

            dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
            buff = (uint8_t*) msg->payload;
            commandID = msg->id;

            //Find out which command was called and call related command
            switch(commandID){
                // A ping will have the destination of the packet as the first
                // value and the string in the remainder of the payload
                case CMD_PING:
                    dbg(COMMAND_CHANNEL, "Command Type: Ping\n");
                    signal CommandHandler.ping(buff[0], &buff[1]);
                    break;

                case CMD_NEIGHBOR_DUMP:
                    dbg(COMMAND_CHANNEL, "Command Type: Neighbor Dump\n");
                    signal CommandHandler.printNeighbors();
                    break;

                case CMD_LINKSTATE_DUMP:
                    dbg(COMMAND_CHANNEL, "Command Type: Link State Dump\n");
                    signal CommandHandler.printLinkState();
                    break;

                case CMD_ROUTETABLE_DUMP:
                    dbg(COMMAND_CHANNEL, "Command Type: Route Table Dump\n");
                    signal CommandHandler.printRouteTable();
                    break;

                case CMD_TEST_CLIENT:
                    dbg(COMMAND_CHANNEL, "Command Type: Client\n");
                    signal CommandHandler.setTestClient();
                    break;

                case CMD_TEST_SERVER:
                    dbg(COMMAND_CHANNEL, "Command Type: Client\n");
                    signal CommandHandler.setTestServer();
                    break;

                case CMD_KILL:
                    dbg(COMMAND_CHANNEL, "Command Type: Kill\n");
                    signal CommandHandler.close();
                    break;


                default:
                    dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
                    break;
            }
            call Pool.put(raw_msg);
        }

        if(! call Queue.empty()){
            post processCommand();
        }
    }
    event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len){
        if (! call Pool.empty()){
            call Queue.enqueue(raw_msg);
            post processCommand();
            return call Pool.get();
        }
        return raw_msg;
    }
}




// #include "../../includes/CommandMsg.h"
// #include "../../includes/command.h"
// #include "../../includes/channels.h"
// #include "../../includes/socket.h"

// module CommandHandlerP {
//    provides interface CommandHandler;
//    uses interface Receive;
//    uses interface Pool<message_t>;
//    uses interface Queue<message_t*>;
//    uses interface Packet;
//    uses interface Transport;
// }

// implementation {
//     // Global variables to store socket information for server and client
//     socket_t serverSocket;
//     socket_t clientSocket;
//     socket_addr_t serverAddress;
//     socket_addr_t clientAddress;
//     bool isConnected = FALSE;

//     task void processCommand() {
//         if (!call Queue.empty()) {
//             CommandMsg *msg;
//             uint8_t commandID;
//             uint8_t* buff;
//             message_t *raw_msg;
//             void *payload;

//             // Pop message out of queue.
//             raw_msg = call Queue.dequeue();
//             payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

//             // Check to see if the packet is valid.
//             if (!payload) {
//                 call Pool.put(raw_msg);
//                 post processCommand();
//                 return;
//             }
//             // Change it to our type.
//             msg = (CommandMsg*) payload;

//             dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
//             buff = (uint8_t*) msg->payload;
//             commandID = msg->id;

//             // Find out which command was called and call related command
//             switch(commandID) {
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

//                 case CMD_TEST_SERVER: {
//                     dbg(COMMAND_CHANNEL, "Command Type: Server Setup\n");

//                     // Initialize server socket and address
//                     serverSocket = call Transport.socket();
//                     serverAddress.port = buff[0];
//                     serverAddress.addr = TOS_NODE_ID;

//                     // Bind the server socket
//                     if (call Transport.bind(serverSocket, &serverAddress) == SUCCESS) {
//                         dbg(COMMAND_CHANNEL, "Server bound to port %d\n", buff[0]);
//                         // Server listening and accepting connections
//                         if (call Transport.listen(serverSocket) == SUCCESS) {
//                             dbg(COMMAND_CHANNEL, "Server listening on port %d\n", serverAddress.port);
//                         }
//                     } else {
//                         dbg(COMMAND_CHANNEL, "Failed to bind server to port %d\n", buff[0]);
//                     }
//                     break;
//                 }

//                 case CMD_TEST_CLIENT: {
//                     dbg(COMMAND_CHANNEL, "Command Type: Client Setup\n");

//                     // Initialize client socket and address
//                     clientSocket = call Transport.socket();
//                     clientAddress.port = buff[1]; // Source port
//                     clientAddress.addr = TOS_NODE_ID;

//                     // Server address to connect to
//                     serverAddress.port = buff[2];
//                     serverAddress.addr = buff[0]; // Destination address

//                     // Bind client socket
//                     if (call Transport.bind(clientSocket, &clientAddress) == SUCCESS) {
//                         dbg(COMMAND_CHANNEL, "Client bound to port %d\n", clientAddress.port);

//                         // Attempt to connect
//                         if (call Transport.connect(clientSocket, &serverAddress) == SUCCESS) {
//                             dbg(COMMAND_CHANNEL, "Client connected to server at %d:%d\n", serverAddress.addr, serverAddress.port);
//                             isConnected = TRUE;
//                         } else {
//                             dbg(COMMAND_CHANNEL, "Client failed to connect to server at %d:%d\n", serverAddress.addr, serverAddress.port);
//                         }
//                     } else {
//                         dbg(COMMAND_CHANNEL, "Failed to bind client to port %d\n", clientAddress.port);
//                     }
//                     break;
//                 }

//                 case CMD_KILL:
//                     dbg(COMMAND_CHANNEL, "Command Type: Close Connection\n");
//                     if (isConnected) {
//                         // Close client socket connection gracefully
//                         if (call Transport.close(clientSocket) == SUCCESS) {
//                             dbg(COMMAND_CHANNEL, "Connection closed for client on port %d\n", clientAddress.port);
//                             isConnected = FALSE;
//                         } else {
//                             dbg(COMMAND_CHANNEL, "Failed to close connection for client on port %d\n", clientAddress.port);
//                         }
//                     } else {
//                         dbg(COMMAND_CHANNEL, "No active connection to close.\n");
//                     }
//                     break;

//                 default:
//                     dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
//                     break;
//             }
//             call Pool.put(raw_msg);
//         }

//         if (!call Queue.empty()) {
//             post processCommand();
//         }
//     }

//     event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len) {
//         if (!call Pool.empty()) {
//             call Queue.enqueue(raw_msg);
//             post processCommand();
//             return call Pool.get();
//         }
//         return raw_msg;
//     }
// }
