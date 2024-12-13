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

            uint8_t username[16];
            uint8_t port;
            uint8_t *message;
            uint16_t i;
            char *token;

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

            dbg(COMMAND_CHANNEL, "Processing command ID: %d\n", commandID);
            dbg(COMMAND_CHANNEL, "Payload: %s\n", buff);

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

                case CMD_TEST_SERVER:
                    dbg(COMMAND_CHANNEL, "Command Type: Testing Server\n");
                    signal CommandHandler.setTestServer(msg->dest, buff[0]);
                    break;

                case CMD_TEST_CLIENT:
                    dbg(COMMAND_CHANNEL, "Command Type: Testing Client\n");
                    signal CommandHandler.setTestClient(msg->dest, buff[0], buff[1], buff[2], (buff[3] << 8) | buff[4]);
                    break;

                case CMD_CLIENT_CLOSE:
                    dbg(COMMAND_CHANNEL, "Command Type: Closing Client\n");
                    signal CommandHandler.clientClose(msg->dest, buff[0], buff[1], buff[2]);
                    break;


                // Project 4
                case CMD_SET_APP_SERVER:
                    dbg(COMMAND_CHANNEL, "Command Type: Setting Up Server\n");
                    signal CommandHandler.setAppServer(msg->dest);
                    break;

                case CMD_SET_APP_CLIENT:
                    dbg(COMMAND_CHANNEL, "Command Type: Setting Up Client\n");
                    signal CommandHandler.setAppClient(msg->dest);
                    break;

                case CMD_HELLO:
                    dbg(COMMAND_CHANNEL, "Processing HELLO command\n");
                    token = strtok((char*)buff, " ");  // Get "hello"
                    if(token != NULL) {
                        dbg(COMMAND_CHANNEL, "Found hello token\n");
                        token = strtok(NULL, " ");     // Get username
                        if(token != NULL) {
                            strncpy((char*)username, token, 15);
                            username[15] = '\0';
                            dbg(COMMAND_CHANNEL, "Username: %s\n", username);
                            
                            token = strtok(NULL, "\r\n"); // Get port
                            if(token != NULL) {
                                port = atoi(token);
                                dbg(COMMAND_CHANNEL, "Port: %d\n", port);
                                signal CommandHandler.handleHello(msg->dest, username, port);
                            } else {
                                dbg(COMMAND_CHANNEL, "Error: No port found\n");
                            }
                        } else {
                            dbg(COMMAND_CHANNEL, "Error: No username found\n");
                        }
                    } else {
                        dbg(COMMAND_CHANNEL, "Error: Invalid hello format\n");
                    }
                    break;

                case CMD_MSG:
                    dbg(COMMAND_CHANNEL, "Processing MSG command\n");
                    token = strtok((char*)buff, " ");  // Get "msg"
                    if(token != NULL) {
                        message = (uint8_t*)strtok(NULL, "\r\n");
                        if(message != NULL) {
                            dbg(COMMAND_CHANNEL, "Message: %s\n", message);
                            signal CommandHandler.handleMsg(msg->dest, message);
                        } else {
                            dbg(COMMAND_CHANNEL, "Error: No message content\n");
                        }
                    }
                    break;

                case CMD_WHISPER:
                    // Parse whisper command: whisper [username] [message]\r\n
                    token = strtok((char*)buff, " ");  // Get "whisper"

                    if(token != NULL) {
                        token = strtok(NULL, " ");     // Get target username
                        if(token != NULL) {
                            strncpy((char*)username, token, 15);
                            username[15] = '\0';
                            
                            message = (uint8_t*)strtok(NULL, "\r\n");
                            if(message != NULL) {
                                signal CommandHandler.handleWhisper(msg->dest, username, message);
                            }
                        }
                    }

                    break;

                case CMD_LISTUSR:
                    signal CommandHandler.handleListUsers(msg->dest);
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
