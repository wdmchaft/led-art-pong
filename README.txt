Welcome to the LED-Art pong repository.

This is a project to create a pong game using RGB LED lights. The (32) LEDlights simulate a ball being pinged and ponged back and forth.

The LED lights are controlled by a small computer board that is programmed in assembler. The software for the board interprets the commands that are sent by the game server.

The game server is an Erlang application (running on a small Linux computer like the FOXboard, Gumstix or Beagleboard for instance) that controls the gameplay.

The Erlang software allows the game to be distributed, e.g. two players can be playing together at different locations, each with their own LED lights.

Communication between the components is mostly done using TCP/IP. The LED controller board is however addressed using a serial port. To communicate with the LED controller we use ser2net, a small component that creates a gateway between an network port and a serial port on the same machine.

There is a simulator for the LED lights board that runs on a Mac in de LEDsimulator folder.

End of README.
