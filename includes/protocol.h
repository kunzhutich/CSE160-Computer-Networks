//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedDate: 2014-06-16 13:16:24 -0700 (Mon, 16 Jun 2014) $

#ifndef PROTOCOL_H
#define PROTOCOL_H

// should put the following in another header later
#define SYN 0x02
#define ACK 0x10
#define FIN 0x01
#define PSH 0x08

//PROTOCOLS
enum{
	PROTOCOL_PING = 0,
	PROTOCOL_PINGREPLY = 1,
	PROTOCOL_LINKSTATE = 2,
	PROTOCOL_NAME = 3,
	PROTOCOL_TCP= 4,
	PROTOCOL_DV = 5,
	PROTOCOL_CMD = 99
};



#endif /* PROTOCOL_H */
