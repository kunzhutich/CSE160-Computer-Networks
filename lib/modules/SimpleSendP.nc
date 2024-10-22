/**
 * ANDES Lab - University of California, Merced
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

generic module SimpleSendP(){
    // provides shows the interface we are implementing. See lib/interface/SimpleSend.nc
    // to see what funcitons we need to implement.
    provides interface SimpleSend;

    uses interface Queue<sendInfo*>;
    uses interface Pool<sendInfo>;

    uses interface Timer<TMilli> as sendTimer;

    uses interface Packet;
    uses interface AMPacket;
    uses interface AMSend;

    uses interface Random;
}

implementation{
    uint16_t sequenceNum = 0;
    bool busy = FALSE;
    message_t pkt;

    pack sentMsg;

    error_t send(uint16_t src, uint16_t dest, pack *message);

    void postSendTask(){
        if(call sendTimer.isRunning() == FALSE){
            call sendTimer.startOneShot( (call Random.rand16() %300));
        }
    }

    command error_t SimpleSend.send(pack msg, uint16_t dest) {
        if(!call Pool.empty()){
            sendInfo *input;

            input = call Pool.get();
            input->packet = msg;
            input->dest = dest;

            sentMsg = msg;

            call Queue.enqueue(input);

            postSendTask();

            return SUCCESS;
        }
        return FAIL;
    }

    task void sendBufferTask(){
        if(!call Queue.empty() && !busy){
            sendInfo *info;
            info = call Queue.head();

            // Attempt to send it.
            if(SUCCESS == send(info->src,info->dest, &(info->packet))){
                call Queue.dequeue();
                call Pool.put(info);
            }
        }

        if(!call Queue.empty()){
            postSendTask();
        }
    }

    event void sendTimer.fired(){
        post sendBufferTask();
    }

    error_t send(uint16_t src, uint16_t dest, pack *message){
        if(!busy){
            pack* msg = (pack *)(call Packet.getPayload(&pkt, sizeof(pack) ));

            *msg = *message;

            // Attempt to send the packet.
            if(call AMSend.send(dest, &pkt, sizeof(pack)) ==SUCCESS){
                busy = TRUE;
                return SUCCESS;
            } else {
                dbg(GENERAL_CHANNEL,"The radio is busy, or something\n");
                return FAIL;
            }
        } else {
            dbg(GENERAL_CHANNEL, "The radio is busy");
            return EBUSY;
        }

        dbg(GENERAL_CHANNEL, "FAILED!?");
        return FAIL;
    }

    event void AMSend.sendDone(message_t* msg, error_t error){
        if(&pkt == msg){
            busy = FALSE;
            postSendTask();

            signal SimpleSend.sendDone(sentMsg, error); // 'sentMsg' is the 'pack' you sent
        }
    }
}
