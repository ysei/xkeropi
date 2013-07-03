; Make68K - V0.17 - Copyright 1998, Mike Coates (mcoates@mame.freeserve.co.uk)
;                               & Darren Olafson (deo@mail.island.net)

; Changed for WinX68k by Kenjo
;   - Added BusError / Adress Error
;   - Changed inc/dec number to 2 in byte access from/to -(A7)/(A7)+
;   - Changed main loop style (slower ... but for DMA and "Trace exception")
;     ... Not yet done :-p

		 BITS 32

%define	_OP_ROM			OP_ROM
%define	_M68KRUN		M68KRUN
%define	_M68KRESET		M68KRESET
%define	_m68000_ICount		m68000_ICount
%define	_m68000_ICountBk	m68000_ICountBk
%define	_ICount			ICount
%define	_regs			regs
%define	AdrError		@AdrError@8
%define	BusError		@BusError@8

		 GLOBAL OP_f000
		 GLOBAL Exception

		 GLOBAL _M68KRUN
		 GLOBAL _M68KRESET
		 GLOBAL _m68000_ICount
		 GLOBAL _m68000_ICountBk
		 GLOBAL ICount
		 GLOBAL _regs
		 GLOBAL BusError
		 GLOBAL AdrError

		 EXTERN @cpu_readmem24@4
		 EXTERN @cpu_readmem24_word@4
		 EXTERN @cpu_readmem24_dword@4

		 EXTERN @cpu_writemem24@8
		 EXTERN @cpu_writemem24_word@8
		 EXTERN @cpu_writemem24_dword@8
		 EXTERN @cpu_setOPbase24@4

; Vars Mame declares / needs access to

		 EXTERN _OP_ROM
		 SECTION .text


;
; M68KEM MAIN
;

_M68KRESET:
		 pushad

; Build Jump Table (not optimised!)

		 lea   edi,[OPCODETABLE]		; Jump Table
		 lea   esi,[COMPTABLE]		; RLE Compressed Table
		 mov   ebp,[esi]
		 add   esi,byte 4
RESET0:
		 mov   eax,[esi]
		 mov   ecx,eax
		 and   eax,0ffffffh
		 add   eax,ebp
		 add   esi,byte 4
		 shr   ecx,24
		 jne   short RESET1
		 movzx ecx,word [esi]		; Repeats
		 add   esi,byte 2
		 jecxz RESET2		; Finished!
RESET1:
		 mov   [edi],eax
		 add   edi,byte 4
		 dec   ecx
		 jnz   short RESET1
		 jmp   short RESET0
RESET2:
		 popad
		 ret

		 ALIGN 4

_M68KRUN:
		 pushad
		 mov   esi,[R_PC]
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
; Check for Interrupt waiting

		 test  [R_IRQ],byte 07H
		 jne   near interrupt

IntCont:
		 or    dword [_m68000_ICount],0
		 js    short MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]
		 ALIGN 4

MainExit:
		 mov   [R_PC],esi		; Save PC
		 mov   [R_CCR],edx
		 test  byte [R_SR_H],20H
		 mov   eax,[R_A7]		; Get A7
		 jne   short ME1		; Mode ?
		 mov   [R_USP],eax		;Save in USP
		 jmp   short MC68Kexit
ME1:
		 mov   [R_ISP],eax
MC68Kexit:
		 popad
		 ret
		 ALIGN 4

; Interrupt check

interrupt:
		 mov   eax,[R_IRQ]
		 and   eax,byte 07H
		 cmp   al,7		 ; Always take 7
		 je    short procint

		 mov   ebx,[R_SR_H]		; int mask
		 and   ebx,byte 07H
		 cmp   eax,ebx
		 jle   near IntCont

		 ALIGN 4

procint:
		 and   byte [R_IRQ],78h		; remove interrupt & stop

		 push  eax		; save level

		 mov   ebx,eax
		 mov   [R_CCR],edx
		 mov   ecx, eax		; irq line #
		 call  dword [R_IRQ_CALLBACK]	; get the IRQ level
		 mov   edx,[R_CCR]
		 test  eax,eax
		 jns   short AUTOVECTOR
		 mov   eax,ebx
		 add   eax,byte 24		; Vector

AUTOVECTOR:

		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_0ffff_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_0ffff_Bank:
		 pop   eax		; set Int mask
		 mov   bl,byte [R_SR_H]
		 and   bl,0F8h
		 or    bl,al
		 mov   byte [R_SR_H],bl

		 jmp   IntCont

		 ALIGN 4

Exception:
		 push  edx		; Save flags
		 and   eax,0FFH		; Zero Extend IRQ Vector
		 push  eax		; Save for Later
		 mov   al,[exception_cycles+eax]		; Get Cycles
		 sub   [_m68000_ICount],eax		; Decrement ICount
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 mov   edi,[R_A7]		; Get A7
		 test  ah,20H	; Which Mode ?
		 jne	short ExSuperMode		; Supervisor
		 or    byte [R_SR_H],20H	; Set Supervisor Mode
		 mov   [R_USP],edi		; Save in USP
		 mov   edi,[R_ISP]		; Get ISP
ExSuperMode:
		 sub   edi,byte 6
		 mov   [R_A7],edi		; Put in A7
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 add   edi,byte 2
		 mov   [R_PC],ESI
		 mov   edx,ESI
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   eax		;Level
		 shl   eax,2
		 add   eax,[R_VBR]
		 mov   [R_PC],ESI
		 mov   ecx,EAX
		 call  @cpu_readmem24_dword@4
		 and   eax, 0ffffffh
		 mov   esi,eax		;Set PC
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   ebp,dword [_OP_ROM]
		 pop   edx		; Restore flags
		 ret
		 ALIGN 4


BusError:
		 push  edx		; Save flags
		 push  ecx		; Save flags
		 movzx eax,byte[exception_cycles+2]		; Get Cycles
		 sub   [_m68000_ICount],eax		; Decrement ICount
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 mov   edi,[R_A7]		; Get A7
		 test  ah,20H	; Which Mode ?
		 jne	short BESuperMode		; Supervisor
		 or    byte [R_SR_H],20H	; Set Supervisor Mode
		 mov   [R_USP],edi		; Save in USP
		 mov   edi,[R_ISP]		; Get ISP
BESuperMode:
		 sub   edi,byte 14
		 mov   [R_A7],edi		; Put in A7
		 mov   [R_PC],ESI
		 add   edi,byte 2		; SP(Word) <- Dummy (Read/Write cycle flag, Command/Others flag, etc)
		 pop   ecx
		 push  eax
		 mov   edx,ecx
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8	; SP(DWord) <- Accessed Adr
		 add   edi,byte 6		; SP(Word) <- Dummy (OP word)
		 pop   eax
		 and   EDI,0FFFFFFh
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8	; SP(Word) <- SR
		 mov   [R_PC],ESI
		 add   edi,byte 2
		 mov   edx,ESI
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8	; SP(DWord) <- PC
		 mov   eax, 8
		 add   eax,[R_VBR]
		 mov   [R_PC],ESI
		 mov   ecx,EAX
		 call  @cpu_readmem24_dword@4
		 and   eax, 0ffffffh
		 mov   esi,eax		;Set PC
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   ebp,dword [_OP_ROM]
		 pop   edx		; Restore flags
		 ret
		 ALIGN 4


AdrError:				; Adress Error
		 push  edx		; Save flags
		 push  ecx		; Save flags
		 movzx eax,byte[exception_cycles+3]		; Get Cycles
		 sub   [_m68000_ICount],eax		; Decrement ICount
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 mov   edi,[R_A7]		; Get A7
		 test  ah,20H	; Which Mode ?
		 jne	short AESuperMode		; Supervisor
		 or    byte [R_SR_H],20H	; Set Supervisor Mode
		 mov   [R_USP],edi		; Save in USP
		 mov   edi,[R_ISP]		; Get ISP
AESuperMode:
		 sub   edi,byte 14
		 mov   [R_A7],edi		; Put in A7
		 mov   [R_PC],ESI
		 add   edi,byte 2
		 pop   ecx
		 push  eax
		 mov   edx,ecx
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 add   edi,byte 6
		 pop   eax
		 and   EDI,0FFFFFFh
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 mov   [R_PC],ESI
		 add   edi,byte 2
		 mov   edx,ESI
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 mov   eax, 12
		 add   eax,[R_VBR]
		 mov   [R_PC],ESI
		 mov   ecx,EAX
		 call  @cpu_readmem24_dword@4
		 and   eax, 0ffffffh
		 mov   esi,eax		;Set PC
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   ebp,dword [_OP_ROM]
		 pop   edx		; Restore flags
		 ret
		 ALIGN 4


OP_1000:				; move.b  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1010:				; move.b  (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1018:				; move.b  (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_101f:				; move.b  (A7)+, D0:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1020:				; move.b  -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1027:				; move.b  -(A7), D0:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1028:				; move.b  ($1028,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1030:				; move.b  ($30,A0,D1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1030_1
		 cwde
OP_1030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1038:				; move.b  $1038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1039:				; move.b  $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_103a:				; move.b  ($103a,PC), D0; ($1038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_103b:				; move.b  ($3b,PC,D1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_103b_1
		 cwde
OP_103b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_103c:				; move.b  #$0, D0:
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1080:				; move.b  D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1090:				; move.b  (A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1098:				; move.b  (A0)+, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_109f:				; move.b  (A7)+, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10a0:				; move.b  -(A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10a7:				; move.b  -(A7), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10a8:				; move.b  ($10a8,A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10b0:				; move.b  (-$50,A0,D1.w), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_10b0_1
		 cwde
OP_10b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10b8:				; move.b  $10b8.w, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10b9:				; move.b  $123456.l, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10ba:				; move.b  ($10ba,PC), (A0); ($10b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10bb:				; move.b  (-$45,PC,D1.w), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_10bb_1
		 cwde
OP_10bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10bc:				; move.b  #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10c0:				; move.b  D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10d0:				; move.b  (A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10d8:				; move.b  (A0)+, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10d8_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10d8_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10df:				; move.b  (A7)+, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10df_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10df_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10e0:				; move.b  -(A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10e0_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10e0_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10e7:				; move.b  -(A7), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10e7_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10e7_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10e8:				; move.b  ($10e8,A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10e8_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10e8_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10f0:				; move.b  (-$10,A0,D1.w), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_10f0_1
		 cwde
OP_10f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10f0_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10f0_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10f8:				; move.b  $10f8.w, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10f8_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10f8_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10f9:				; move.b  $123456.l, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10f9_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10f9_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10fa:				; move.b  ($10fa,PC), (A0)+; ($10f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10fa_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10fa_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10fb:				; move.b  (-$5,PC,D1.w), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_10fb_1
		 cwde
OP_10fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10fb_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10fb_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_10fc:				; move.b  #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_10fc_notA7			;
		 inc   dword [R_A0+ECX*4]
OP_10fc_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1100:				; move.b  D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1100_notA7			;
		 dec   EDI
OP_1100_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1110:				; move.b  (A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1110_notA7			;
		 dec   EDI
OP_1110_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1118:				; move.b  (A0)+, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1118_notA7			;
		 dec   EDI
OP_1118_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_111f:				; move.b  (A7)+, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_111f_notA7			;
		 dec   EDI
OP_111f_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1120:				; move.b  :
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1120_notA7			;
		 dec   EDI				;
OP_1120_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1127:				; move.b  -(A7), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1127_notA7			;
		 dec   EDI				;
OP_1127_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1128:				; move.b  ($1128,A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1128_notA7			;
		 dec   EDI				;
OP_1128_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1130:				; move.b  ($3456,A0,D1.w), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1130_1
		 cwde
OP_1130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1130_notA7			;
		 dec   EDI				;
OP_1130_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1138:				; move.b  $1138.w, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1138_notA7			;
		 dec   EDI				;
OP_1138_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1139:				; move.b  $123456.l, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_1139_notA7			;
		 dec   EDI				;
OP_1139_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_113a:				; move.b  ($113a,PC), -(A0); ($1138):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_113a_notA7			;
		 dec   EDI				;
OP_113a_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_113b:				; move.b  ([$3456,PC,D1.w],$3456), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_113b_1
		 cwde
OP_113b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_113b_notA7			;
		 dec   EDI				;
OP_113b_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_113c:				; move.b  #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_113c_notA7			;
		 dec   EDI				;
OP_113c_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1140:				; move.b  D0, ($1140,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1150:				; move.b  (A0), ($1150,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1158:				; move.b  (A0)+, ($1158,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_115f:				; move.b  (A7)+, ($115f,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1160:				; move.b  -(A0), ($1160,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1167:				; move.b  -(A7), ($1167,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1168:				; move.b  ($1168,A0), ($1168,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1170:				; move.b  ($3456,A0), ($1170,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1170_1
		 cwde
OP_1170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1178:				; move.b  $1178.w, ($1178,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1179:				; move.b  $123456.l, ($1179,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_117a:				; move.b  ($117a,PC), ($117a,A0); ($1178):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_117b:				; move.b  ([$3456,PC],$3456), ($117b,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_117b_1
		 cwde
OP_117b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_117c:				; move.b  #$0, ($117c,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1180:				; move.b  D0, (D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1180_1
		 cwde
OP_1180_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1190:				; move.b  (A0), (D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1190_1
		 cwde
OP_1190_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1198:				; move.b  (A0)+, (D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1198_1
		 cwde
OP_1198_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_119f:				; move.b  (A7)+, ([],D1.w,$3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_119f_1
		 cwde
OP_119f_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11a0:				; move.b  -(A0), ($11a0,D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11a0_1
		 cwde
OP_11a0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11a7:				; move.b  -(A7), ([$11a7],D1.w,$3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11a7_1
		 cwde
OP_11a7_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11a8:				; move.b  ($11a8,A0), ($11a8,D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11a8_1
		 cwde
OP_11a8_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11b0:				; move.b  ($3456,D1.w), ($3456,D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11b0_1
		 cwde
OP_11b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11b0_2
		 cwde
OP_11b0_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11b8:				; move.b  $11b8.w, ($3456,D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11b8_1
		 cwde
OP_11b8_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11b9:				; move.b  $123456.l, ([$3456,D1.w]):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11b9_1
		 cwde
OP_11b9_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11ba:				; move.b  ($11ba,PC), ([$3456,D1.w],$11ba); ($11b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11ba_1
		 cwde
OP_11ba_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11bb:				; move.b  ([$3456,D1.w],$3456), ([$3456,D1.w],$3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11bb_1
		 cwde
OP_11bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11bb_2
		 cwde
OP_11bb_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11bc:				; move.b  #$0, ($3456,D1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11bc_1
		 cwde
OP_11bc_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11c0:				; move.b  D0, $11c0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11d0:				; move.b  (A0), $11d0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11d8:				; move.b  (A0)+, $11d8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11df:				; move.b  (A7)+, $11df.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11e0:				; move.b  -(A0), $11e0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11e7:				; move.b  -(A7), $11e7.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11e8:				; move.b  ($11e8,A0), $11e8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11f0:				; move.b  ($3456), $11f0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11f0_1
		 cwde
OP_11f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11f8:				; move.b  $11f8.w, $11f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11f9:				; move.b  $123456.l, $11f9.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11fa:				; move.b  ($11fa,PC), $11fa.w; ($11f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11fb:				; move.b  ([$3456],$3456), $11fb.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_11fb_1
		 cwde
OP_11fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_11fc:				; move.b  #$0, $11fc.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13c0:				; move.b  D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13d0:				; move.b  (A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13d8:				; move.b  (A0)+, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13df:				; move.b  (A7)+, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13e0:				; move.b  -(A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13e7:				; move.b  -(A7), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13e8:				; move.b  ($13e8,A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13f0:				; move.b  ($3456), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_13f0_1
		 cwde
OP_13f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13f8:				; move.b  $13f8.w, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13f9:				; move.b  $123456.l, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13fa:				; move.b  ($13fa,PC), $123456.l; ($13f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13fb:				; move.b  ([$3456],$3456), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_13fb_1
		 cwde
OP_13fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_13fc:				; move.b  #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ec0:				; move.b  D0, (A7)+:
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ed0:				; move.b  (A0), (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ed8:				; move.b  (A0)+, (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1edf:				; move.b  (A7)+, (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ee0:				; move.b  -(A0), (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ee7:				; move.b  -(A7), (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ee8:				; move.b  ($1ee8,A0), (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ef0:				; move.b  (-$10,A0,D1.l*8), (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1ef0_1
		 cwde
OP_1ef0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ef8:				; move.b  $1ef8.w, (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1ef9:				; move.b  $123456.l, (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1efa:				; move.b  ($1efa,PC), (A7)+; ($1ef8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1efb:				; move.b  (-$5,PC,D1.l*8), (A7)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1efb_1
		 cwde
OP_1efb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1efc:				; move.b  #$0, (A7)+:
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f00:				; move.b  D0, -(A7):
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f10:				; move.b  (A0), -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f18:				; move.b  (A0)+, -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f1f:				; move.b  (A7)+, -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f20:				; move.b  -(A0), -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f27:				; move.b  -(A7), -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f28:				; move.b  ($1f28,A0), -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f30:				; move.b  ($3456,A0,D1.l*8), -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1f30_1
		 cwde
OP_1f30_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f38:				; move.b  $1f38.w, -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f39:				; move.b  $123456.l, -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f3a:				; move.b  ($1f3a,PC), -(A7); ($1f38):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f3b:				; move.b  ([$3456,PC,D1.l*8],$3456), -(A7):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_1f3b_1
		 cwde
OP_1f3b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_1f3c:				; move.b  #$0, -(A7):
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AL,AL
		 pushfd
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2000:				; move.l  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2010:				; move.l  (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2018:				; move.l  (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2020:				; move.l  -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2028:				; move.l  ($2028,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2030:				; move.l  ($30,A0,D2.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_2030_1
		 cwde
OP_2030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2038:				; move.l  $2038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2039:				; move.l  $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_203a:				; move.l  ($203a,PC), D0; ($2038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_203b:				; move.l  ($3b,PC,D2.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_203b_1
		 cwde
OP_203b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_203c:				; move.l  #$123456, D0:
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2040:				; movea.l D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2050:				; movea.l (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2058:				; movea.l (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2060:				; movea.l -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2068:				; movea.l ($2068,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2070:				; movea.l ($70,A0,D2.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_2070_1
		 cwde
OP_2070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2078:				; movea.l $2078.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2079:				; movea.l $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_207a:				; movea.l ($207a,PC), A0; ($2078):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_207b:				; movea.l ($7b,PC,D2.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_207b_1
		 cwde
OP_207b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_207c:				; movea.l #$123456, A0:
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2080:				; move.l  D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2090:				; move.l  (A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2098:				; move.l  (A0)+, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20a0:				; move.l  -(A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20a8:				; move.l  ($20a8,A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20b0:				; move.l  (-$50,A0,D2.w), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_20b0_1
		 cwde
OP_20b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20b8:				; move.l  $20b8.w, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20b9:				; move.l  $123456.l, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20ba:				; move.l  ($20ba,PC), (A0); ($20b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20bb:				; move.l  (-$45,PC,D2.w), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_20bb_1
		 cwde
OP_20bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20bc:				; move.l  #$123456, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20c0:				; move.l  D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20d0:				; move.l  (A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20d8:				; move.l  (A0)+, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20e0:				; move.l  -(A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20e8:				; move.l  ($20e8,A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20f0:				; move.l  (-$10,A0,D2.w), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_20f0_1
		 cwde
OP_20f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20f8:				; move.l  $20f8.w, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20f9:				; move.l  $123456.l, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20fa:				; move.l  ($20fa,PC), (A0)+; ($20f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20fb:				; move.l  (-$5,PC,D2.w), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_20fb_1
		 cwde
OP_20fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_20fc:				; move.l  #$123456, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2100:				; move.l  D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2110:				; move.l  (A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2118:				; move.l  (A0)+, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2120:				; move.l  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2128:				; move.l  ($2128,A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2130:				; move.l  ($3456,A0,D2.w), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_2130_1
		 cwde
OP_2130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2138:				; move.l  $2138.w, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2139:				; move.l  $123456.l, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_213a:				; move.l  ($213a,PC), -(A0); ($2138):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_213b:				; move.l  ([$3456,PC,D2.w],$3456), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_213b_1
		 cwde
OP_213b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_213c:				; move.l  #$123456, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2140:				; move.l  D0, ($2140,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2150:				; move.l  (A0), ($2150,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2158:				; move.l  (A0)+, ($2158,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2160:				; move.l  -(A0), ($2160,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2168:				; move.l  ($2168,A0), ($2168,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2170:				; move.l  ($3456,A0), ($2170,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_2170_1
		 cwde
OP_2170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2178:				; move.l  $2178.w, ($2178,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2179:				; move.l  $123456.l, ($2179,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_217a:				; move.l  ($217a,PC), ($217a,A0); ($2178):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_217b:				; move.l  ([$3456,PC],$3456), ($217b,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_217b_1
		 cwde
OP_217b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_217c:				; move.l  #$123456, ($217c,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2180:				; move.l  D0, (D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_2180_1
		 cwde
OP_2180_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2190:				; move.l  (A0), (D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_2190_1
		 cwde
OP_2190_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_2198:				; move.l  (A0)+, (D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_2198_1
		 cwde
OP_2198_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21a0:				; move.l  -(A0), ($21a0,D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21a0_1
		 cwde
OP_21a0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21a8:				; move.l  ($21a8,A0), ($21a8,D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21a8_1
		 cwde
OP_21a8_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21b0:				; move.l  ($3456,D2.w), ($3456,D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21b0_1
		 cwde
OP_21b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21b0_2
		 cwde
OP_21b0_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21b8:				; move.l  $21b8.w, ($3456,D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21b8_1
		 cwde
OP_21b8_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21b9:				; move.l  $123456.l, ([$3456,D2.w]):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21b9_1
		 cwde
OP_21b9_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21ba:				; move.l  ($21ba,PC), ([$3456,D2.w],$21ba); ($21b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21ba_1
		 cwde
OP_21ba_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21bb:				; move.l  ([$3456,D2.w],$3456), ([$3456,D2.w],$3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21bb_1
		 cwde
OP_21bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21bb_2
		 cwde
OP_21bb_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21bc:				; move.l  #$123456, ($3456,D2.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21bc_1
		 cwde
OP_21bc_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21c0:				; move.l  D0, $21c0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21d0:				; move.l  (A0), $21d0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21d8:				; move.l  (A0)+, $21d8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21e0:				; move.l  -(A0), $21e0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21e8:				; move.l  ($21e8,A0), $21e8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21f0:				; move.l  ($3456), $21f0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21f0_1
		 cwde
OP_21f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21f8:				; move.l  $21f8.w, $21f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21f9:				; move.l  $123456.l, $21f9.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21fa:				; move.l  ($21fa,PC), $21fa.w; ($21f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21fb:				; move.l  ([$3456],$3456), $21fb.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_21fb_1
		 cwde
OP_21fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_21fc:				; move.l  #$123456, $21fc.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23c0:				; move.l  D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23d0:				; move.l  (A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23d8:				; move.l  (A0)+, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23e0:				; move.l  -(A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23e8:				; move.l  ($23e8,A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23f0:				; move.l  ($3456), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_23f0_1
		 cwde
OP_23f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23f8:				; move.l  $23f8.w, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23f9:				; move.l  $123456.l, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23fa:				; move.l  ($23fa,PC), $123456.l; ($23f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23fb:				; move.l  ([$3456],$3456), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_23fb_1
		 cwde
OP_23fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_23fc:				; move.l  #$123456, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 test  EAX,EAX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3000:				; move.w  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3010:				; move.w  (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3018:				; move.w  (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3020:				; move.w  -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3028:				; move.w  ($3028,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3030:				; move.w  ($30,A0,D3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_3030_1
		 cwde
OP_3030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3038:				; move.w  $3038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3039:				; move.w  $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_303a:				; move.w  ($303a,PC), D0; ($3038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_303b:				; move.w  ($3b,PC,D3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_303b_1
		 cwde
OP_303b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_303c:				; move.w  #$303c, D0:
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3040:				; movea.w D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3050:				; movea.w (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3058:				; movea.w (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3060:				; movea.w -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3068:				; movea.w ($3068,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3070:				; movea.w ($70,A0,D3.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_3070_1
		 cwde
OP_3070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3078:				; movea.w $3078.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3079:				; movea.w $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_307a:				; movea.w ($307a,PC), A0; ($3078):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_307b:				; movea.w ($7b,PC,D3.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_307b_1
		 cwde
OP_307b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_307c:				; movea.w #$307c, A0:
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 shr   ecx,9
		 and   ecx,byte 7
		 cwde
		 mov   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3080:				; move.w  D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3090:				; move.w  (A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3098:				; move.w  (A0)+, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30a0:				; move.w  -(A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30a8:				; move.w  ($30a8,A0), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30b0:				; move.w  (-$50,A0,D3.w), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_30b0_1
		 cwde
OP_30b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30b8:				; move.w  $30b8.w, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30b9:				; move.w  $123456.l, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30ba:				; move.w  ($30ba,PC), (A0); ($30b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30bb:				; move.w  (-$45,PC,D3.w), (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_30bb_1
		 cwde
OP_30bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30bc:				; move.w  #$30bc, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30c0:				; move.w  D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30d0:				; move.w  (A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30d8:				; move.w  (A0)+, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30e0:				; move.w  -(A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30e8:				; move.w  ($30e8,A0), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30f0:				; move.w  (-$10,A0,D3.w), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_30f0_1
		 cwde
OP_30f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30f8:				; move.w  $30f8.w, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30f9:				; move.w  $123456.l, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30fa:				; move.w  ($30fa,PC), (A0)+; ($30f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30fb:				; move.w  (-$5,PC,D3.w), (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_30fb_1
		 cwde
OP_30fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_30fc:				; move.w  #$30fc, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3100:				; move.w  D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3110:				; move.w  (A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3118:				; move.w  (A0)+, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3120:				; move.w  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3128:				; move.w  ($3128,A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3130:				; move.w  ($3456,A0,D3.w), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_3130_1
		 cwde
OP_3130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3138:				; move.w  $3138.w, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3139:				; move.w  $123456.l, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_313a:				; move.w  ($313a,PC), -(A0); ($3138):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_313b:				; move.w  ([$3456,PC,D3.w],$3456), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_313b_1
		 cwde
OP_313b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_313c:				; move.w  #$313c, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3140:				; move.w  D0, ($3140,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3150:				; move.w  (A0), ($3150,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3158:				; move.w  (A0)+, ($3158,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3160:				; move.w  -(A0), ($3160,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3168:				; move.w  ($3168,A0), ($3168,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3170:				; move.w  ($3456,A0), ($3170,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_3170_1
		 cwde
OP_3170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3178:				; move.w  $3178.w, ($3178,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3179:				; move.w  $123456.l, ($3179,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_317a:				; move.w  ($317a,PC), ($317a,A0); ($3178):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_317b:				; move.w  ([$3456,PC],$3456), ($317b,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_317b_1
		 cwde
OP_317b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_317c:				; move.w  #$317c, ($317c,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3180:				; move.w  D0, (D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 mov   EAX,[R_D0+EBX*4]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_3180_1
		 cwde
OP_3180_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3190:				; move.w  (A0), (D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_3190_1
		 cwde
OP_3190_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_3198:				; move.w  (A0)+, (D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_3198_1
		 cwde
OP_3198_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31a0:				; move.w  -(A0), ($31a0,D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31a0_1
		 cwde
OP_31a0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31a8:				; move.w  ($31a8,A0), ($31a8,D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31a8_1
		 cwde
OP_31a8_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31b0:				; move.w  ($3456,D3.w), ($3456,D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31b0_1
		 cwde
OP_31b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31b0_2
		 cwde
OP_31b0_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31b8:				; move.w  $31b8.w, ($3456,D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31b8_1
		 cwde
OP_31b8_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31b9:				; move.w  $123456.l, ([$3456,D3.w]):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31b9_1
		 cwde
OP_31b9_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31ba:				; move.w  ($31ba,PC), ([$3456,D3.w],$31ba); ($31b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31ba_1
		 cwde
OP_31ba_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31bb:				; move.w  ([$3456,D3.w],$3456), ([$3456,D3.w],$3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31bb_1
		 cwde
OP_31bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31bb_2
		 cwde
OP_31bb_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31bc:				; move.w  #$31bc, ($3456,D3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 shr   ecx,9
		 and   ecx,byte 7
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31bc_1
		 cwde
OP_31bc_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31c0:				; move.w  D0, $31c0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31d0:				; move.w  (A0), $31d0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31d8:				; move.w  (A0)+, $31d8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31e0:				; move.w  -(A0), $31e0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31e8:				; move.w  ($31e8,A0), $31e8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31f0:				; move.w  ($3456), $31f0.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31f0_1
		 cwde
OP_31f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31f8:				; move.w  $31f8.w, $31f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31f9:				; move.w  $123456.l, $31f9.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31fa:				; move.w  ($31fa,PC), $31fa.w; ($31f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31fb:				; move.w  ([$3456],$3456), $31fb.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_31fb_1
		 cwde
OP_31fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_31fc:				; move.w  #$31fc, $31fc.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33c0:				; move.w  D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 15
		 mov   EAX,[R_D0+ECX*4]
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33d0:				; move.w  (A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33d8:				; move.w  (A0)+, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33e0:				; move.w  -(A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33e8:				; move.w  ($33e8,A0), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33f0:				; move.w  ($3456), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_33f0_1
		 cwde
OP_33f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33f8:				; move.w  $33f8.w, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33f9:				; move.w  $123456.l, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33fa:				; move.w  ($33fa,PC), $123456.l; ($33f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33fb:				; move.w  ([$3456],$3456), $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_33fb_1
		 cwde
OP_33fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_33fc:				; move.w  #$33fc, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  AX,AX
		 pushfd
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0000:				; ori.b   #$0, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 or    AL,BL
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0010:				; ori.b   #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0018:				; ori.b   #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_001f:				; ori.b   #$0, (A7)+:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0020:				; ori.b   #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0027:				; ori.b   #$0, -(A7):
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0028:				; ori.b   #$0, ($28,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0030:				; ori.b   #$0, ($30,A0,D0.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0030_1
		 cwde
OP_0030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0038:				; ori.b   #$0, $38.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0039:				; ori.b   #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_003c:				; ori     #$0, CCR:
		 add   esi,byte 2

		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 or    AL,BL
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0040:				; ori.w   #$40, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 or    AX,BX
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0050:				; ori.w   #$50, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0058:				; ori.w   #$58, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0060:				; ori.w   #$60, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0068:				; ori.w   #$68, ($68,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0070:				; ori.w   #$70, ($70,A0,D0.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0070_1
		 cwde
OP_0070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0078:				; ori.w   #$78, $78.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0079:				; ori.w   #$79, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_007c:				; ori     #$7c, SR:
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 jne   near OP_007c_1

;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_0007c_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_0007c_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_007c_1:
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 or    AX,BX
		 test  ah,20h 			; User Mode ?
		 jne   short OP_007c_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_007c_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0080:				; ori.l   #$123456, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EAX,[R_D0+ECX*4]
		 or    EAX,EBX
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0090:				; ori.l   #$123456, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0098:				; ori.l   #$123456, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_00a0:				; ori.l   #$123456, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_00a8:				; ori.l   #$123456, ($a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_00b0:				; ori.l   #$123456, (-$50,A0,D0.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_00b0_1
		 cwde
OP_00b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_00b8:				; ori.l   #$123456, $b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_00b9:				; ori.l   #$123456, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0200:				; andi.b  #$0, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 and   AL,BL
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0210:				; andi.b  #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0218:				; andi.b  #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_021f:				; andi.b  #$0, (A7)+:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0220:				; andi.b  #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0227:				; andi.b  #$0, -(A7):
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0228:				; andi.b  #$0, ($228,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0230:				; andi.b  #$0, ($30,A0,D0.w*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0230_1
		 cwde
OP_0230_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0238:				; andi.b  #$0, $238.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0239:				; andi.b  #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_023c:				; andi    #$0, CCR:
		 add   esi,byte 2

		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 and   AL,BL
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0240:				; andi.w  #$240, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 and   AX,BX
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0250:				; andi.w  #$250, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0258:				; andi.w  #$258, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0260:				; andi.w  #$260, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0268:				; andi.w  #$268, ($268,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0270:				; andi.w  #$270, ($70,A0,D0.w*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0270_1
		 cwde
OP_0270_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0278:				; andi.w  #$278, $278.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0279:				; andi.w  #$279, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_027c:				; andi    #$27c, SR:
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 jne   near OP_027c_1

;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_0027c_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_0027c_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_027c_1:
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 and   AX,BX
		 test  ah,20h 			; User Mode ?
		 jne   short OP_027c_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_027c_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0280:				; andi.l  #$123456, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EAX,[R_D0+ECX*4]
		 and   EAX,EBX
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0290:				; andi.l  #$123456, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0298:				; andi.l  #$123456, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_02a0:				; andi.l  #$123456, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_02a8:				; andi.l  #$123456, ($2a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_02b0:				; andi.l  #$123456, (-$50,A0,D0.w*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_02b0_1
		 cwde
OP_02b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_02b8:				; andi.l  #$123456, $2b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_02b9:				; andi.l  #$123456, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0400:				; subi.b  #$0, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 sub   AL,BL
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0410:				; subi.b  #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0418:				; subi.b  #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_041f:				; subi.b  #$0, (A7)+:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0420:				; subi.b  #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0427:				; subi.b  #$0, -(A7):
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0428:				; subi.b  #$0, ($428,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0430:				; subi.b  #$0, ($30,A0,D0.w*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0430_1
		 cwde
OP_0430_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0438:				; subi.b  #$0, $438.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0439:				; subi.b  #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0440:				; subi.w  #$440, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 sub   AX,BX
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0450:				; subi.w  #$450, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0458:				; subi.w  #$458, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0460:				; subi.w  #$460, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0468:				; subi.w  #$468, ($468,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0470:				; subi.w  #$470, ($70,A0,D0.w*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0470_1
		 cwde
OP_0470_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0478:				; subi.w  #$478, $478.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0479:				; subi.w  #$479, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0480:				; subi.l  #$123456, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EAX,[R_D0+ECX*4]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0490:				; subi.l  #$123456, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0498:				; subi.l  #$123456, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_04a0:				; subi.l  #$123456, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_04a8:				; subi.l  #$123456, ($4a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_04b0:				; subi.l  #$123456, (-$50,A0,D0.w*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_04b0_1
		 cwde
OP_04b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_04b8:				; subi.l  #$123456, $4b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_04b9:				; subi.l  #$123456, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0600:				; addi.b  #$0, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 add   AL,BL
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0610:				; addi.b  #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0618:				; addi.b  #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_061f:				; addi.b  #$0, (A7)+:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0620:				; addi.b  #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0627:				; addi.b  #$0, -(A7):
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0628:				; addi.b  #$0, ($628,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0630:				; addi.b  #$0, ($30,A0,D0.w*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0630_1
		 cwde
OP_0630_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0638:				; addi.b  #$0, $638.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0639:				; addi.b  #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0640:				; addi.w  #$640, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 add   AX,BX
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0650:				; addi.w  #$650, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0658:				; addi.w  #$658, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0660:				; addi.w  #$660, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0668:				; addi.w  #$668, ($668,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0670:				; addi.w  #$670, ($70,A0,D0.w*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0670_1
		 cwde
OP_0670_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0678:				; addi.w  #$678, $678.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0679:				; addi.w  #$679, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0680:				; addi.l  #$123456, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EAX,[R_D0+ECX*4]
		 add   EAX,EBX
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0690:				; addi.l  #$123456, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0698:				; addi.l  #$123456, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_06a0:				; addi.l  #$123456, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_06a8:				; addi.l  #$123456, ($6a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_06b0:				; addi.l  #$123456, (-$50,A0,D0.w*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_06b0_1
		 cwde
OP_06b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_06b8:				; addi.l  #$123456, $6b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_06b9:				; addi.l  #$123456, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a00:				; eori.b  #$0, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 xor   AL,BL
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a10:				; eori.b  #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a18:				; eori.b  #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a1f:				; eori.b  #$0, (A7)+:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a20:				; eori.b  #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a27:				; eori.b  #$0, -(A7):
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a28:				; eori.b  #$0, ($a28,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a30:				; eori.b  #$0, ($30,A0,D0.l*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0a30_1
		 cwde
OP_0a30_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a38:				; eori.b  #$0, $a38.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a39:				; eori.b  #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,BL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a3c:				; eori    #$0, CCR:
		 add   esi,byte 2

		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 xor   AL,BL
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a40:				; eori.w  #$a40, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 xor   AX,BX
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a50:				; eori.w  #$a50, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a58:				; eori.w  #$a58, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a60:				; eori.w  #$a60, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a68:				; eori.w  #$a68, ($a68,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a70:				; eori.w  #$a70, ($70,A0,D0.l*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0a70_1
		 cwde
OP_0a70_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a78:				; eori.w  #$a78, $a78.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a79:				; eori.w  #$a79, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,BX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a7c:				; eori    #$a7c, SR:
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 jne   near OP_0a7c_1

;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_00a7c_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_00a7c_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_0a7c_1:
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 xor   AX,BX
		 test  ah,20h 			; User Mode ?
		 jne   short OP_0a7c_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_0a7c_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a80:				; eori.l  #$123456, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EAX,[R_D0+ECX*4]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a90:				; eori.l  #$123456, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0a98:				; eori.l  #$123456, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0aa0:				; eori.l  #$123456, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0aa8:				; eori.l  #$123456, ($aa8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0ab0:				; eori.l  #$123456, (-$50,A0,D0.l*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0ab0_1
		 cwde
OP_0ab0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0ab8:				; eori.l  #$123456, $ab8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0ab9:				; eori.l  #$123456, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,EBX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c00:				; cmpi.b  #$0, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c10:				; cmpi.b  #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c18:				; cmpi.b  #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c1f:				; cmpi.b  #$0, (A7)+:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c20:				; cmpi.b  #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c27:				; cmpi.b  #$0, -(A7):
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c28:				; cmpi.b  #$0, ($c28,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c30:				; cmpi.b  #$0, ($30,A0,D0.l*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0c30_1
		 cwde
OP_0c30_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c38:				; cmpi.b  #$0, $c38.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c39:				; cmpi.b  #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c3c:				; dc.w $0c3c; ILLEGAL:
		 add   esi,byte 2

		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 cmp   AL,BL
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c40:				; cmpi.w  #$c40, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EAX,[R_D0+ECX*4]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c50:				; cmpi.w  #$c50, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c58:				; cmpi.w  #$c58, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c60:				; cmpi.w  #$c60, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c68:				; cmpi.w  #$c68, ($c68,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c70:				; cmpi.w  #$c70, ($70,A0,D0.l*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0c70_1
		 cwde
OP_0c70_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c78:				; cmpi.w  #$c78, $c78.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c79:				; cmpi.w  #$c79, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c7c:				; dc.w $0c7c; ILLEGAL:
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 jne   near OP_0c7c_1

;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_00c7c_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_00c7c_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_0c7c_1:
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   ECX,edx
		 and   ECX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,ECX 				; C

		 mov   ECX,edx
		 shr   ECX,10
		 and   ECX,byte 2
		 or    eax,ECX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 cmp   AX,BX
		 test  ah,20h 			; User Mode ?
		 jne   short OP_0c7c_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_0c7c_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c80:				; cmpi.l  #$123456, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EAX,[R_D0+ECX*4]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c90:				; cmpi.l  #$123456, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0c98:				; cmpi.l  #$123456, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0ca0:				; cmpi.l  #$123456, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0ca8:				; cmpi.l  #$123456, ($ca8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0cb0:				; cmpi.l  #$123456, (-$50,A0,D0.l*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0cb0_1
		 cwde
OP_0cb0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0cb8:				; cmpi.l  #$123456, $cb8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0cb9:				; cmpi.l  #$123456, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EBX,dword [esi+ebp]
		 rol   EBX,16
		 add   esi,byte 4
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0100:				; btst    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_0100_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0100_1:
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0110:				; btst    D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0110_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0110_1:
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0118:				; btst    D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_0118_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_0118_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0118_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0118_1:
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0120:				; btst    D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_0120_notA7			;
		 dec   EDI				;
OP_0120_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0120_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0120_1:
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0128:				; btst    D0, ($128,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0128_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0128_1:
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0130:				; btst    D0, ($3456,A0,D0.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0130_1
		 cwde
OP_0130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0130_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0130_2:
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0138:				; btst    D0, $138.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0138_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0138_1:
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0139:				; btst    D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0139_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0139_1:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_013a:				; btst    D0, ($13a,PC); ($138):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_013a_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_013a_1:
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_013b:				; btst    D0, ([$3456,PC,D0.w],$3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_013b_1
		 cwde
OP_013b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_013b_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_013b_2:
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_013c:				; btst    D0, CCR			// 16/04/2000 Kenjo
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax

; ---------------------------------------- "btst D0, CCR" �� Ver.
;		 mov   eax,edx
;		 mov   ah,byte [R_XC]
;		 mov   EbX,edx
;		 and   EbX,byte 1
;		 shr   eax,4
;		 and   eax,byte 01Ch 			; X, N & Z
;		 or    eax,EbX 				; C
;		 mov   EbX,edx
;		 shr   EbX,10
;		 and   EbX,byte 2
;		 or    eax,EbX				; O
; ---------------------------------------- ���ޤǤɤ����Ver.��"btst D0, #$0"��
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_013c_1
		 xor   edx,byte 40h	; Clear Zero Flag
; ----------------------------------------

		 or    edx,byte 40h	; Set Zero Flag
		 test  eax,ECX
		 jz    short OP_013c_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_013c_1:
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4


OP_0140:				; bchg    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_0140_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0140_1:
		 xor   [R_D0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0150:				; bchg    D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0150_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0150_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0158:				; bchg    D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_0158_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_0158_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0158_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0158_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0160:				; bchg    D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_0160_notA7			;
		 dec   EDI				;
OP_0160_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0160_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0160_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0168:				; bchg    D0, ($168,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0168_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0168_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0170:				; bchg    D0, ($3456,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0170_1
		 cwde
OP_0170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0170_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0170_2:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0178:				; bchg    D0, $178.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0178_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0178_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0179:				; bchg    D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0179_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0179_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0180:				; bclr    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_0180_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0180_1:
		 not   ecx
		 and   [R_D0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0190:				; bclr    D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0190_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0190_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0198:				; bclr    D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_0198_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_0198_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0198_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0198_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01a0:				; bclr    D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_01a0_notA7			;
		 dec   EDI				;
OP_01a0_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01a0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01a0_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01a8:				; bclr    D0, ($1a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01a8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01a8_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01b0:				; bclr    D0, ($3456,D0.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_01b0_1
		 cwde
OP_01b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01b0_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01b0_2:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01b8:				; bclr    D0, $1b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01b8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01b8_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01b9:				; bclr    D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01b9_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01b9_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01c0:				; bset    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_01c0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01c0_1:
		 or    [R_D0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01d0:				; bset    D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01d0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01d0_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01d8:				; bset    D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_01d8_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_01d8_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01d8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01d8_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01e0:				; bset    D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_01e0_notA7			;
		 dec   EDI				;
OP_01e0_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01e0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01e0_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01e8:				; bset    D0, ($1e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01e8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01e8_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01f0:				; bset    D0, ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_01f0_1
		 cwde
OP_01f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01f0_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01f0_2:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01f8:				; bset    D0, $1f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01f8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01f8_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01f9:				; bset    D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   ecx, [R_D0+ECX*4]
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_01f9_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_01f9_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0108:				; movep.w ($108,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 push  edx
		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   bh,al
		 add   edi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   bl,al
		 mov   [R_D0+ecx*4],bx
		 pop   edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0148:				; movep.l ($148,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 push  edx
		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   bh,al
		 add   edi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   bl,al
		 add   edi,byte 2
		 shl   ebx,16
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   bh,al
		 add   edi,byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   bl,al
		 mov   [R_D0+ecx*4],ebx
		 pop   edx
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0188:				; movep.w D0, ($188,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 push  edx
		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   eax,[R_D0+ecx*4]
		 rol   eax,byte 24
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 push  EaX
		 mov   [Safe_EDI],EDI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDI,[Safe_EDI]
		 pop   EAX
		 add   edi,byte 2
		 rol   eax,byte 8
		 mov   [R_PC],ESI
		 push  EaX
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EAX
		 pop   edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_01c8:				; movep.l D0, ($1c8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 push  edx
		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   eax,[R_D0+ecx*4]
		 rol   eax,byte 8
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 push  EaX
		 mov   [Safe_EDI],EDI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDI,[Safe_EDI]
		 pop   EAX
		 add   edi,byte 2
		 rol   eax,byte 8
		 mov   [R_PC],ESI
		 push  EaX
		 mov   [Safe_EDI],EDI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDI,[Safe_EDI]
		 pop   EAX
		 add   edi,byte 2
		 rol   eax,byte 8
		 mov   [R_PC],ESI
		 push  EaX
		 mov   [Safe_EDI],EDI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDI,[Safe_EDI]
		 pop   EAX
		 add   edi,byte 2
		 rol   eax,byte 8
		 mov   [R_PC],ESI
		 push  EaX
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EAX
		 pop   edx
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0800:				; btst    #$0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_0800_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0800_1:
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0810:				; btst    #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0810_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0810_1:
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0818:				; btst    #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_0818_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_0818_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0818_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0818_1:
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0820:				; btst    #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_0820_notA7			;
		 dec   EDI				;
OP_0820_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0820_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0820_1:
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0828:				; btst    #$0, ($828,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0828_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0828_1:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0830:				; btst    #$0, ($30,A0,D0.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0830_1
		 cwde
OP_0830_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0830_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0830_2:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0838:				; btst    #$0, $838.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0838_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0838_1:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0839:				; btst    #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0839_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0839_1:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_083a:				; btst    #$0, ($83a,PC); ($838):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_083a_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_083a_1:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_083b:				; btst    #$0, ($3b,PC,D0.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_083b_1
		 cwde
OP_083b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_083b_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_083b_2:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0840:				; bchg    #$0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_0840_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0840_1:
		 xor   [R_D0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0850:				; bchg    #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0850_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0850_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0858:				; bchg    #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_0858_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_0858_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0858_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0858_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0860:				; bchg    #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_0860_notA7			;
		 dec   EDI				;
OP_0860_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0860_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0860_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0868:				; bchg    #$0, ($868,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0868_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0868_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0870:				; bchg    #$0, ($70,A0,D0.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_0870_1
		 cwde
OP_0870_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0870_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0870_2:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0878:				; bchg    #$0, $878.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0878_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0878_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0879:				; bchg    #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0879_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0879_1:
		 xor   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0880:				; bclr    #$0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_0880_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0880_1:
		 not   ecx
		 and   [R_D0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0890:				; bclr    #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0890_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0890_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_0898:				; bclr    #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_0898_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_0898_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_0898_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_0898_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08a0:				; bclr    #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_08a0_notA7			;
		 dec   EDI				;
OP_08a0_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08a0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08a0_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08a8:				; bclr    #$0, ($8a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08a8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08a8_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08b0:				; bclr    #$0, (-$50,A0,D0.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_08b0_1
		 cwde
OP_08b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08b0_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08b0_2:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08b8:				; bclr    #$0, $8b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08b8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08b8_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08b9:				; bclr    #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08b9_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08b9_1:
		 not   ecx
		 and   AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08c0:				; bset    #$0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 31
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 or    edx,byte 40h	; Set Zero Flag
		 test  [R_D0+ebx*4],ECX
		 jz    short OP_08c0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08c0_1:
		 or    [R_D0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08d0:				; bset    #$0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08d0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08d0_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08d8:				; bset    #$0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_08d8_notA7			;
		 inc   dword [R_A0+EBX*4]		;
OP_08d8_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08d8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08d8_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08e0:				; bset    #$0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_08e0_notA7			;
		 dec   EDI				;
OP_08e0_notA7:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08e0_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08e0_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08e8:				; bset    #$0, ($8e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08e8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08e8_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08f0:				; bset    #$0, (-$10,A0,D0.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_08f0_1
		 cwde
OP_08f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08f0_2
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08f0_2:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08f8:				; bset    #$0, $8f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08f8_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08f8_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_08f9:				; bset    #$0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ECX,dword [esi+ebp]
		 add   esi,byte 2
		 and   ecx, byte 7
		 xor   eax,eax
		 inc   eax
		 shl   eax,cl
		 mov   ecx,eax
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 or    edx,byte 40h	; Set Zero Flag
		 test  AL,CL
		 jz    short OP_08f9_1
		 xor   edx,byte 40h	; Clear Zero Flag
OP_08f9_1:
		 or    AL,CL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41d0:				; lea     (A0), A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_A0+ECX*4],edi
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41e8:				; lea     ($41e8,A0), A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_A0+ECX*4],edi
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41f0:				; lea     ($3456), A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_41f0_1
		 cwde
OP_41f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_A0+ECX*4],edi
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41f8:				; lea     $41f8.w, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_A0+ECX*4],edi
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41f9:				; lea     $123456.l, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_A0+ECX*4],edi
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41fa:				; lea     ($41fa,PC), A0; ($41f8):
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_A0+ECX*4],edi
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41fb:				; lea     ([$3456],$3456), A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_41fb_1
		 cwde
OP_41fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_A0+ECX*4],edi
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4850:				; pea     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   ecx,[R_A7]	 ; Push onto Stack
		 sub   ecx,byte 4
		 mov   [R_A7],ecx
		 mov   [R_PC],ESI
		 and   ECX,0FFFFFFh
		 mov   [R_CCR],edx
		 mov   edx,EDI
		 mov   ecx,ECX
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4868:				; pea     ($4868,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   ecx,[R_A7]	 ; Push onto Stack
		 sub   ecx,byte 4
		 mov   [R_A7],ecx
		 mov   [R_PC],ESI
		 and   ECX,0FFFFFFh
		 mov   [R_CCR],edx
		 mov   edx,EDI
		 mov   ecx,ECX
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4870:				; pea     ($70,A0,D4.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4870_1
		 cwde
OP_4870_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   ecx,[R_A7]	 ; Push onto Stack
		 sub   ecx,byte 4
		 mov   [R_A7],ecx
		 mov   [R_PC],ESI
		 and   ECX,0FFFFFFh
		 mov   [R_CCR],edx
		 mov   edx,EDI
		 mov   ecx,ECX
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4878:				; pea     $4878.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   ecx,[R_A7]	 ; Push onto Stack
		 sub   ecx,byte 4
		 mov   [R_A7],ecx
		 mov   [R_PC],ESI
		 and   ECX,0FFFFFFh
		 mov   [R_CCR],edx
		 mov   edx,EDI
		 mov   ecx,ECX
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4879:				; pea     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   ecx,[R_A7]	 ; Push onto Stack
		 sub   ecx,byte 4
		 mov   [R_A7],ecx
		 mov   [R_PC],ESI
		 and   ECX,0FFFFFFh
		 mov   [R_CCR],edx
		 mov   edx,EDI
		 mov   ecx,ECX
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_487a:				; pea     ($487a,PC); ($4878):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   ecx,[R_A7]	 ; Push onto Stack
		 sub   ecx,byte 4
		 mov   [R_A7],ecx
		 mov   [R_PC],ESI
		 and   ECX,0FFFFFFh
		 mov   [R_CCR],edx
		 mov   edx,EDI
		 mov   ecx,ECX
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_487b:				; pea     ($7b,PC,D4.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_487b_1
		 cwde
OP_487b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   ecx,[R_A7]	 ; Push onto Stack
		 sub   ecx,byte 4
		 mov   [R_A7],ecx
		 mov   [R_PC],ESI
		 and   ECX,0FFFFFFh
		 mov   [R_CCR],edx
		 mov   edx,EDI
		 mov   ecx,ECX
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40c0:				; move    SR, D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 mov   [R_D0+ECX*4],AX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40d0:				; move    SR, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40d8:				; move    SR, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40e0:				; move    SR, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40e8:				; move    SR, ($40e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40f0:				; move    SR, (-$10,A0,D4.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_40f0_1
		 cwde
OP_40f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40f8:				; move    SR, $40f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40f9:				; move    SR, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   ah,byte [R_SR_H] 	; T, S & I

		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42c0:				; move    CCR, D0; (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42c0_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42c0_Cnt:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   [R_D0+ECX*4],AX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42d0:				; move    CCR, (A0); (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42d0_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42d0_Cnt:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42d8:				; move    CCR, (A0)+; (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42d8_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42d8_Cnt:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42e0:				; move    CCR, -(A0); (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42e0_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42e0_Cnt:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42e8:				; move    CCR, ($42e8,A0); (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42e8_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42e8_Cnt:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42f0:				; move    CCR, (-$10,A0,D4.w*2); (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42f0_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42f0_Cnt:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_42f0_1
		 cwde
OP_42f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42f8:				; move    CCR, $42f8.w; (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42f8_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42f8_Cnt:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42f9:				; move    CCR, $123456.l; (1+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jnz   OP_42f9_Cnt				; 030/040?
		 mov   al, 4
		 jmp   ILLEGAL
OP_42f9_Cnt:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   eax,edx
		 mov   ah,byte [R_XC]
		 mov   EBX,edx
		 and   EBX,byte 1
		 shr   eax,4
		 and   eax,byte 01Ch 		; X, N & Z

		 or    eax,EBX 				; C

		 mov   EBX,edx
		 shr   EBX,10
		 and   EBX,byte 2
		 or    eax,EBX				; O

		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44c0:				; move    D0, CCR:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44d0:				; move    (A0), CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44d8:				; move    (A0)+, CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44e0:				; move    -(A0), CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44e8:				; move    ($44e8,A0), CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44f0:				; move    (-$10,A0,D4.w*4), CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_44f0_1
		 cwde
OP_44f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44f8:				; move    $44f8.w, CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44f9:				; move    $123456.l, CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44fa:				; move    ($44fa,PC), CCR; ($44f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44fb:				; move    (-$5,PC,D4.w*4), CCR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_44fb_1
		 cwde
OP_44fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44fc:				; move    #$0, CCR:
		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46c0:				; move    D0, SR:
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46c0_1

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46c0_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46c0_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46c0_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046c0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046c0_Bank:
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46d0:				; move    (A0), SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46d0_1

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46d0_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46d0_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46d0_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046d0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046d0_Bank:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46d8:				; move    (A0)+, SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46d8_1

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46d8_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46d8_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46d8_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046d8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046d8_Bank:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46e0:				; move    -(A0), SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46e0_1

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46e0_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46e0_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46e0_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046e0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046e0_Bank:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46e8:				; move    ($46e8,A0), SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46e8_1

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46e8_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46e8_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46e8_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046e8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046e8_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46f0:				; move    (-$10,A0,D4.w*8), SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46f0_1

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_46f0_2
		 cwde
OP_46f0_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46f0_3

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46f0_3:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46f0_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046f0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046f0_Bank:
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46f8:				; move    $46f8.w, SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46f8_1

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46f8_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46f8_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46f8_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046f8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046f8_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46f9:				; move    $123456.l, SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46f9_1

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46f9_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46f9_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46f9_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046f9_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046f9_Bank:
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46fa:				; move    ($46fa,PC), SR; ($46f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46fa_1

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46fa_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46fa_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46fa_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046fa_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046fa_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46fb:				; move    (-$5,PC,D4.w*8), SR:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46fb_1

		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_46fb_2
		 cwde
OP_46fb_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46fb_3

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46fb_3:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46fb_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046fb_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046fb_Bank:
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46fc:				; move    #$46fc, SR:
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 je    near OP_46fc_1

		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  ah,20h 			; User Mode ?
		 jne   short OP_46fc_2

		 mov   edx,[R_A7]
		 mov   [R_ISP],edx
		 mov   edx,[R_USP]
		 mov   [R_A7],edx
OP_46fc_2:
		 mov   byte [R_SR_H],ah 	;T, S & I
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_46fc_1:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_046fc_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_046fc_Bank:
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

; Check for Interrupt waiting

		 test  byte [R_IRQ],07H
		 jne   near interrupt

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5000:				; addq.b  #8, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   [R_D0+ebx*4],CL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5088:				; addq.l  #8, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   [R_A0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5010:				; addq.b  #8, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5018:				; addq.b  #8, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_501f:				; addq.b  #8, (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5020:				; addq.b  #8, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5027:				; addq.b  #8, -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5028:				; addq.b  #8, ($5028,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5030:				; addq.b  #8, ($30,A0,D5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5030_1
		 cwde
OP_5030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5038:				; addq.b  #8, $5038.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5039:				; addq.b  #8, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5040:				; addq.w  #8, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   [R_D0+ebx*4],CX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5050:				; addq.w  #8, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5058:				; addq.w  #8, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5060:				; addq.w  #8, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5068:				; addq.w  #8, ($5068,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5070:				; addq.w  #8, ($70,A0,D5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5070_1
		 cwde
OP_5070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5078:				; addq.w  #8, $5078.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5079:				; addq.w  #8, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5080:				; addq.l  #8, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   [R_D0+ebx*4],ECX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5090:				; addq.l  #8, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5098:				; addq.l  #8, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50a0:				; addq.l  #8, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50a8:				; addq.l  #8, ($50a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50b0:				; addq.l  #8, (-$50,A0,D5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_50b0_1
		 cwde
OP_50b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50b8:				; addq.l  #8, $50b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50b9:				; addq.l  #8, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 add   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50c0:				; st      D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   AL,byte 0ffh
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50c8:				; dbt     D0, 50c8:
		 jmp   short OP_50c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_50c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_50c8_1:
OP_50c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50d0:				; st      (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50d8:				; st      (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50df:				; st      (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50e0:				; st      -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50e7:				; st      -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50e8:				; st      ($50e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50f0:				; st      (-$10,A0,D5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_50f0_1
		 cwde
OP_50f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50f8:				; st      $50f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_50f9:				; st      $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 mov   AL,byte 0ffh
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5100:				; subq.b  #8, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   [R_D0+ebx*4],CL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5188:				; subq.l  #8, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   [R_A0+ebx*4],ECX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5110:				; subq.b  #8, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5118:				; subq.b  #8, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_511f:				; subq.b  #8, (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5120:				; subq.b  #8, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5127:				; subq.b  #8, -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5128:				; subq.b  #8, ($5128,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5130:				; subq.b  #8, ($3456,A0,D5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5130_1
		 cwde
OP_5130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5138:				; subq.b  #8, $5138.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5139:				; subq.b  #8, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AL,CL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5140:				; subq.w  #8, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   [R_D0+ebx*4],CX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5150:				; subq.w  #8, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5158:				; subq.w  #8, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5160:				; subq.w  #8, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5168:				; subq.w  #8, ($5168,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5170:				; subq.w  #8, ($3456,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5170_1
		 cwde
OP_5170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5178:				; subq.w  #8, $5178.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5179:				; subq.w  #8, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   AX,CX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5180:				; subq.l  #8, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   [R_D0+ebx*4],ECX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5190:				; subq.l  #8, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5198:				; subq.l  #8, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51a0:				; subq.l  #8, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51a8:				; subq.l  #8, ($51a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51b0:				; subq.l  #8, ($3456,D5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_51b0_1
		 cwde
OP_51b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51b8:				; subq.l  #8, $51b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51b9:				; subq.l  #8, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 shr   ecx,9
		 dec   ecx          ; Move range down
		 and   ecx,byte 7   ; Mask out lower bits
		 inc   ecx          ; correct range
		 sub   EAX,ECX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51c0:				; sf      D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51c8:				; dbra    D0, 51c8:
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_51c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_51c8_1:
OP_51c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51d0:				; sf      (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51d8:				; sf      (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51df:				; sf      (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51e0:				; sf      -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51e7:				; sf      -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51e8:				; sf      ($51e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51f0:				; sf      ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_51f0_1
		 cwde
OP_51f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51f8:				; sf      $51f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_51f9:				; sf      $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 xor   eax,eax
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52c0:				; shi     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52c8:				; dbhi    D0, 52c8:
		 mov   ah,dl
		 sahf
		 ja    short OP_52c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_52c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_52c8_1:
OP_52c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52d0:				; shi     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52d8:				; shi     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52df:				; shi     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52e0:				; shi     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52e7:				; shi     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52e8:				; shi     ($52e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52f0:				; shi     (-$10,A0,D5.w*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_52f0_1
		 cwde
OP_52f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52f8:				; shi     $52f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_52f9:				; shi     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 seta  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53c0:				; sls     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53c8:				; dbls    D0, 53c8:
		 mov   ah,dl
		 sahf
		 jbe   short OP_53c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_53c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_53c8_1:
OP_53c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53d0:				; sls     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53d8:				; sls     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53df:				; sls     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53e0:				; sls     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53e7:				; sls     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53e8:				; sls     ($53e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53f0:				; sls     ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_53f0_1
		 cwde
OP_53f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53f8:				; sls     $53f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_53f9:				; sls     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 mov   ah,dl
		 sahf
		 setbe AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54c0:				; scc     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54c8:				; dbcc    D0, 54c8:
		 test  dl,1H		;check carry
		 jz    short OP_54c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_54c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_54c8_1:
OP_54c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54d0:				; scc     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54d8:				; scc     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54df:				; scc     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54e0:				; scc     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54e7:				; scc     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54e8:				; scc     ($54e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54f0:				; scc     (-$10,A0,D5.w*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_54f0_1
		 cwde
OP_54f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54f8:				; scc     $54f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_54f9:				; scc     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55c0:				; scs     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55c8:				; dbcs    D0, 55c8:
		 test  dl,1H		;check carry
		 jnz   short OP_55c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_55c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_55c8_1:
OP_55c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55d0:				; scs     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55d8:				; scs     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55df:				; scs     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55e0:				; scs     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55e7:				; scs     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55e8:				; scs     ($55e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55f0:				; scs     ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_55f0_1
		 cwde
OP_55f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55f8:				; scs     $55f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_55f9:				; scs     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dl,1		;Check Carry
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56c0:				; sne     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56c8:				; dbne    D0, 56c8:
		 test  dl,40H		;Check zero
		 jz    short OP_56c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_56c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_56c8_1:
OP_56c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56d0:				; sne     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56d8:				; sne     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56df:				; sne     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56e0:				; sne     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56e7:				; sne     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56e8:				; sne     ($56e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56f0:				; sne     (-$10,A0,D5.w*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_56f0_1
		 cwde
OP_56f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56f8:				; sne     $56f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_56f9:				; sne     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57c0:				; seq     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57c8:				; dbeq    D0, 57c8:
		 test  dl,40H		;Check zero
		 jnz   short OP_57c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_57c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_57c8_1:
OP_57c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57d0:				; seq     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57d8:				; seq     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57df:				; seq     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57e0:				; seq     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57e7:				; seq     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57e8:				; seq     ($57e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57f0:				; seq     ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_57f0_1
		 cwde
OP_57f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57f8:				; seq     $57f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_57f9:				; seq     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dl,40H		;Check Zero
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58c0:				; svc     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58c8:				; dbvc    D0, 58c8:
		 test  dh,8H		;Check Overflow
		 jz    short OP_58c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_58c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_58c8_1:
OP_58c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58d0:				; svc     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58d8:				; svc     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58df:				; svc     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58e0:				; svc     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58e7:				; svc     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58e8:				; svc     ($58e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58f0:				; svc     (-$10,A0,D5.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_58f0_1
		 cwde
OP_58f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58f8:				; svc     $58f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_58f9:				; svc     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59c0:				; svs     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59c8:				; dbvs    D0, 59c8:
		 test  dh,8H		;Check Overflow
		 jnz   short OP_59c8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_59c8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_59c8_1:
OP_59c8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59d0:				; svs     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59d8:				; svs     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59df:				; svs     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59e0:				; svs     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59e7:				; svs     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59e8:				; svs     ($59e8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59f0:				; svs     ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_59f0_1
		 cwde
OP_59f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59f8:				; svs     $59f8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_59f9:				; svs     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dh,8H		;Check Overflow
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ac0:				; spl     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ac8:				; dbpl    D0, 5ac8:
		 test  dl,80H		;Check Sign
		 jz    short OP_5ac8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_5ac8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_5ac8_1:
OP_5ac8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ad0:				; spl     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ad8:				; spl     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5adf:				; spl     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ae0:				; spl     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ae7:				; spl     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ae8:				; spl     ($5ae8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5af0:				; spl     (-$10,A0,D5.l*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5af0_1
		 cwde
OP_5af0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5af8:				; spl     $5af8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5af9:				; spl     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setz  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bc0:				; smi     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bc8:				; dbmi    D0, 5bc8:
		 test  dl,80H		;Check Sign
		 jnz   short OP_5bc8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_5bc8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_5bc8_1:
OP_5bc8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bd0:				; smi     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bd8:				; smi     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bdf:				; smi     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5be0:				; smi     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5be7:				; smi     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5be8:				; smi     ($5be8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bf0:				; smi     ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5bf0_1
		 cwde
OP_5bf0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bf8:				; smi     $5bf8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5bf9:				; smi     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 test  dl,80H		;Check Sign
		 setnz AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cc0:				; sge     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cc8:				; dbge    D0, 5cc8:
		 or    edx,200h
		 push  edx
		 popf
		 jge   short OP_5cc8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_5cc8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_5cc8_1:
OP_5cc8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cd0:				; sge     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cd8:				; sge     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cdf:				; sge     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ce0:				; sge     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ce7:				; sge     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ce8:				; sge     ($5ce8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cf0:				; sge     (-$10,A0,D5.l*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5cf0_1
		 cwde
OP_5cf0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cf8:				; sge     $5cf8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5cf9:				; sge     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setge AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5dc0:				; slt     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5dc8:				; dblt    D0, 5dc8:
		 or    edx,200h
		 push  edx
		 popf
		 jl    short OP_5dc8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_5dc8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_5dc8_1:
OP_5dc8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5dd0:				; slt     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5dd8:				; slt     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ddf:				; slt     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5de0:				; slt     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5de7:				; slt     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5de8:				; slt     ($5de8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5df0:				; slt     ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5df0_1
		 cwde
OP_5df0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5df8:				; slt     $5df8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5df9:				; slt     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setl  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ec0:				; sgt     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ec8:				; dbgt    D0, 5ec8:
		 or    edx,200h
		 push  edx
		 popf
		 jg    short OP_5ec8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_5ec8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_5ec8_1:
OP_5ec8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ed0:				; sgt     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ed8:				; sgt     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5edf:				; sgt     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ee0:				; sgt     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ee7:				; sgt     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ee8:				; sgt     ($5ee8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ef0:				; sgt     (-$10,A0,D5.l*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5ef0_1
		 cwde
OP_5ef0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ef8:				; sgt     $5ef8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ef9:				; sgt     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setg  AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fc0:				; sle     D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_D0+ECX*4],AL
		 and   eax,byte 2
		 add   eax,byte 4
		 sub   dword [_m68000_ICount],eax
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fc8:				; dble    D0, 5fc8:
		 or    edx,200h
		 push  edx
		 popf
		 jle   short OP_5fc8_2
		 and   ecx,byte 7
		 mov   ax,[R_D0+ecx*4]
		 dec   ax
		 mov   [R_D0+ecx*4],ax
		 inc   ax		; Is it -1
		 jz    short OP_5fc8_1
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_5fc8_1:
OP_5fc8_2:
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fd0:				; sle     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fd8:				; sle     (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fdf:				; sle     (A7)+:
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fe0:				; sle     -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fe7:				; sle     -(A7):
		 add   esi,byte 2

		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5fe8:				; sle     ($5fe8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ff0:				; sle     ($3456):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_5ff0_1
		 cwde
OP_5ff0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ff8:				; sle     $5ff8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_5ff9:				; sle     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 and   edi,0FFFFFFh
		 or    edx,200h
		 push  edx
		 popf
		 setle AL
		 neg   byte AL
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6000:				; bra     6000:
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6001:				; bra     1:
		 add   esi,byte 2

		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_60ff:				; bra     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6001					; 030/040?

		 add   esi,byte 2

		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6100:				; bsr     6100:
		 add   esi,byte 2

		 mov   edi,[R_A7]      	   ; Get A7
		 mov   eax,esi            ; Get PC
		 sub   edi,byte 4         ; Decrement A7
		 add   eax,byte 2         ; Skip Displacement
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6101:				; bsr     1:
		 add   esi,byte 2

		 mov   edi,[R_A7]      ; Get A7
		 sub   edi,byte 4         ; Decrement
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   edx,ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_61ff:				; bsr     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6101					; 030/040?

		 add   esi,byte 2

		 mov   edi,[R_A7]      ; Get A7
		 mov   eax,esi            ; Get PC
		 sub   edi,byte 4         ; Decrement A7
		 add   eax,byte 2         ; Skip Displacement
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6200:				; bhi     6200:
		 add   esi,byte 2

		 mov   ah,dl
		 sahf
		 ja    short OP_6200_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6200_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6201:				; bhi     1:
		 add   esi,byte 2

		 mov   ah,dl
		 sahf
		 ja    short OP_6201_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6201_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_62ff:				; bhi     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6201					; 030/040?

		 add   esi,byte 2

		 mov   ah,dl
		 sahf
		 ja    short OP_62ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_62ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6300:				; bls     6300:
		 add   esi,byte 2

		 mov   ah,dl
		 sahf
		 jbe   short OP_6300_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6300_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6301:				; bls     1:
		 add   esi,byte 2

		 mov   ah,dl
		 sahf
		 jbe   short OP_6301_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6301_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_63ff:				; bls     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6301					; 030/040?

		 add   esi,byte 2

		 mov   ah,dl
		 sahf
		 jbe   short OP_63ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_63ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6400:				; bcc     6400:
		 add   esi,byte 2

		 test  dl,1H		;check carry
		 jz    short OP_6400_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6400_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6401:				; bcc     1:
		 add   esi,byte 2

		 test  dl,1H		;check carry
		 jz    short OP_6401_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6401_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_64ff:				; bcc     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6401					; 030/040?

		 add   esi,byte 2

		 test  dl,1H		;check carry
		 jz    short OP_64ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_64ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6500:				; bcs     6500:
		 add   esi,byte 2

		 test  dl,1H		;check carry
		 jnz   short OP_6500_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6500_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6501:				; bcs     1:
		 add   esi,byte 2

		 test  dl,1H		;check carry
		 jnz   short OP_6501_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6501_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_65ff:				; bcs     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6501					; 030/040?

		 add   esi,byte 2

		 test  dl,1H		;check carry
		 jnz   short OP_65ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_65ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6600:				; bne     6600:
		 add   esi,byte 2

		 test  dl,40H		;Check zero
		 jz    short OP_6600_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6600_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6601:				; bne     1:
		 add   esi,byte 2

		 test  dl,40H		;Check zero
		 jz    short OP_6601_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6601_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_66ff:				; bne     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6601					; 030/040?

		 add   esi,byte 2

		 test  dl,40H		;Check zero
		 jz    short OP_66ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_66ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6700:				; beq     6700:
		 add   esi,byte 2

		 test  dl,40H		;Check zero
		 jnz   short OP_6700_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6700_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6701:				; beq     1:
		 add   esi,byte 2

		 test  dl,40H		;Check zero
		 jnz   short OP_6701_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6701_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_67ff:				; beq     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6701					; 030/040?

		 add   esi,byte 2

		 test  dl,40H		;Check zero
		 jnz   short OP_67ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_67ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6800:				; bvc     6800:
		 add   esi,byte 2

		 test  dh,8H		;Check Overflow
		 jz    short OP_6800_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6800_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6801:				; bvc     1:
		 add   esi,byte 2

		 test  dh,8H		;Check Overflow
		 jz    short OP_6801_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6801_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_68ff:				; bvc     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6801					; 030/040?

		 add   esi,byte 2

		 test  dh,8H		;Check Overflow
		 jz    short OP_68ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_68ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6900:				; bvs     6900:
		 add   esi,byte 2

		 test  dh,8H		;Check Overflow
		 jnz   short OP_6900_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6900_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6901:				; bvs     1:
		 add   esi,byte 2

		 test  dh,8H		;Check Overflow
		 jnz   short OP_6901_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6901_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_69ff:				; bvs     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6901					; 030/040?

		 add   esi,byte 2

		 test  dh,8H		;Check Overflow
		 jnz   short OP_69ff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_69ff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6a00:				; bpl     6a00:
		 add   esi,byte 2

		 test  dl,80H		;Check Sign
		 jz    short OP_6a00_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6a00_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6a01:				; bpl     1:
		 add   esi,byte 2

		 test  dl,80H		;Check Sign
		 jz    short OP_6a01_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6a01_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6aff:				; bpl     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6a01					; 030/040?

		 add   esi,byte 2

		 test  dl,80H		;Check Sign
		 jz    short OP_6aff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6aff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6b00:				; bmi     6b00:
		 add   esi,byte 2

		 test  dl,80H		;Check Sign
		 jnz   short OP_6b00_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6b00_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6b01:				; bmi     1:
		 add   esi,byte 2

		 test  dl,80H		;Check Sign
		 jnz   short OP_6b01_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6b01_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6bff:				; bmi     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6b01					; 030/040?

		 add   esi,byte 2

		 test  dl,80H		;Check Sign
		 jnz   short OP_6bff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6bff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6c00:				; bge     6c00:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jge   short OP_6c00_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6c00_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6c01:				; bge     1:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jge   short OP_6c01_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6c01_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6cff:				; bge     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6c01					; 030/040?

		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jge   short OP_6cff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6cff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6d00:				; blt     6d00:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jl    short OP_6d00_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6d00_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6d01:				; blt     1:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jl    short OP_6d01_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6d01_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6dff:				; blt     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6d01					; 030/040?

		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jl    short OP_6dff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6dff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6e00:				; bgt     6e00:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jg    short OP_6e00_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6e00_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6e01:				; bgt     1:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jg    short OP_6e01_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6e01_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6eff:				; bgt     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6e01					; 030/040?

		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jg    short OP_6eff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6eff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6f00:				; ble     6f00:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jle   short OP_6f00_1
		 add   esi,byte 2
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6f00_1:
		 movsx EAX,word [esi+ebp]
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6f01:				; ble     1:
		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jle   short OP_6f01_1
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6f01_1:
		 movsx eax,cl               ; Sign Extend displacement
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6fff:				; ble     123456; (2+):
		 test  byte [CPU_TYPE], 3			; CPU Check
		 jz    OP_6f01					; 030/040?

		 add   esi,byte 2

		 or    edx,200h
		 push  edx
		 popf
		 jle   short OP_6fff_1
		 add   esi,byte 4
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_6fff_1:
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,eax
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_7000:				; moveq   #$0, D0:
		 add   esi,byte 2

		 movsx eax,cl
		 shr   ecx,9
		 and   ecx,byte 7
		 test  EAX,EAX
		 pushfd
		 pop   EDX
		 mov   [R_D0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8100:				; sbcd    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 mov   EAX,[R_D0+ECX*4]
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 mov   ebx,edx
		 setc  dl
		 jnz   short OP_8100_1

		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_8100_1:
		 mov   bl,dl
		 and   bl,1
		 shl   bl,7
		 and   dl,7Fh
		 or    dl,bl
		 mov   [R_XC],edx
		 mov   [R_D0+ECX*4],AL
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8108:				; sbcd    -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_8108_notA7_1			;
		 dec   EDI
OP_8108_notA7_1:						;
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_8108_notA7_2			;
		 dec   EDI
OP_8108_notA7_2:						;
		 dec   EDI
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 mov   ebx,edx
		 setc  dl
		 jnz   short OP_8108_1

		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_8108_1:
		 mov   bl,dl
		 and   bl,1
		 shl   bl,7
		 and   dl,7Fh
		 or    dl,bl
		 mov   [R_XC],edx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c100:				; abcd    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 mov   EAX,[R_D0+ECX*4]
		 bt    dword [R_XC],0
		 adc   al,bl
		 daa
		 mov   ebx,edx
		 setc  dl
		 jnz   short OP_c100_1

		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_c100_1:
		 mov   bl,dl
		 and   bl,1
		 shl   bl,7
		 and   dl,7Fh
		 or    dl,bl
		 mov   [R_XC],edx
		 mov   [R_D0+ECX*4],AL
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c108:				; abcd    -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_c108_notA7_1			;
		 dec   EDI
OP_c108_notA7_1:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_c108_notA7_2			;
		 dec   EDI
OP_c108_notA7_2:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 adc   al,bl
		 daa
		 mov   ebx,edx
		 setc  dl
		 jnz   short OP_c108_1

		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_c108_1:
		 mov   bl,dl
		 and   bl,1
		 shl   bl,7
		 and   dl,7Fh
		 or    dl,bl
		 mov   [R_XC],edx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8000:				; or.b    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8010:				; or.b    (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8018:				; or.b    (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_801f:				; or.b    (A7)+, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8020:				; or.b    -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8027:				; or.b    -(A7), D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8028:				; or.b    (-$7fd8,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8030:				; or.b    ($30,A0,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_8030_1
		 cwde
OP_8030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8038:				; or.b    $8038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8039:				; or.b    $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_803a:				; or.b    (-$7fc6,PC), D0; ($ffff8038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_803b:				; or.b    ($3b,PC,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_803b_1
		 cwde
OP_803b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_803c:				; or.b    #$0, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 or    [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8040:				; or.w    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8050:				; or.w    (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8058:				; or.w    (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8060:				; or.w    -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8068:				; or.w    (-$7f98,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8070:				; or.w    ($70,A0,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_8070_1
		 cwde
OP_8070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8078:				; or.w    $8078.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8079:				; or.w    $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_807a:				; or.w    (-$7f86,PC), D0; ($ffff8078):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_807b:				; or.w    ($7b,PC,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_807b_1
		 cwde
OP_807b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_807c:				; or.w    #$807c, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 or    [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8080:				; or.l    D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8090:				; or.l    (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8098:				; or.l    (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80a0:				; or.l    -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80a8:				; or.l    (-$7f58,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80b0:				; or.l    (-$50,A0,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_80b0_1
		 cwde
OP_80b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80b8:				; or.l    $80b8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80b9:				; or.l    $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80ba:				; or.l    (-$7f46,PC), D0; ($ffff80b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80bb:				; or.l    (-$45,PC,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_80bb_1
		 cwde
OP_80bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80bc:				; or.l    #$123456, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 or    [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8110:				; or.b    D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8118:				; or.b    D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_811f:				; or.b    D0, (A7)+:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8120:				; or.b    D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8127:				; or.b    D0, -(A7):
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8128:				; or.b    D0, (-$7ed8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8130:				; or.b    D0, ($3456,A0,A0.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_8130_1
		 cwde
OP_8130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8138:				; or.b    D0, $8138.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8139:				; or.b    D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8150:				; or.w    D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8158:				; or.w    D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8160:				; or.w    D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8168:				; or.w    D0, (-$7e98,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8170:				; or.w    D0, ($3456,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_8170_1
		 cwde
OP_8170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8178:				; or.w    D0, $8178.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8179:				; or.w    D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8190:				; or.l    D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_8198:				; or.l    D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81a0:				; or.l    D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81a8:				; or.l    D0, (-$7e58,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81b0:				; or.l    D0, ($3456,A0.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_81b0_1
		 cwde
OP_81b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81b8:				; or.l    D0, $81b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81b9:				; or.l    D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 or    EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9000:				; sub.b   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9010:				; sub.b   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9018:				; sub.b   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_901f:				; sub.b   (A7)+, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9020:				; sub.b   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9027:				; sub.b   -(A7), D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9028:				; sub.b   (-$6fd8,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9030:				; sub.b   ($30,A0,A1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_9030_1
		 cwde
OP_9030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9038:				; sub.b   $9038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9039:				; sub.b   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_903a:				; sub.b   (-$6fc6,PC), D0; ($ffff9038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_903b:				; sub.b   ($3b,PC,A1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_903b_1
		 cwde
OP_903b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_903c:				; sub.b   #$0, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 sub   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9040:				; sub.w   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9050:				; sub.w   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9058:				; sub.w   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9060:				; sub.w   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9068:				; sub.w   (-$6f98,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9070:				; sub.w   ($70,A0,A1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_9070_1
		 cwde
OP_9070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9078:				; sub.w   $9078.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9079:				; sub.w   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_907a:				; sub.w   (-$6f86,PC), D0; ($ffff9078):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_907b:				; sub.w   ($7b,PC,A1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_907b_1
		 cwde
OP_907b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_907c:				; sub.w   #$907c, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 sub   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9080:				; sub.l   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9090:				; sub.l   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9098:				; sub.l   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90a0:				; sub.l   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90a8:				; sub.l   (-$6f58,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90b0:				; sub.l   (-$50,A0,A1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_90b0_1
		 cwde
OP_90b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90b8:				; sub.l   $90b8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90b9:				; sub.l   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90ba:				; sub.l   (-$6f46,PC), D0; ($ffff90b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90bb:				; sub.l   (-$45,PC,A1.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_90bb_1
		 cwde
OP_90bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90bc:				; sub.l   #$123456, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 sub   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9110:				; sub.b   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9118:				; sub.b   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_911f:				; sub.b   D0, (A7)+:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9120:				; sub.b   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9127:				; sub.b   D0, -(A7):
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9128:				; sub.b   D0, (-$6ed8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9130:				; sub.b   D0, ($3456,A0,A1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_9130_1
		 cwde
OP_9130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9138:				; sub.b   D0, $9138.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9139:				; sub.b   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9150:				; sub.w   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9158:				; sub.w   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9160:				; sub.w   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9168:				; sub.w   D0, (-$6e98,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9170:				; sub.w   D0, ($3456,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_9170_1
		 cwde
OP_9170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9178:				; sub.w   D0, $9178.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9179:				; sub.w   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9190:				; sub.l   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9198:				; sub.l   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91a0:				; sub.l   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91a8:				; sub.l   D0, (-$6e58,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91b0:				; sub.l   D0, ($3456,A1.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_91b0_1
		 cwde
OP_91b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91b8:				; sub.l   D0, $91b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91b9:				; sub.l   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 sub   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90c0:				; suba.w  D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90d0:				; suba.w  (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90d8:				; suba.w  (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90e0:				; suba.w  -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90e8:				; suba.w  (-$6f18,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90f0:				; suba.w  (-$10,A0,A1.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_90f0_1
		 cwde
OP_90f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90f8:				; suba.w  $90f8.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90f9:				; suba.w  $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90fa:				; suba.w  (-$6f06,PC), A0; ($ffff90f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90fb:				; suba.w  (-$5,PC,A1.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_90fb_1
		 cwde
OP_90fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_90fc:				; suba.w  #$90fc, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 cwde
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91c0:				; suba.l  D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91d0:				; suba.l  (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91d8:				; suba.l  (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91e0:				; suba.l  -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91e8:				; suba.l  (-$6e18,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91f0:				; suba.l  ($3456), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_91f0_1
		 cwde
OP_91f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91f8:				; suba.l  $91f8.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91f9:				; suba.l  $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91fa:				; suba.l  (-$6e06,PC), A0; ($ffff91f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91fb:				; suba.l  ([$3456],$3456), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_91fb_1
		 cwde
OP_91fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_91fc:				; suba.l  #$123456, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 sub   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b000:				; cmp.b   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b010:				; cmp.b   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b018:				; cmp.b   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b01f:				; cmp.b   (A7)+, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b020:				; cmp.b   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b027:				; cmp.b   -(A7), D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b028:				; cmp.b   (-$4fd8,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b030:				; cmp.b   ($30,A0,A3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b030_1
		 cwde
OP_b030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b038:				; cmp.b   $b038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b039:				; cmp.b   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b03a:				; cmp.b   (-$4fc6,PC), D0; ($ffffb038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b03b:				; cmp.b   ($3b,PC,A3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b03b_1
		 cwde
OP_b03b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b03c:				; cmp.b   #$0, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 cmp   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b040:				; cmp.w   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b050:				; cmp.w   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b058:				; cmp.w   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b060:				; cmp.w   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b068:				; cmp.w   (-$4f98,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b070:				; cmp.w   ($70,A0,A3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b070_1
		 cwde
OP_b070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b078:				; cmp.w   $b078.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b079:				; cmp.w   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b07a:				; cmp.w   (-$4f86,PC), D0; ($ffffb078):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b07b:				; cmp.w   ($7b,PC,A3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b07b_1
		 cwde
OP_b07b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b07c:				; cmp.w   #$b07c, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 cmp   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b080:				; cmp.l   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b090:				; cmp.l   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b098:				; cmp.l   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0a0:				; cmp.l   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0a8:				; cmp.l   (-$4f58,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0b0:				; cmp.l   (-$50,A0,A3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b0b0_1
		 cwde
OP_b0b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0b8:				; cmp.l   $b0b8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0b9:				; cmp.l   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0ba:				; cmp.l   (-$4f46,PC), D0; ($ffffb0b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0bb:				; cmp.l   (-$45,PC,A3.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b0bb_1
		 cwde
OP_b0bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0bc:				; cmp.l   #$123456, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 cmp   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0c0:				; cmpa.w  D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0d0:				; cmpa.w  (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0d8:				; cmpa.w  (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0e0:				; cmpa.w  -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0e8:				; cmpa.w  (-$4f18,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0f0:				; cmpa.w  (-$10,A0,A3.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b0f0_1
		 cwde
OP_b0f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0f8:				; cmpa.w  $b0f8.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0f9:				; cmpa.w  $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0fa:				; cmpa.w  (-$4f06,PC), A0; ($ffffb0f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0fb:				; cmpa.w  (-$5,PC,A3.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b0fb_1
		 cwde
OP_b0fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b0fc:				; cmpa.w  #$b0fc, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 cwde
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1c0:				; cmpa.l  D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1d0:				; cmpa.l  (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1d8:				; cmpa.l  (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1e0:				; cmpa.l  -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1e8:				; cmpa.l  (-$4e18,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1f0:				; cmpa.l  ($3456), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b1f0_1
		 cwde
OP_b1f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1f8:				; cmpa.l  $b1f8.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1f9:				; cmpa.l  $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1fa:				; cmpa.l  (-$4e06,PC), A0; ($ffffb1f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1fb:				; cmpa.l  ([$3456],$3456), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b1fb_1
		 cwde
OP_b1fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1fc:				; cmpa.l  #$123456, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 cmp   [R_A0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0c0:				; adda.w  D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0d0:				; adda.w  (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0d8:				; adda.w  (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0e0:				; adda.w  -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0e8:				; adda.w  (-$2f18,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0f0:				; adda.w  (-$10,A0,A5.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d0f0_1
		 cwde
OP_d0f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0f8:				; adda.w  $d0f8.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0f9:				; adda.w  $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0fa:				; adda.w  (-$2f06,PC), A0; ($ffffd0f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0fb:				; adda.w  (-$5,PC,A5.w), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d0fb_1
		 cwde
OP_d0fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0fc:				; adda.w  #$d0fc, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 cwde
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1c0:				; adda.l  D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1d0:				; adda.l  (A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1d8:				; adda.l  (A0)+, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1e0:				; adda.l  -(A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1e8:				; adda.l  (-$2e18,A0), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1f0:				; adda.l  ($3456), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d1f0_1
		 cwde
OP_d1f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1f8:				; adda.l  $d1f8.w, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1f9:				; adda.l  $123456.l, A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1fa:				; adda.l  (-$2e06,PC), A0; ($ffffd1f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1fb:				; adda.l  ([$3456],$3456), A0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d1fb_1
		 cwde
OP_d1fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [R_CCR],edx
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDX,[R_CCR]
		 mov   EDI,[Safe_EDI]
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1fc:				; adda.l  #$123456, A0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 add   [R_A0+ECX*4],EAX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b100:				; eor.b   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_D0+EBX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b110:				; eor.b   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b118:				; eor.b   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b11f:				; eor.b   D0, (A7)+:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b120:				; eor.b   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b127:				; eor.b   D0, -(A7):
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b128:				; eor.b   D0, (-$4ed8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b130:				; eor.b   D0, ($3456,A0,A3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b130_1
		 cwde
OP_b130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b138:				; eor.b   D0, $b138.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b139:				; eor.b   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b140:				; eor.w   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_D0+EBX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b150:				; eor.w   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b158:				; eor.w   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b160:				; eor.w   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b168:				; eor.w   D0, (-$4e98,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b170:				; eor.w   D0, ($3456,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b170_1
		 cwde
OP_b170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b178:				; eor.w   D0, $b178.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b179:				; eor.w   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b180:				; eor.l   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_D0+EBX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b190:				; eor.l   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b198:				; eor.l   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1a0:				; eor.l   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1a8:				; eor.l   D0, (-$4e58,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1b0:				; eor.l   D0, ($3456,A3.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_b1b0_1
		 cwde
OP_b1b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1b8:				; eor.l   D0, $b1b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b1b9:				; eor.l   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c000:				; and.b   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c010:				; and.b   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c018:				; and.b   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c01f:				; and.b   (A7)+, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c020:				; and.b   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c027:				; and.b   -(A7), D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c028:				; and.b   (-$3fd8,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c030:				; and.b   ($30,A0,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c030_1
		 cwde
OP_c030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c038:				; and.b   $c038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c039:				; and.b   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c03a:				; and.b   (-$3fc6,PC), D0; ($ffffc038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c03b:				; and.b   ($3b,PC,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c03b_1
		 cwde
OP_c03b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c03c:				; and.b   #$0, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 and   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c040:				; and.w   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c050:				; and.w   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c058:				; and.w   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c060:				; and.w   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c068:				; and.w   (-$3f98,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c070:				; and.w   ($70,A0,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c070_1
		 cwde
OP_c070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c078:				; and.w   $c078.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c079:				; and.w   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c07a:				; and.w   (-$3f86,PC), D0; ($ffffc078):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c07b:				; and.w   ($7b,PC,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c07b_1
		 cwde
OP_c07b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c07c:				; and.w   #$c07c, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 and   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c080:				; and.l   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c090:				; and.l   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c098:				; and.l   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0a0:				; and.l   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0a8:				; and.l   (-$3f58,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0b0:				; and.l   (-$50,A0,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c0b0_1
		 cwde
OP_c0b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0b8:				; and.l   $c0b8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0b9:				; and.l   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0ba:				; and.l   (-$3f46,PC), D0; ($ffffc0b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0bb:				; and.l   (-$45,PC,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c0bb_1
		 cwde
OP_c0bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0bc:				; and.l   #$123456, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 and   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c110:				; and.b   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c118:				; and.b   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c11f:				; and.b   D0, (A7)+:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c120:				; and.b   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c127:				; and.b   D0, -(A7):
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c128:				; and.b   D0, (-$3ed8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c130:				; and.b   D0, ($3456,A0,A4.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c130_1
		 cwde
OP_c130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c138:				; and.b   D0, $c138.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c139:				; and.b   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c150:				; and.w   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c158:				; and.w   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c160:				; and.w   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c168:				; and.w   D0, (-$3e98,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c170:				; and.w   D0, ($3456,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c170_1
		 cwde
OP_c170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c178:				; and.w   D0, $c178.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c179:				; and.w   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c190:				; and.l   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c198:				; and.l   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1a0:				; and.l   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1a8:				; and.l   D0, (-$3e58,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1b0:				; and.l   D0, ($3456,A4.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c1b0_1
		 cwde
OP_c1b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1b8:				; and.l   D0, $c1b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1b9:				; and.l   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 and   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d000:				; add.b   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d010:				; add.b   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d018:				; add.b   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d01f:				; add.b   (A7)+, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d020:				; add.b   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d027:				; add.b   -(A7), D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d028:				; add.b   (-$2fd8,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d030:				; add.b   ($30,A0,A5.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d030_1
		 cwde
OP_d030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d038:				; add.b   $d038.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d039:				; add.b   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d03a:				; add.b   (-$2fc6,PC), D0; ($ffffd038):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d03b:				; add.b   ($3b,PC,A5.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d03b_1
		 cwde
OP_d03b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d03c:				; add.b   #$0, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 add   [R_D0+ECX*4],AL
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d040:				; add.w   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d050:				; add.w   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d058:				; add.w   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d060:				; add.w   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d068:				; add.w   (-$2f98,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d070:				; add.w   ($70,A0,A5.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d070_1
		 cwde
OP_d070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d078:				; add.w   $d078.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d079:				; add.w   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d07a:				; add.w   (-$2f86,PC), D0; ($ffffd078):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d07b:				; add.w   ($7b,PC,A5.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d07b_1
		 cwde
OP_d07b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d07c:				; add.w   #$d07c, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 add   [R_D0+ECX*4],AX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d080:				; add.l   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 15
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,[R_D0+EBX*4]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d090:				; add.l   (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d098:				; add.l   (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0a0:				; add.l   -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0a8:				; add.l   (-$2f58,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0b0:				; add.l   (-$50,A0,A5.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d0b0_1
		 cwde
OP_d0b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0b8:				; add.l   $d0b8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0b9:				; add.l   $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0ba:				; add.l   (-$2f46,PC), D0; ($ffffd0b8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0bb:				; add.l   (-$45,PC,A5.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d0bb_1
		 cwde
OP_d0bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d0bc:				; add.l   #$123456, D0:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EAX,dword [esi+ebp]
		 rol   EAX,16
		 add   esi,byte 4
		 add   [R_D0+ECX*4],EAX
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d110:				; add.b   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d118:				; add.b   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d11f:				; add.b   D0, (A7)+:
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 add   dword [R_A7],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d120:				; add.b   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d127:				; add.b   D0, -(A7):
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   edi,[R_A7]    ; Get A7
		 sub   edi,byte 2
		 mov   [R_A7],edi
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d128:				; add.b   D0, (-$2ed8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d130:				; add.b   D0, ($3456,A0,A5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d130_1
		 cwde
OP_d130_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d138:				; add.b   D0, $d138.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d139:				; add.b   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AL,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d150:				; add.w   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d158:				; add.w   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d160:				; add.w   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d168:				; add.w   D0, (-$2e98,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d170:				; add.w   D0, ($3456,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d170_1
		 cwde
OP_d170_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d178:				; add.w   D0, $d178.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d179:				; add.w   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   AX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d190:				; add.l   D0, (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d198:				; add.l   D0, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1a0:				; add.l   D0, -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1a8:				; add.l   D0, (-$2e58,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1b0:				; add.l   D0, ($3456,A5.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_d1b0_1
		 cwde
OP_d1b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1b8:				; add.l   D0, $d1b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d1b9:				; add.l   D0, $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 add   EAX,[R_D0+ECX*4]
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9100:				; subx.b  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 bt    dword [R_XC],0
		 sbb   [R_D0+ecx*4],BL
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_9100_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_9100_1:
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9108:				; subx.b  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_9108_notA7_1			;
		 dec   EDI
OP_9108_notA7_1:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_9108_notA7_2			;
		 dec   EDI
OP_9108_notA7_2:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 sbb   AL,BL
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_9108_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_9108_1:
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9140:				; subx.w  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 bt    dword [R_XC],0
		 sbb   [R_D0+ecx*4],BX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_9140_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_9140_1:
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9148:				; subx.w  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 sbb   AX,BX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_9148_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_9148_1:
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9180:				; subx.l  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 bt    dword [R_XC],0
		 sbb   [R_D0+ecx*4],EBX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_9180_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_9180_1:
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_9188:				; subx.l  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 sbb   EAX,EBX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_9188_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_9188_1:
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d100:				; addx.b  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 bt    dword [R_XC],0
		 adc   [R_D0+ecx*4],BL
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_d100_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_d100_1:
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d108:				; addx.b  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 dec   EDI
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_d108_notA7_1			;
		 dec   EDI
OP_d108_notA7_1:						;
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_d108_notA7_2			;
		 dec   EDI
OP_d108_notA7_2:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 adc   AL,BL
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_d108_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_d108_1:
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d140:				; addx.w  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 bt    dword [R_XC],0
		 adc   [R_D0+ecx*4],BX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_d140_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_d140_1:
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d148:				; addx.w  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 adc   AX,BX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_d148_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_d148_1:
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d180:				; addx.l  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EBX,[R_D0+EBX*4]
		 bt    dword [R_XC],0
		 adc   [R_D0+ecx*4],EBX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_d180_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_d180_1:
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_d188:				; addx.l  -(A0), -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 bt    dword [R_XC],0
		 adc   EAX,EBX
		 mov   ebx,edx
		 pushfd
		 pop   EDX
		 mov   [R_XC],edx
		 jnz   short OP_d188_1

		 and   dl,0BFh       ; Remove Z
		 and   bl,40h        ; Mask out Old Z
		 or    dl,bl         ; Copy across

OP_d188_1:
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80c0:				; divu.w  D0, D0:
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],133
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,[R_D0+EBX*4]
		 test  ax,ax
		 je    near OP_80c0_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80c0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80c0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80c0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080c0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080c0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80d0:				; divu.w  (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],137
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80d0_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80d0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80d0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80d0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080d0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080d0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80d8:				; divu.w  (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],137
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80d8_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80d8_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80d8_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80d8_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080d8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080d8_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80e0:				; divu.w  -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],139
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80e0_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80e0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80e0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80e0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080e0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080e0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80e8:				; divu.w  (-$7f18,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],141
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80e8_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80e8_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80e8_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80e8_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080e8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080e8_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f0:				; divu.w  (-$10,A0,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],145
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_80f0_2
		 cwde
OP_80f0_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80f0_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80f0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080f0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080f0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f8:				; divu.w  $80f8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],141
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80f8_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80f8_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f8_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f8_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080f8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080f8_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f9:				; divu.w  $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],145
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80f9_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80f9_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f9_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80f9_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080f9_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080f9_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fa:				; divu.w  (-$7f06,PC), D0; ($ffff80f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],141
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80fa_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80fa_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fa_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fa_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080fa_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080fa_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fb:				; divu.w  (-$5,PC,A0.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],143
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_80fb_2
		 cwde
OP_80fb_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_80fb_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80fb_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fb_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fb_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080fb_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080fb_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fc:				; divu.w  #$80fc, D0:
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],137
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  ax,ax
		 je    near OP_80fc_1_ZERO		;do div by zero trap
		 movzx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 xor   edx,edx
		 div   ebx
		 test  eax, 0FFFF0000H
		 jnz   short OP_80fc_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fc_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_80fc_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 95
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_080fc_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_080fc_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81c0:				; divs.w  D0, D0:
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],150
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,[R_D0+EBX*4]
		 test  ax,ax
		 je    near OP_81c0_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81c0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81c0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81c0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081c0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081c0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81d0:				; divs.w  (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],154
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81d0_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81d0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81d0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81d0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081d0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081d0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81d8:				; divs.w  (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],154
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81d8_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81d8_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81d8_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81d8_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081d8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081d8_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81e0:				; divs.w  -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],156
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81e0_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81e0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81e0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81e0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081e0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081e0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81e8:				; divs.w  (-$7e18,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],158
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81e8_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81e8_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81e8_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81e8_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081e8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081e8_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f0:				; divs.w  ($3456), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],162
		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_81f0_2
		 cwde
OP_81f0_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81f0_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81f0_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f0_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f0_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081f0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081f0_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f8:				; divs.w  $81f8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],158
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81f8_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81f8_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f8_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f8_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081f8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081f8_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f9:				; divs.w  $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],162
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81f9_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81f9_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f9_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81f9_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081f9_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081f9_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fa:				; divs.w  (-$7e06,PC), D0; ($ffff81f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],158
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81fa_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81fa_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fa_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fa_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081fa_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081fa_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fb:				; divs.w  ([$3456],$3456), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],160
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_81fb_2
		 cwde
OP_81fb_2:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 test  ax,ax
		 je    near OP_81fb_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81fb_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fb_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fb_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081fb_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081fb_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fc:				; divs.w  #$81fc, D0:
		 add   esi,byte 2

		 mov   [R_CCR],edx
		 sub   dword [_m68000_ICount],154
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 test  ax,ax
		 je    near OP_81fc_1_ZERO		;do div by zero trap
		 movsx ebx,ax
		 mov   EAX,[R_D0+ECX*4]
		 cdq
		 idiv  ebx
		 movsx ebx,ax
		 cmp   eax,ebx
		 jne   short OP_81fc_1_OVER
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  DX,DX
		 pushfd
		 pop   EDX
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fc_1_OVER:
		 mov   edx,[R_CCR]
		 or    dh,8h		;V flag
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_81fc_1_ZERO:		 ;Do divide by zero trap
		 add   dword [_m68000_ICount],byte 112
;		 sub   esi,byte 2
		 mov   al,5
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_081fc_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_081fc_Bank:
		 or    dword [_m68000_ICount],byte 0
		 jle   near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4840:				; swap    D0:
		 add   esi,byte 2

		 and   ecx, byte 7
		 ror   dword [R_D0+ECX*4],16
		 or    dword [R_D0+ECX*4],0
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4000:				; negx.b  D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4010:				; negx.b  (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4018:				; negx.b  (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_4018_notA7			;
		 inc   dword [R_A0+ECX*4]		;
OP_4018_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4020:				; negx.b  -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_4020_notA7			;
		 dec   EDI				;
OP_4020_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4028:				; negx.b  ($4028,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4030:				; negx.b  ($30,A0,D4.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4030_1
		 cwde
OP_4030_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4038:				; negx.b  $4038.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4039:				; negx.b  $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 bt    dword [R_XC],0
		 sbb   AL,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4040:				; negx.w  D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4050:				; negx.w  (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4058:				; negx.w  (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4060:				; negx.w  -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4068:				; negx.w  ($4068,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4070:				; negx.w  ($70,A0,D4.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4070_1
		 cwde
OP_4070_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4078:				; negx.w  $4078.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4079:				; negx.w  $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 bt    dword [R_XC],0
		 sbb   AX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4080:				; negx.l  D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4090:				; negx.l  (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4098:				; negx.l  (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40a0:				; negx.l  -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40a8:				; negx.l  ($40a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40b0:				; negx.l  (-$50,A0,D4.w):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_40b0_1
		 cwde
OP_40b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40b8:				; negx.l  $40b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_40b9:				; negx.l  $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 bt    dword [R_XC],0
		 sbb   EAX,0
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4200:				; clr.b   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   [R_D0+ECX*4],AL
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4210:				; clr.b   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4218:				; clr.b   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_4218_notA7			;
		 inc   dword [R_A0+ECX*4]		;
OP_4218_notA7:						;
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4220:				; clr.b   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_4220_notA7			;
		 dec   EDI				;
OP_4220_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4228:				; clr.b   ($4228,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4230:				; clr.b   ($30,A0,D4.w*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4230_1
		 cwde
OP_4230_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4238:				; clr.b   $4238.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 xor   eax,eax
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4239:				; clr.b   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 xor   eax,eax
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4240:				; clr.w   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   [R_D0+ECX*4],AX
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4250:				; clr.w   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4258:				; clr.w   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4260:				; clr.w   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4268:				; clr.w   ($4268,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4270:				; clr.w   ($70,A0,D4.w*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4270_1
		 cwde
OP_4270_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4278:				; clr.w   $4278.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 xor   eax,eax
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4279:				; clr.w   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 xor   eax,eax
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_word@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4280:				; clr.l   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   [R_D0+ECX*4],EAX
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4290:				; clr.l   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4298:				; clr.l   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42a0:				; clr.l   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42a8:				; clr.l   ($42a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 push  EAX
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42b0:				; clr.l   (-$50,A0,D4.w*2):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 xor   eax,eax
		 push  EAX
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_42b0_1
		 cwde
OP_42b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42b8:				; clr.l   $42b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 xor   eax,eax
		 push  EAX
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_42b9:				; clr.l   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 xor   eax,eax
		 push  EAX
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 pop   EAX
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   edx,40H
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4400:				; neg.b   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 neg   AL
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4410:				; neg.b   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4418:				; neg.b   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_4418_notA7			;
		 inc   dword [R_A0+ECX*4]		;
OP_4418_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4420:				; neg.b   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_4420_notA7			;
		 dec   EDI				;
OP_4420_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4428:				; neg.b   ($4428,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4430:				; neg.b   ($30,A0,D4.w*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4430_1
		 cwde
OP_4430_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4438:				; neg.b   $4438.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4439:				; neg.b   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AL
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4440:				; neg.w   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 neg   AX
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4450:				; neg.w   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4458:				; neg.w   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4460:				; neg.w   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4468:				; neg.w   ($4468,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4470:				; neg.w   ($70,A0,D4.w*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4470_1
		 cwde
OP_4470_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4478:				; neg.w   $4478.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4479:				; neg.w   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   AX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4480:				; neg.l   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 neg   EAX
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4490:				; neg.l   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4498:				; neg.l   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44a0:				; neg.l   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44a8:				; neg.l   ($44a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44b0:				; neg.l   (-$50,A0,D4.w*4):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_44b0_1
		 cwde
OP_44b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44b8:				; neg.l   $44b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_44b9:				; neg.l   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 neg   EAX
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4600:				; not.b   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 xor   AL,-1
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4610:				; not.b   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4618:				; not.b   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_4618_notA7			;
		 inc   dword [R_A0+ECX*4]		;
OP_4618_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4620:				; not.b   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_4620_notA7			;
		 dec   EDI				;
OP_4620_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4628:				; not.b   ($4628,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4630:				; not.b   ($30,A0,D4.w*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4630_1
		 cwde
OP_4630_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4638:				; not.b   $4638.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4639:				; not.b   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AL,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4640:				; not.w   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 xor   AX,-1
		 pushfd
		 mov   [R_D0+ECX*4],AX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4650:				; not.w   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4658:				; not.w   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4660:				; not.w   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4668:				; not.w   ($4668,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4670:				; not.w   ($70,A0,D4.w*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4670_1
		 cwde
OP_4670_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4678:				; not.w   $4678.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4679:				; not.w   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   AX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_word@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4680:				; not.l   D0:
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 xor   EAX,-1
		 pushfd
		 mov   [R_D0+ECX*4],EAX
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4690:				; not.l   (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4698:				; not.l   (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46a0:				; not.l   -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 4
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46a8:				; not.l   ($46a8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46b0:				; not.l   (-$50,A0,D4.w*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_46b0_1
		 cwde
OP_46b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46b8:				; not.l   $46b8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_46b9:				; not.l   $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 xor   EAX,-1
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24_dword@8
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4e60:				; move    A0, USP
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 jz    short OP_4e60_Trap
		 and   ecx,7
		 mov   eax,[R_A0+ECX*4]
		 mov   [R_USP],eax
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_4e60_Trap:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04e60_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04e60_Bank:
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4e68:				; move    USP, A0
		 add   esi,byte 2

		 test  byte [R_SR_H],20h 			; Supervisor Mode ?
		 jz    short OP_4e68_Trap
		 and   ecx,7
		 mov   eax,[R_USP]
		 mov   [R_A0+ECX*4],eax
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

OP_4e68_Trap:
;		 sub   esi,byte 2
		 mov   al,8
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04e68_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04e68_Bank:
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4180:				; chk.w   D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_4180_Trap_minus
		 and   ecx,byte 7
		 mov   EAX,[R_D0+ECX*4]
		 cmp   bx,ax
		 jg    near OP_4180_Trap_over
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4180_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04180_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04180_Bank:
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4180_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_14180_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_14180_Bank:
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4190:				; chk.w   (A0), D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_4190_Trap_minus
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_4190_Trap_over
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4190_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04190_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04190_Bank:
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4190_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_14190_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_14190_Bank:
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4198:				; chk.w   (A0)+, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_4198_Trap_minus
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_4198_Trap_over
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4198_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04198_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04198_Bank:
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4198_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_14198_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_14198_Bank:
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41a0:				; chk.w   -(A0), D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41a0_Trap_minus
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_41a0_Trap_over
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41a0_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041a0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041a0_Bank:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41a0_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141a0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141a0_Bank:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41a8:				; chk.w   ($41a8,A0), D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41a8_Trap_minus
		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_41a8_Trap_over
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41a8_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041a8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041a8_Bank:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41a8_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141a8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141a8_Bank:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b0:				; chk.w   ($3456,D4.w), D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41b0_Trap_minus
		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_41b0_1
		 cwde
OP_41b0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_41b0_Trap_over
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b0_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041b0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041b0_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b0_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141b0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141b0_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b8:				; chk.w   $41b8.w, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41b8_Trap_minus
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_41b8_Trap_over
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b8_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041b8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041b8_Bank:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b8_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141b8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141b8_Bank:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b9:				; chk.w   $123456.l, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41b9_Trap_minus
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_41b9_Trap_over
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b9_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041b9_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041b9_Bank:
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41b9_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141b9_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141b9_Bank:
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41ba:				; chk.w   ($41ba,PC), D0; ($41b8):
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41ba_Trap_minus
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_41ba_Trap_over
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41ba_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041ba_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041ba_Bank:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41ba_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141ba_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141ba_Bank:
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41bb:				; chk.w   ([$3456,D4.w],$3456), D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41bb_Trap_minus
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_41bb_1
		 cwde
OP_41bb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   bx,ax
		 jg    near OP_41bb_Trap_over
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41bb_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041bb_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041bb_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41bb_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141bb_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141bb_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41bc:				; chk.w   #$41bc, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 shr   ebx,byte 9
		 and   ebx,byte 7
		 mov   ebx,[R_D0+EBX*4]
		 test  bh,80h
		 jnz   near OP_41bc_Trap_minus
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 cmp   bx,ax
		 jg    near OP_41bc_Trap_over
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41bc_Trap_minus:
		 or    dl,80h
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_041bc_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_041bc_Bank:
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_41bc_Trap_over:
		 and   dl,7Fh
;		 sub   esi,byte 2
		 mov   al,6
		 call  Exception

		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_141bc_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_141bc_Bank:
		 sub   dword [_m68000_ICount],byte 10
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c140:				; exg     D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   eax,[R_D0+ECX*4]
		 mov   edi,[R_D0+EBX*4]
		 mov   [R_D0+ECX*4],edi
		 mov   [R_D0+EBX*4],eax
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c148:				; exg     A0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   eax,[R_A0+ECX*4]
		 mov   edi,[R_A0+EBX*4]
		 mov   [R_A0+ECX*4],edi
		 mov   [R_A0+EBX*4],eax
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c188:				; exg     D0, A0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx,byte 9
		 and   ecx,byte 7
		 mov   eax,[R_D0+ECX*4]
		 mov   edi,[R_A0+EBX*4]
		 mov   [R_D0+ECX*4],edi
		 mov   [R_A0+EBX*4],eax
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b108:				; cmpm.b  (A0)+, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 inc   dword [R_A0+EBX*4]
		 cmp   ebx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_b108_notA7_1			;
		 inc   dword [R_A0+EBX*4]		;
OP_b108_notA7_1:					;
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_b108_notA7_2			;
		 inc   dword [R_A0+ECX*4]		;
OP_b108_notA7_2:					;
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24@4
		 cmp   AL,BL
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b148:				; cmpm.w  (A0)+, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 2
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_word@4
		 cmp   AX,BX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_b188:				; cmpm.l  (A0)+, (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx, byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 4
		 mov   [R_PC],ESI
		 mov   [Safe_ECX],ECX
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   ECX,[Safe_ECX]
		 mov   EBX,EAX
		 mov   EDI,[R_A0+ECX*4]
		 add   dword [R_A0+ECX*4],byte 4
		 mov   [R_PC],ESI
		 mov   ecx,EDI
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 cmp   EAX,EBX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0c0:				; mulu.w  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,[R_D0+EBX*4]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 70
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0d0:				; mulu.w  (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 74
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0d8:				; mulu.w  (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 74
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0e0:				; mulu.w  -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 76
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0e8:				; mulu.w  (-$3f18,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 78
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0f0:				; mulu.w  (-$10,A0,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c0f0_1
		 cwde
OP_c0f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 80
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0f8:				; mulu.w  $c0f8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 78
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0f9:				; mulu.w  $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 82
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0fa:				; mulu.w  (-$3f06,PC), D0; ($ffffc0f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 78
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0fb:				; mulu.w  (-$5,PC,A4.w), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c0fb_1
		 cwde
OP_c0fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 80
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c0fc:				; mulu.w  #$c0fc, D0:
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mul   word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 70
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1c0:				; muls.w  D0, D0:
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,[R_D0+EBX*4]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 70
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1d0:				; muls.w  (A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 74
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1d8:				; muls.w  (A0)+, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 add   dword [R_A0+EBX*4],byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 74
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1e0:				; muls.w  -(A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 sub   EDI,byte 2
		 mov   [R_A0+EBX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 76
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1e8:				; muls.w  (-$3e18,A0), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+EBX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 78
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1f0:				; muls.w  ($3456), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   ebx,ecx
		 and   ebx,byte 7
		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,[R_A0+EBX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c1f0_1
		 cwde
OP_c1f0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 80
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1f8:				; muls.w  $c1f8.w, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 78
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1f9:				; muls.w  $123456.l, D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 82
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1fa:				; muls.w  (-$3e06,PC), D0; ($ffffc1f8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 78
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1fb:				; muls.w  ([$3456],$3456), D0:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_c1fb_1
		 cwde
OP_c1fb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 80
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_c1fc:				; muls.w  #$c1fc, D0:
		 add   esi,byte 2

		 shr   ecx, byte 9
		 and   ecx, byte 7
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 imul  word [R_D0+ECX*4]
		 shl   edx, byte 16
		 mov   dx,ax
		 mov   [R_D0+ECX*4],edx
		 test  EDX,EDX
		 pushfd
		 pop   EDX
		 sub   dword [_m68000_ICount],byte 70
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4e77:				; rtr:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,[R_A7]
		 add   dword [R_A7],byte 6
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_word@4
		 mov   EDI,[Safe_EDI]
		 add   edi,byte 2
		 mov   esi,eax
		 mov   [R_PC],ESI
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24_dword@4
		 mov   EDI,[Safe_EDI]
		 xchg  esi,eax
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04e77_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04e77_Bank:
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4e75:				; rts:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 mov   eax,[R_A7]
		 add   dword [R_A7],byte 4
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   ecx,EAX
		 and   ecx,0FFFFFFh
		 call  @cpu_readmem24_dword@4
		 mov   EDX,[R_CCR]
		 mov   esi,eax
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04e75_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04e75_Bank:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4e90:				; jsr     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   eax,esi		; Old PC
		 mov   ebx,[R_A7]	 ; Push onto Stack
		 sub   ebx,byte 4
		 mov   esi,edi		; New PC
		 mov   [R_A7],ebx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EBX
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04e90_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04e90_Bank:
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ea8:				; jsr     ($4ea8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   eax,esi		; Old PC
		 mov   ebx,[R_A7]	 ; Push onto Stack
		 sub   ebx,byte 4
		 mov   esi,edi		; New PC
		 mov   [R_A7],ebx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EBX
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04ea8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04ea8_Bank:
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4eb0:				; jsr     (-$50,A0,D4.l*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4eb0_1
		 cwde
OP_4eb0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   eax,esi		; Old PC
		 mov   ebx,[R_A7]	 ; Push onto Stack
		 sub   ebx,byte 4
		 mov   esi,edi		; New PC
		 mov   [R_A7],ebx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EBX
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04eb0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04eb0_Bank:
		 sub   dword [_m68000_ICount],byte 36
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4eb8:				; jsr     $4eb8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   eax,esi		; Old PC
		 mov   ebx,[R_A7]	 ; Push onto Stack
		 sub   ebx,byte 4
		 mov   esi,edi		; New PC
		 mov   [R_A7],ebx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EBX
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04eb8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04eb8_Bank:
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4eb9:				; jsr     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   eax,esi		; Old PC
		 mov   ebx,[R_A7]	 ; Push onto Stack
		 sub   ebx,byte 4
		 mov   esi,edi		; New PC
		 mov   [R_A7],ebx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EBX
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04eb9_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04eb9_Bank:
		 sub   dword [_m68000_ICount],byte 34
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4eba:				; jsr     ($4eba,PC); ($4eb8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   eax,esi		; Old PC
		 mov   ebx,[R_A7]	 ; Push onto Stack
		 sub   ebx,byte 4
		 mov   esi,edi		; New PC
		 mov   [R_A7],ebx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EBX
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04eba_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04eba_Bank:
		 sub   dword [_m68000_ICount],byte 30
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ebb:				; jsr     (-$45,PC,D4.l*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4ebb_1
		 cwde
OP_4ebb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   eax,esi		; Old PC
		 mov   ebx,[R_A7]	 ; Push onto Stack
		 sub   ebx,byte 4
		 mov   esi,edi		; New PC
		 mov   [R_A7],ebx
		 mov   [R_PC],ESI
		 mov   [R_CCR],edx
		 mov   edx,EAX
		 mov   ecx,EBX
		 and   ecx,0FFFFFFh
		 call  @cpu_writemem24_dword@8
		 mov   EDX,[R_CCR]
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04ebb_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04ebb_Bank:
		 sub   dword [_m68000_ICount],byte 32
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ed0:				; jmp     (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   esi,edi
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04ed0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04ed0_Bank:
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ee8:				; jmp     ($4ee8,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   esi,edi
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04ee8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04ee8_Bank:
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ef0:				; jmp     (-$10,A0,D4.l*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx,byte 7
		 mov   EDI,[R_A0+ECX*4]
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4ef0_1
		 cwde
OP_4ef0_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   esi,edi
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04ef0_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04ef0_Bank:
		 sub   dword [_m68000_ICount],byte 28
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ef8:				; jmp     $4ef8.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   esi,edi
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04ef8_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04ef8_Bank:
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ef9:				; jmp     $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   esi,edi
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04ef9_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04ef9_Bank:
		 sub   dword [_m68000_ICount],byte 26
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4efa:				; jmp     ($4efa,PC); ($4ef8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   esi,edi
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04efa_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04efa_Bank:
		 sub   dword [_m68000_ICount],byte 22
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4efb:				; jmp     (-$5,PC,D4.l*8):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 mov   edi,esi           ; Get PC
		 push  edx
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4efb_1
		 cwde
OP_4efb_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 pop   edx
		 mov   esi,edi
		 and   esi,0ffffffh
		 mov   eax,esi
		 shr   eax,16
		 cmp   [asmbank],eax
		 je    OP_04efb_Bank
		 mov   [asmbank],eax
		 mov   [R_CCR],edx
		 mov   ecx,esi
		 call  @cpu_setOPbase24@4
		 mov   edx,[R_CCR]
		 mov   ebp,dword [_OP_ROM]
OP_04efb_Bank:
		 sub   dword [_m68000_ICount],byte 24
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4800:				; nbcd    D0:
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EBX,[R_D0+ECX*4]
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 6
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4810:				; nbcd    (A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4818:				; nbcd    (A0)+:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EDI,[R_A0+ECX*4]
		 inc   dword [R_A0+ECX*4]
		 cmp   ecx, byte 7			; by Kenjo, for "(A7)+"
		 jne   OP_4818_notA7			;
		 inc   dword [R_A0+ECX*4]		;
OP_4818_notA7:						;
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 12
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4820:				; nbcd    -(A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EDI,[R_A0+ECX*4]
		 dec   EDI
		 cmp   ecx, byte 7			; by Kenjo, for "-(A7)"
		 jne   OP_4820_notA7			;
		 dec   EDI				;
OP_4820_notA7:						;
		 mov   [R_A0+ECX*4],EDI
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 14
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4828:				; nbcd    ($4828,A0):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,[R_A0+ECX*4]
		 add   esi,byte 2
		 add   edi,eax
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4830:				; nbcd    ($30,A0,D4.l):
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EDI,[R_A0+ECX*4]
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_4830_1
		 cwde
OP_4830_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4838:				; nbcd    $4838.w:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 movsx EDI,word [esi+ebp]
		 add   esi,byte 2
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4839:				; nbcd    $123456.l:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EDI,dword [esi+ebp]
		 rol   EDI,16
		 add   esi,byte 4
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 20
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_483a:				; dc.w $483a; ILLEGAL:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 movsx EAX,word [esi+ebp]
		 mov   EDI,ESI           ; Get PC
		 add   esi,byte 2
		 add   edi,eax         ; Add Offset to PC
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 16
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_483b:				; dc.w $483b; ILLEGAL:
		 mov   [R_PPC],esi			 ; Keep Previous PC
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   edi,esi           ; Get PC
		 mov   EAX,dword [esi+ebp]
		 add   esi,byte 2
		 mov   edx,eax
		 shr   eax,10
		 and   eax,byte 3Ch
		 mov   eax,[R_D0+eax]
		 test  dh,8H
		 jnz   short OP_483b_1
		 cwde
OP_483b_1:
		 add   edi,eax
		 movsx edx,dl
		 add   edi,edx
		 mov   [R_PC],ESI
		 and   EDI,0FFFFFFh
		 mov   [Safe_ECX],ECX
		 mov   [Safe_EDI],EDI
		 mov   ecx,EDI
		 call  @cpu_readmem24@4
		 mov   ECX,[Safe_ECX]
		 mov   EDI,[Safe_EDI]
		 mov   EBX,EAX
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 mov   [R_PC],ESI
		 mov   edx,EAX
		 mov   ecx,EDI
		 call  @cpu_writemem24@8
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 18
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_483c:				; dc.w $483c; ILLEGAL:
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EBX,dword [esi+ebp]
		 add   esi,byte 2
		 xor   eax,eax
		 bt    dword [R_XC],0
		 sbb   al,bl
		 das
		 pushfd
		 and   eax,byte 1Fh
		 mov   edx,[IntelFlag+eax*4]
		 mov   [R_XC],dh
		 and   edx,0EFFh
		 pop   EDX
		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 8
		 js    near MainExit

		 movzx ecx,word [esi+ebp]
		 jmp   [OPCODETABLE+ecx*4]

		 ALIGN 4

OP_4ac0:				; tas     D0:
		 add   esi,byte 2

		 and   ecx, byte 7
		 mov   EAX,[R_D0+ECX*4]
		 test  AL,AL
		 pushfd
		 or    al,128
		 mov   [R_D0+ECX*4],AL
		 pop   EDX
;		 mov   [R_XC],edx
		 sub   dword [_m68000_ICount],byte 4
		 js    near MainExit



