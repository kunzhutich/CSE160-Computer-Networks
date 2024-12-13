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
    s.addChannel(s.CHAT_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    # print("Letting network initialize...")
    # s.runTime(20)

    # print("Starting chat server on node 1...")
    # s.setAppServer(1)
    # s.runTime(20)

    # print("Starting client on node 2...")
    # s.setAppClient(2)
    # s.runTime(20)
    
    # print("Sending hello from node 2...")
    # s.hello(2, "alice", 50)
    # s.runTime(30)
    
    # print("Testing simple message...")
    # s.relayMsg(2, "Test message")
    # s.runTime(30)

    # Let the network stabilize
    print("Letting network initialize...")
    s.runTime(20)

    # Start server
    print("Starting chat server on node 1...")
    s.setAppServer(1)
    s.runTime(10)  # Give server time to start

    # Start and connect first client
    print("Starting first client (alice) on node 2...")
    s.setAppClient(2)
    s.runTime(5)  # Wait for client initialization
    print("Connecting alice...")
    s.hello(2, "alice", 50)
    s.runTime(10)  # Give time for connection to establish

    # Start and connect second client
    print("Starting second client (bob) on node 3...")
    s.setAppClient(3)
    s.runTime(5)
    print("Connecting bob...")
    s.hello(3, "bob", 51)
    s.runTime(10)

    # Test chat functionality
    print("Testing chat functionality...")
    s.runTime(5)  # Wait a bit before starting tests
    
    print("Alice sending broadcast message...")
    s.relayMsg(2, "Hello everyone!")
    s.runTime(5)
    
    print("Alice whispering to bob...")
    s.whisper(2, "bob", "Hey Bob!")
    s.runTime(5)
    
    print("Requesting user list...")
    s.listUsers(2)
    s.runTime(5)


if __name__ == '__main__':
    main()
