[bits 16]
[org 0xF000]
[cpu 8086]

CONSOLE_LINE_LENGTH: equ 160	; 80 characters, two bytes per character
DISK_BIOS_INTERRUPT: equ 0x1B
DISK_BIOS_IVT_ENTRY_IP: equ DISK_BIOS_INTERRUPT << 2
DISK_BIOS_IVT_ENTRY_CS: equ DISK_BIOS_IVT_ENTRY_IP + 2
LOADER_SEGMENT: equ 0xA000	; The loader is held into the text VRAM.
BIOS_PATCH_SEGMENT: equ 0x9F80	; Store the BIOS patch two kilobytes below text VRAM.

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

	; Copy the BIOS patch to its final location.
	mov ax, BIOS_PATCH_SEGMENT
	mov es, ax

	mov si, bios_patch
	xor di, di
	mov cx, (bios_patch_end - bios_patch)
_patch_copy_loop:
	lodsb
	stosb
	loop _patch_copy_loop

	; Patch the Interrupt Vector Table
	; TODO: keep the previous value somewhere, we're patching, not replacing things
	mov si, patching_interrupt_msg
	call puts

	cli	; Disable interrupts...
	push ds

	xor ax, ax
	mov ds, ax

	mov [DISK_BIOS_IVT_ENTRY_IP], ax ; Interrupt handler offset is 0

	mov ax, BIOS_PATCH_SEGMENT
	mov [DISK_BIOS_IVT_ENTRY_CS], ax ; Interrupt handler segment

	pop ds
	sti	; Restore interrupts.


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

	mov di, [tvram_cur_char_ptr]

	xor ax, ax

_puts_charwrite:
	lodsb

	cmp al, 13	; Line Feed handler
	jz _puts_lf

	cmp al, 0	; NULL character handler
	jz _puts_end

	stosw	; We've got a normal ASCII character, just print it out.
	loop _puts_charwrite

_puts_lf:
	; Set "current line start pointer" to the start of the next line, and use that
	; new value as the current character position
	mov di, [tvram_cur_line_start_ptr]
	add di, CONSOLE_LINE_LENGTH
	mov [tvram_cur_line_start_ptr], di

	jmp _puts_charwrite

_puts_end:
	mov [tvram_cur_char_ptr], di
	pop es
	pop ax
	ret

; Messages catalog
%defstr _greeting_msg PC9801 Serial HDD emulator (GIT_COMMIT_REF)
greeting_msg: db _greeting_msg, 13, 0
patching_interrupt_msg: db "Patching interrupt vector...", 13, 0

; Global variables
tvram_cur_line_start_ptr: dw 0
tvram_cur_char_ptr: dw 0

; BIOS patch is imported here.
; For now, we'll just implement a stub interrupt handler
bios_patch:
	push bp
	mov bp, sp
	or word [bp+6], 1	; Manually set carry on the saved flags
	pop bp
	iret

bios_patch_end:
