from argparse import ArgumentParser
import os
import struct

import serial


EMULATOR_READ_COMMAND_OPCODE = 0x01
EMULATOR_READ_RESPONSE_OPCODE = 0x81

EMULATOR_GEOMETRY_COMMAND_OPCODE = 0x02
EMULATOR_GEOMETRY_RESPONSE_OPCODE = 0x82


HDI_HEADER_FORMAT = "<8L"

READ_COMMAND_FORMAT = "<BBHHBB"

SERIAL_PORT_SPEED = 19200


class HDIHeader:
    """
    HDI disk image header
    """

    def __init__(self, header_size, data_size, bytes_per_sector, sectors, heads, cylinders):
        self.header_size = header_size
        self.data_size = data_size
        self.bytes_per_sector = bytes_per_sector
        self.sectors = sectors
        self.heads = heads
        self.cylinders = cylinders
        self.total_sectors = data_size // bytes_per_sector

    @classmethod
    def from_bytes(cls, raw_bytes) -> "HDIHeader":
        header_dwords = struct.unpack(HDI_HEADER_FORMAT, raw_bytes)
        return cls(*header_dwords[2:])

    def get_absolute_address_from_chs(self, c, h, s) -> int:
        return s + (h * self.sectors) + (c * self.heads * self.sectors)


def get_argument_parser():
    ap = ArgumentParser("disk_emulator")
    ap.add_argument("disk_image", help="Path to the emulated HDI disk image")
    ap.add_argument("serial_port", help="Path to the serial port where the PC-9801 is connected")

    return ap


def handle_read_command(command_buffer, disk_data, image_header, serial_port):
    command_items = struct.unpack(READ_COMMAND_FORMAT, bytes(command_buffer))
    drive_id = command_items[1]
    print(
        f"- Got READ command, drive {drive_id:02x}, {command_items[2]} bytes, CX/DL/DH were "
        f"{command_items[3]}/{command_items[4]}/{command_items[5]}"
    )

    sector_count = command_items[2] // 256

    if drive_id & 0x80:
        print(f"drive {drive_id:02x}, using CHS mode")
        base_offset = image_header.get_absolute_address_from_chs(command_items[3], command_items[4], command_items[5]) * image_header.bytes_per_sector
    else:
        print(f"drive {drive_id:02x}, using LBA mode")
        base_offset = ((command_items[4] << 16) + command_items[3]) * image_header.bytes_per_sector

    data_size = sector_count * image_header.bytes_per_sector

    end_offset = base_offset + data_size

    print(f"Sending {data_size} bytes from offset {base_offset:08x} to PC-9801...")
    print(f"{base_offset:08x}->{end_offset:08x}")

    response_base = struct.pack(
        "<BBH", EMULATOR_READ_RESPONSE_OPCODE, 0x00, data_size
    )
    serial_port.write(response_base)

    print("sent command data")
    serial_port.write(disk_data[base_offset:end_offset])
    print("sent data")


def handle_geometry_command(command_buffer, image_header, serial_port):
    print(f"- Got GEOMETRY command, AL={command_buffer[1]:02x}")
    response = struct.pack(
        "<BBLHBB",
        EMULATOR_GEOMETRY_RESPONSE_OPCODE,
        0x00,   # Status=OK
        image_header.total_sectors,
        image_header.cylinders,
        image_header.heads,
        image_header.sectors
    )

    serial_port.write(response)


def handle_other_command(command_buffer, image_header, serial_port):
    print(f"- Got UNSUPPORTED command, AH={command_buffer[2]:02x}, AL={command_buffer[1]:02x}")


def run_server_loop(disk_data, image_header, serial_port):
    command_buffer = []

    while True:
        cur_bytes = serial_port.read(1)
        if cur_bytes is None:
            continue

        cur_byte = cur_bytes[0]

        print(f"- Read byte {cur_byte:02x}")

        command_buffer.append(cur_byte)

        if len(command_buffer) == 8 and command_buffer[0] == EMULATOR_READ_COMMAND_OPCODE:
            handle_read_command(command_buffer, disk_data, image_header, serial_port)
            command_buffer.clear()

        if len(command_buffer) == 2 and command_buffer[0] == 0x02:
            handle_geometry_command(command_buffer, image_header, serial_port)
            command_buffer.clear()

        if len(command_buffer) == 3 and command_buffer[0] == 0x03:
            handle_other_command(command_buffer, image_header, serial_port)
            command_buffer.clear()


def main():
    args = get_argument_parser().parse_args()

    with open(args.disk_image, "rb") as f:
        image_header = HDIHeader.from_bytes(f.read(32))
        # Go back to the start of the image, and jump just after the header section.
        f.seek(image_header.header_size, os.SEEK_SET)
        disk_data = f.read()

    print(
        f"Emulated disk has C/H/S structure {image_header.cylinders}/"
        f"{image_header.heads}/{image_header.sectors}, and uses "
        f"{image_header.bytes_per_sector} bytes sectors"
    )
    print(f"Read {len(disk_data)} bytes from disk image")

    try:
        with serial.Serial(
            args.serial_port, SERIAL_PORT_SPEED, parity=serial.PARITY_NONE, rtscts=True, dsrdtr=False
        ) as serial_port:
            print(f"Listening on {args.serial_port}...")
            run_server_loop(disk_data, image_header, serial_port)
    except KeyboardInterrupt:
        print("Stopping disk emulator")


if __name__ == "__main__":
    main()
