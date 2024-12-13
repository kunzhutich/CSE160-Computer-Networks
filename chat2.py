from TestSim import TestSim


def main():
    # Get simulation ready to run.
    s = TestSim()

    # Before we do anything, lets simulate the network off.
    s.runTime(1)

    # Load the the layout of the network.
    s.loadTopo("example.topo")

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt")

    # Turn on all of the sensors.
    s.bootAll()

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.CHAT_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    # Let the network stabilize
    s.runTime(20)

    # Start server
    print("Starting chat server on node 1...")
    s.setAppServer(1)
    s.runTime(10)  # Give server time to start

    # Start and connect first client (with port 50)
    s.setAppClient(2, 50)
    s.runTime(10)
    s.hello(2, "alice")
    s.runTime(10)

    # Start and connect second client (with port 51)
    s.setAppClient(3, 51)
    s.runTime(10)
    s.hello(3, "bob")
    s.runTime(10)
    
    s.setAppClient(4, 52)
    s.runTime(10)
    s.hello(4, "john")
    s.runTime(10)
    s

    # Test chat functionality
    s.runTime(10)  # Wait a bit before starting tests
    
    s.relayMsg(2, "Hello everyone!\r\n")
    s.runTime(10)
    
    s.whisper(2, "bob", "Hey Bob!\r\n")
    s.runTime(10)
    

    s.listUsers(2)
    s.runTime(10)


if __name__ == '__main__':
    main()
