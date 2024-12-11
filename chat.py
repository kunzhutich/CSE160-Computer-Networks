from TestSim import TestSim


def main():
    # Get simulation ready to run.
    s = TestSim()

    # Before we do anything, lets simulate the network off.
    s.runTime(1)

    # Load the the layout of the network.
    s.loadTopo("long_line.topo")

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt")

    # Turn on all of the sensors.
    s.bootAll()

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    # s.addChannel(s.TRANSPORT_CHANNEL)

    # Start server on node 1
    s.runTime(20)
    s.setAppServer(1)
    
    # Start clients on nodes 2 and 3
    s.runTime(20)
    s.setAppClient(2)
    s.setAppClient(3)
    
    # Connect clients
    s.runTime(20)
    s.sendCMD(s.CMD_HELLO, 2, "user1 50")
    s.sendCMD(s.CMD_HELLO, 3, "user2 51")

    # Connect clients (alternative way using helper function)
    s.hello(2, "user1", 50)
    s.hello(3, "user2", 51)

    # Send messages
    s.runTime(10)
    s.msg(2, "Hello everyone!")
    s.runTime(10)
    s.whisper(3, "user1", "Hey there!")
    s.runTime(10)
    s.listUsers(2)

if __name__ == '__main__':
    main()
