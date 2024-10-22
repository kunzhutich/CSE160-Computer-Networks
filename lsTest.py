from TestSim import TestSim

def main():
    s = TestSim()

    s.runTime(1)

    # Load your topology
    s.loadTopo("example.topo")

    # Load the noise model
    s.loadNoise("no_noise.txt")

    # Boot all motes
    s.bootAll()

    # Add channels for debugging
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel("LinkState")
    s.addChannel("IP")
    s.addChannel("Flooding")

    s.runTime(5)

    # Test route dump command
    s.routeDMP(1)  # Request node 1 to print its routing table

    s.runTime(2)

    # Send a ping from node 1 to node 9
    s.ping(1, 9, "Hello, Node 9")

    s.runTime(10)

if __name__ == '__main__':
    main()
