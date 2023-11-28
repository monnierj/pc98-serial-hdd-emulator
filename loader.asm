[bits 16]
[org 0xF000]
[cpu 8086]

LOADER_SEGMENT: equ 0xA000
DISK_BIOS_INTERRUPT: equ 0x1B

main:
	push ax
	mov ax, LOADER_SEGMENT
	mov ds, ax

	; Reset VRAM, white text, not secret mode, fill screen with blank spaces
	mov ah, 0x16
	mov dx, 0xE120
	int 0x18

	mov si, greeting_msg
	call puts

	pop ax
	retf 2	; temporary, we're not expected to return to BASIC.

puts:
	; Writes a static message on-screen. Only supports US-ASCII strings.
	; DS:SI -> source address of a C string.
	push ax
	push es

	; Set ES to the text VRAM segment
	mov ax, 0xA000
	mov es, ax

	; FIXME: keep track of DI
	xor di, di

	xor ax, ax

_puts_charwrite:
	lodsb

	cmp al, 0
	jz _puts_end

	stosw
	loop _puts_charwrite

_puts_end:
	pop es
	pop ax
	ret

; Messages catalog
%defstr _greeting_msg PC9801 Serial HDD emulator (GIT_COMMIT_REF)
greeting_msg: db _greeting_msg, 0
