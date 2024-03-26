# pc98-serial-hdd-emulator

A three-parts projects that allows bootstraping a PC-9801 to a 16 bits OS by simulating a fixed disk drive:

- a "client", written in assembly, that resides in the PC-9801 RAM
- a "server", written in Python, that answers client's requests over a serial port
- a "client mover", written in assembly too, that moves the client in a properly allocated memory area in MS-DOS

The simulated disk drive data is read from a modern computer running a simple Python program.

The goal of this project is to reach a bit more capable than the BASIC interpreter to test and fix those machines.

While all of this works, this is currently vastly unfinished, and in a dire need of documentation.
