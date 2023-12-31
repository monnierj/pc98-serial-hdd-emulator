[bits 16]
[cpu 8086]
[org 0x100]

%include "config.inc"

; See client.asm to know where .bss begins, how many bytes it spans,
; and that sum gives the next constant value
BIOS_PATCH_LENGTH: equ 512+64
BIOS_PATCH_PARAGRAPH_COUNT: equ (BIOS_PATCH_LENGTH >> 4) + 1
BIOS_PATCH_BASE_OFFSET: equ (256+144)	; Must be multiple of 16, and greater than the executable size
RELOCATOR_PARAGRAPH_COUNT: equ (BIOS_PATCH_BASE_OFFSET >> 4) + 1

main:
	; Print the welcome message
	mov ah, 0x09
	mov dx, msg_welcome
	int 0x21

	; Copy the BIOS patch from the GVRAM to the main memory
	; ES is already pointing to the current code segment, but we need to
	; make DS point to the GVRAM segment currently holding the BIOS patch.
	mov ax, BIOS_PATCH_SEGMENT
	mov ds, ax

	xor si, si	; Copy the BIOS patch from the first location
	mov di, BIOS_PATCH_BASE_OFFSET	; Do not overwrite this program - for now.
	mov cx, BIOS_PATCH_LENGTH

	rep movsb

	; We've successfully copied the BIOS patch. Now, fix the interrupt vector.
	xor ax, ax
	mov es, ax

	;-------- INTERRUPT-SENSITIVE SECTION --------
	cli
	xor ax, ax
	mov [es:DISK_BIOS_IVT_ENTRY_IP], ax

	push cs
	pop ax

	; We now have the program segment in AX. Add (relocated BIOS patch offset >> 4) to it
	; to know the final BIOS patch segment
	clc
	add ax, (BIOS_PATCH_BASE_OFFSET >> 4)
	mov [es:DISK_BIOS_IVT_ENTRY_CS], ax
	sti
	;-------- END OF INTERRUPT-SENSITIVE SECTION --------

	push cs
	pop ds

	;  ; Write a victory message
	mov ah, 0x09
	mov dx, msg_done
	int 0x21

	;  ; Terminate and stay resident.
	mov ax, 0x3100
	mov dx, (BIOS_PATCH_PARAGRAPH_COUNT + RELOCATOR_PARAGRAPH_COUNT)
	int 0x21

; Message catalog
msg_welcome: db "pushing PC-9801 serial disk emulator patch to conventional memory...$"
msg_done: db " done!", 13, 10, "$"
;msg_allocation_failed: db "Failed to allocate memory, system stability compromised!\r\n$"
