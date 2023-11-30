; Disk emulator configuration - default settings are perfectly fine, but some things may
; be changed here.

; Pointer to the high byte for the "Equipped disk drives" BIOS variable
BIOS_DISK_EQUIP_HI: equ 0x55D
; Pointer to the "boot disk ID" BIOS variable.
BIOS_BOOT_DISK_ID: equ 0x584

BOOT_SECTOR_SEGMENT: equ 0x1FE0

; Byte count for one sector
DRIVE_SECTOR_LENGTH: equ 256

; Sets the UA/DA byte that we'll hook.
DRIVE_ID: equ 0x80

