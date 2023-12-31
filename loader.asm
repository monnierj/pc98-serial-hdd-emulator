[bits 16]
[org 0xF000]
[cpu 8086]

%include "config.inc"

CONSOLE_LINE_LENGTH: equ 160	; 80 characters, two bytes per character


main:
	push ax
	push cs
	pop ds

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
	rep movsb

	; Patch the Interrupt Vector Table
	mov si, patching_interrupt_msg
	call puts

	cli	; Disable interrupts...
	push ds

	xor ax, ax
	mov ds, ax

	; Copy BIOS-provided interrupt 0x1B handler in our client.
	mov ax, [DISK_BIOS_IVT_ENTRY_IP]
	mov [es:0x0009], ax

	mov ax, [DISK_BIOS_IVT_ENTRY_CS]
	mov [es:0x000B], ax

	; Replace original vector values
	xor ax, ax
	mov [DISK_BIOS_IVT_ENTRY_IP], ax ; Interrupt handler offset is 0

	mov ax, BIOS_PATCH_SEGMENT
	mov [DISK_BIOS_IVT_ENTRY_CS], ax ; Interrupt handler segment

	; Edit BIOS work area to simulate a proper disk boot...

	; Update Boot drive ID. "Undocumented PC-9801" tells that DA/UA 0xh is not
	; supported, use 8xh instead
	mov [BIOS_BOOT_DISK_ID], byte DRIVE_ID

	; Mark SASI Disk 80h/00h as present. This is needed to boot DOS,
	; or else the "msdos.sys 読み込み時にエラーが発生しました" error
	; will appear
	or [BIOS_DISK_EQUIP_HI], byte 0x01

	pop ds
	sti	; Restore interrupts.

	; Initialize serial port through the BIOS patch
	mov ax, (0x03 << 8) + DRIVE_ID
	int 0x1B

	; Load the two first sectors of the disk to the conventional boot sector offset
	mov ax, BOOT_SECTOR_SEGMENT
	mov es, ax
	xor bp, bp	; Data is stored in ES:BP

	mov bx, 512	; Load two sectors
	xor cx, cx	; Reset sector index
	xor dx, dx	; Reset both sector and head indexes

	mov ax, (0x06 << 8) + (DRIVE_ID & 0x7F)
	int 0x1B

	jc _boot_sector_loading_failed

	mov si, jumping_to_boot_sector_msg
	call puts

	; The boot sector was loaded without issues, we can now run it.
	; Prepare final registers values before jumping to the bootloader code
	mov ax, BOOT_SECTOR_SEGMENT
	mov es, ax	; Make ES point to the boot sector segment

	mov ax, 0x0020
	mov ss, ax	; Change stack segment

	xor ax, ax	; Reset general purpose registers
	;mov bx, ax
	mov cx, ax
	mov dx, ax
	mov ds, ax	; DS should point to segment 0
	mov sp, 0xFFFE	; Reset stack position

	mov bx, DRIVE_SECTOR_LENGTH	; We have 256 bytes sectors on this disk
	mov al, DRIVE_ID	; AL holds the current drive ID

	; Call to the bootloader, so that we have a stack structure
	call BOOT_SECTOR_SEGMENT:0x0000

	; We somehow returned from the bootloader. Things aren't good.
	push cs
	pop ds	; Restore DS...

	mov si, returned_from_bootloader_msg	; display an error message...
	call puts

	cli	; And stop the machine.
	hlt
	jmp $

_boot_sector_loading_failed:
	mov si, boot_sector_loading_failed_msg
	call puts
	cli
	jmp $	; This is the point of no return, the machine is considered crashed.

puts:
	; Writes a static message on-screen. Only supports US-ASCII strings.
	; DS:SI -> source address of a C string.
	push ax
	push dx
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

	; Update cursor position

	mov ah, 0x13
	mov dx, di
	inc dx
	int 0x18


	pop es
	pop dx
	pop ax
	ret

; Messages catalog
%defstr _greeting_msg PC9801 Serial HDD emulator (GIT_COMMIT_REF)
greeting_msg: db _greeting_msg, 13, 0
patching_interrupt_msg: db "Patching interrupt vector...", 13, 0
jumping_to_boot_sector_msg: db "Now running boot sector!", 13, 0
boot_sector_loading_failed_msg: db "Failed to load boot sector, aborting.", 13, 0
returned_from_bootloader_msg: db "Returned from bootloader, aborting.", 0

; Global variables
tvram_cur_line_start_ptr: dw 0
tvram_cur_char_ptr: dw 0

; BIOS patch is imported here.
bios_patch: incbin "client.bin"

bios_patch_end:
