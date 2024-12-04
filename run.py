from TestSim import TestSim


def main():
    # Get simulation ready to run.
    s = TestSim()

    # Before we do anything, lets simulate the network off.
    s.runTime(1)

    # Load the the layout of the network.
    s.loadTopo("example.topo")

    # Add a noise model to all of the motes.
    s.loadNoise("meyer-heavy.txt")

    # Turn on all of the sensors.
    s.bootAll()

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    s.runTime(10)

    s.cmdTestServer(1, 80)
    s.runTime(30)

    s.cmdTestClient(2, 1, 20, 80, 100)
    s.runTime(60)

    s.cmdClientClose(2, 1, 20, 80)
    s.runTime(60)

    s.runTime(30)

if __name__ == '__main__':
    main()
