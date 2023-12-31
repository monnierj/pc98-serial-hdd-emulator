; pc98-serial-hdd-emulator - emulator client / BIOS patch
[bits 16]
[org 0x0000]
[cpu 8086]

%include "config.inc"

BIOS_STATUS_CODE_EQUIPMENT_CHECK: equ 0x40
BIOS_STATUS_CODE_NOT_WRITABLE: equ 0x70

EMULATED_DRIVE_CYLINDER_COUNT: equ 153
EMULATED_DRIVE_SECTOR_COUNT: equ 33
EMULATED_DRIVE_HEAD_COUNT: equ 4

EMULATOR_READ_COMMAND_OPCODE: equ 0x01
EMULATOR_READ_RESPONSE_OPCODE: equ 0x81

UART_DATA_PORT: equ 0x30
UART_CMD_PORT: equ 0x32


[section .text]
_entry:
	; This is where we're dropped after an "int 0x1b" instruction.
	; We have caller flags, CS and IP pushed in that order onto the stack

	; Check if the interrupt was made for our drive
	; That will change FLAGS, but since the "PC9800 Technical Data Book - BIOS"
	; book doesn't tell that input flags are used, we will not store them.
	cmp al, DRIVE_ID
	jz client_main

	cmp al, (DRIVE_ID & 0x7F) ; MSB means LBA access mode
	jz client_main

	; The call is directed to a drive that we aren't shadowing.
_original_interrupt_handler_jump:
	jmp word 0:0


client_main:
	; The handler are sorted in most-to-least-probable-call order.

	cmp ah, 0x06
	jz read_handler

	cmp ah, 0x04
	jz sense_handler

	; Special case of SENSE: if SENSE is called and the most significant
	; bit is set, we have to return the drive geometry.
	cmp ah, 0x84
	jz extended_sense_handler

	cmp ah, 0x03
	jz initialize_handler

	cmp ah, 0x07
	jz recalibrate_handler

	; We didn't find a valid handler. Return a more a less valid error code.

	push bp
	push cx
	mov bp, command_buffer

	mov [cs:bp], byte 0x03
	mov [cs:bp+1], word ax
	mov cx, 3
	call uart_send_packet

	pop cx
	pop bp

	mov ah, BIOS_STATUS_CODE_EQUIPMENT_CHECK
	jmp error_return


; A stub handler that simulates a successful call (CF cleared)
success_stub:
	mov ax, DRIVE_ID	; AH: status (0 is OK), AL: drive ID

; Function postlude that clears CF, indicating that the function was successful
success_return:
	push bp
	mov bp, sp
	and byte [bp+6], ~0x01	; Clear the CF bit in the caller FLAGS
	pop bp
	iret

; A stub handler that simulates "disk not writable" errors
not_writable_stub:
	mov ax, (BIOS_STATUS_CODE_NOT_WRITABLE << 8) + DRIVE_ID

; Function postlude that sets CF, indicating an error in the function
error_return:
	push bp
	mov bp, sp
	or byte [bp+6], 0x01	; Set the CF bit in the caller FLAGS
	pop bp
	iret

; AH=0x03 handler - INITIALIZE
initialize_handler:
	call uart_init

	call wait_some

	xor ah, ah
	jmp success_return

; AH=0x04/0x84 handler - SENSE
; Returns what do we know about the fixed disk (size and geometry)
; Output registers:
; AH -> Four lowest bits tell the drive size (0000 -> 5MB)
; If input AH.7 is set,
; BX -> Sector length
; CX -> Cylinder count
; DH -> Heads count
; DL -> Sector per cylinder count
extended_sense_handler:
	; If set, we come from the 0x84 Sense+Geometry code: update BX/CX/DX to the
	; expected values
	mov bx, 256
	mov cx, EMULATED_DRIVE_CYLINDER_COUNT
	mov dh, EMULATED_DRIVE_HEAD_COUNT
	mov dl, EMULATED_DRIVE_SECTOR_COUNT

	push ax
	push ds

	xor ax, ax
	mov ds, ax

	mov [0x586], word 0x0000
	mov [0x588], word 0xe44e	; store in big endian...

	pop ds
	pop ax

sense_handler:
	push bp	; Sense debug section
	push cx
	mov bp, command_buffer
	mov [cs:bp], byte 0x02
	mov [cs:bp+1], word ax
	mov cx, 3
	call uart_send_packet
	pop cx
	pop bp


	mov ah, 0x00	; bit 4 is set to indicate we're in RO mode
	jmp success_return

recalibrate_handler:
	mov ah, 0x00
	jmp success_return

; AH=0x06 handler - READ
; Input registers:
; BX -> Sector count
; CX -> Start cylinder index
; DH -> Head index
; DL -> Sector index
; ES:BP -> Data buffer
read_handler:
	push ax
	push bx
	push cx
	push dx
	push bp

	; Build the READ command
	mov bp, command_buffer

	mov [cs:bp], 	byte EMULATOR_READ_COMMAND_OPCODE
	mov [cs:bp+1],	al
	mov [cs:bp+2],	word bx
	mov [cs:bp+4],	word cx
	mov [cs:bp+6],	word dx

	; Send the READ command
	mov cx, 8
	call uart_send_packet

	; We can now wait for the command bytes.
	; Check that we do have a response for our READ command...
	call uart_read_byte
	cmp al, EMULATOR_READ_RESPONSE_OPCODE
	jnz read_handler.failure

	; ... and that the status byte is cleared.
	call uart_read_byte
	cmp al, 0
	jnz read_handler.failure

	; Read the byte count word
	call uart_read_byte
	mov cl, al
	call uart_read_byte
	mov ch, al

	pop bp
	push bp

	; And, finally, enter the data read loop:
read_handler.loop:
	call uart_read_byte
	mov [es:bp], al
	inc bp
	loop read_handler.loop

	pop bp
	pop dx
	pop cx
	pop bx
	pop ax

	; Clean the status byte in AH, then return success
	xor ah, ah
	jmp success_return

read_handler.failure:
	pop bp
	pop dx
	pop cx
	pop bx
	pop ax
	mov ah, BIOS_STATUS_CODE_EQUIPMENT_CHECK
	jmp error_return


; UART-related functions

; uart_init - sets up the built-in Intel 8251 UART
uart_init:
	; Perform a full reset of the UART, as explained in the datasheet

	out UART_CMD_PORT, al	; Write three times 0x00 to the UART command port
	call wait_some
	out UART_CMD_PORT, al
	call wait_some
	out UART_CMD_PORT, al
	call wait_some

	mov al, 13	; 8MHz bus on V mode, clock prescaler is 16: this will give us 9600bps
	out 0x75, al
	xor al, al
	out 0x75, al	; Ghetto reset i8253 channel 2, which drivers the baud generator
	call wait_some

	; Do an internal reset
	mov al, 0x40
	out UART_CMD_PORT, al
	call wait_some

	; We're finally in the MODE state. Set up asynchronous mode.
	mov al, 0x4E	; 1 stop bit, no parity, 8 bits of data, system clock is x16 the baud rate
	out UART_CMD_PORT, al
	call wait_some

	; And reset the possible errors flags, while enabling the receiver and transmitter
	mov al, 0x15
	out UART_CMD_PORT, al
	call wait_some

	ret

; uart_send_packet - send a "packet" of bytes through the UART. Packet data must be
; stored in the command buffer.
; Input registers:
; CX -> packet length, in bytes.
uart_send_packet:
	push ax
	push si

	mov si, command_buffer
_send_loop:
	; Loop until TxEMPTY and TxRDY are set
	in al, UART_CMD_PORT
	and al, 0x04
	jz _send_loop

	cs lodsb
	out UART_DATA_PORT, al

	loop _send_loop

	pop si
	pop ax
	ret

; uart_read_byte - blocks until a byte is read from the onboard UART.
; Output registers:
; AL -> read byte
uart_read_byte:
	; Make /RTS low, so that hardware flow control works as expected.
	mov al, 0x25	; RTS flag set, TxEN/RxEN set
	out UART_CMD_PORT, al

	in al, UART_CMD_PORT
	and al, 0x02
	jz uart_read_byte

	in al, UART_DATA_PORT

	push ax
	mov al, 0x05	; RTS flag reset, TxEN/RxEN still set
	out UART_CMD_PORT, al
	pop ax

	ret

wait_some:
	push cx
	mov cx, 0x4000

_ws_loop:
	nop
	loop _ws_loop

	pop cx
	ret

[section .bss vstart=512]
command_buffer: resb 64
