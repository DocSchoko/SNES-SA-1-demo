;self-contained exception printer
	.include "routines/h/exception.h"
	
.section "excp"	
PrintException:
	.ACCU 16
	.INDEX 16
	php
	rep #$31
	sta.l excA	
	lda 2,s					;save call origin
	dec a
	dec a				;substract jsr len
	sta.l excPc
	lda 4,s	;get err-no
	and #$ff
	sta.l excErr
	tsc
	inc a
	inc a	;skip return addr on stack
	inc a
	sta.l excStack
	lda #STACK_strt
	tcs		;set stack to sane range in case it's fucked up already
	phb
	phk
	
	phd
	phx
	phy
	pea 0
	pea ZP
	pld
	plb
	plb
	sei							;disable screen,irqs
	lda #INIDSP_FORCE_BLANK
	sta INIDSP
	stz NMITIMEN

	;save cpu status:
	pla
	sta.l excY
	pla
	sta.l excX
	pla
	sta.l excDp

	sep #$20
	pla
	sta.l excPb
	pla
	sta.l excDb
	pla
	sta.l excFlags

	rep #$31
	jsr ClearRegisters
	jsr ClearVRAM

	sep #$20
	lda #DMAP_2_REG_WRITE_ONCE			;upload font tiles
	sta DMAP0
	lda #VMDATAL & $ff
	sta DMADEST0

	rep #$31
	lda #ExcFontTiles.LEN
	sta DMALEN0L
	lda #($2000+(TILE2BPP*32))/2	;vram target,after tilemap and after first 128 ascii chars
	sta VMADDL
	lda #ExcFontTiles			;dma source
	sta DMASRC0L
	sep #$20
	lda #:ExcFontTiles
	sta DMASRC0B
	lda #VMAIN_INCREMENT_MODE
	sta VMAIN			;set VRAM transfer mode to word-access, increment by 1
	lda #DMA_CHANNEL0_ENABLE
	sta MDMAEN

	stz CGADD			;upload pal
	ldx #ExcFontPal			;start at color 0 
	stx DMASRC0L			;Store the data offset into DMA source offset
	ldx #ExcFontPal.LEN
	stx DMALEN0L   			;Store the size of the data block
	lda #:ExcFontPal
	sta DMASRC0B			;Store the data bank holding the tile data
	stz DMAP0
	lda #CGDATA & $ff    			;Set the destination register ( CGDATA: CG-RAM Write )
	sta DMADEST0
	lda #DMA_CHANNEL0_ENABLE    			;Initiate the DMA transfer
	sta MDMAEN

	rep #$31					;print main exception text
	
	lda #0
	jsr ExceptionVramPointer
	lda #T_EXCP_exception.PTR
	jsr ExceptionStrPointer
	jsr ExceptionPrintLoop
	
	lda.l excErr
	and #$ff
	cmp #errStrt
	bcc ExceptionNoErrMsg
									
		and #$ff				;fetch corresponding string for this err-msg
		tax
		lda.l ExcErrMsgStrLut-errStrt,x
		and #$ff
		jsr ExceptionStrPointer
		jsr ExceptionPrintLoop

ExceptionNoErrMsg:
	sep #$20
	lda #BG1NBA_2000			;set up some regs
	sta BG12NBA
	lda #T_BG1_ENABLE
	sta TMAIN
	lda #INIDSP_BRIGHTNESS
	sta INIDSP
	
-
	jmp -			;die
	stp
	
;print string to vram port	
ExceptionPrintLoop:
	php
	rep #$31
	ldy #0		
PrintLoop:
		lda [tmp],y
		and #$ff
		cmp #' '	;lower than whitespace??
		bcs ExceptionTilemapPrint 
			jsr PrintCmd
		bcs PrintLoopExit
		bra PrintLoop

		ExceptionTilemapPrint:
			sta VMDATAL
			iny
			bra PrintLoop

PrintLoopExit:
	plp
	rts
	
;puts 16bit a string pointer into tmp, 3 bytes
ExceptionStrPointer:
	php
	rep #$31
	sta tmp
	asl a
	clc
	adc tmp
	tax
	lda.l TextstringLUT,x
	sta tmp
	lda.l TextstringLUT+1,x
	sta tmp+1
	plp
	rts		

;sets vram adress to a/2	
ExceptionVramPointer:
	pha
	and #$1f
	sta tmp+6		;left margin
	pla
	sta tmp+4		;screen position
	clc
	adc #vramBase
	sta VMADDL
	rts
	
PrintCmd:
	asl a
	tax
	jsr (ExcStrCmdLut,x)	;get pointer to subroutine
	rts
	
SUB_TC_end:
	sec
	rts
	
;recursively goto substring, input: number of textstring pointer, 2 bytes
SUB_TC_sub:
	lda tmp	;push current string pointer to stack
	pha
	lda tmp+2
	pha
	iny
	phy			;push current string counter to stack	

	lda [tmp],y	;get argument, substring to load
	jsr ExceptionStrPointer	
	jsr ExceptionPrintLoop

	ply		;restore original string status
	iny		;goto next string char
	iny
	pla
	sep #$20
	sta tmp+2
	rep #$31
	pla
	sta tmp
	clc
	rts

;recursively goto substring, indirect.(input: 16bit pointer to 16bit str_pointer_number in bank $7e.)	
SUB_TC_iSub:
	lda tmp	;push current string pointer to stack
	pha
	lda tmp+2
	pha
	iny
	phy			;push current string counter to stack	

	phb
	sep #$20
	lda #RAM
	pha
	plb
	rep #$31
	lda [tmp],y ;get argument, pointer to substring to load
	tax
	lda.l RAM << 16,x
	plb
	
	jsr ExceptionStrPointer	
	jsr ExceptionPrintLoop

	ply		;restore original string status
	iny
	iny		;goto next string char
	pla
	sep #$20
	sta tmp+2
	rep #$31
	pla
	sta tmp
	clc
	rts

;recursively goto substring, direct 24bit pointer to arbitrary string	
SUB_TC_dSub:
	lda tmp	;push current string pointer to stack
	pha
	lda tmp+2
	pha
	iny
	phy			;push current string counter to stack	

	lda [tmp],y ;get argument, pointer to substring to load
	pha
	iny
	lda [tmp],y
	sta tmp+1
	pla
	sta tmp

	jsr ExceptionPrintLoop

	ply		;restore original string status
	iny
	iny
	iny		;goto next string char
	pla
	sep #$20
	sta tmp+2
	rep #$31
	pla
	sta tmp
	clc
	rts

;recursively goto substring, indirect 16bit pointer to 24bit pointer to arbitrary string	
SUB_TC_diSub:
	lda tmp	;push current string pointer to stack
	pha
	lda tmp+2
	pha
	iny
	phy			;push current string counter to stack	

	phb
	sep #$20
	lda #RAM
	pha
	plb
	rep #$31
	lda [tmp],y ;get argument, pointer to substring-pointer to load
	tax
	lda.l RAM << 16,x
	sta tmp
	inx
	lda.l RAM << 16,x
	sta tmp+1
	plb

	jsr ExceptionPrintLoop

	ply		;restore original string status
	iny
	iny		;goto next string char
	pla
	sep #$20
	sta tmp+2
	rep #$31
	pla
	sta tmp
	clc
	rts

;set new screen position to write to
SUB_TC_pos:
	iny
	lda [tmp],y ;get argument, new position
	;and #$ff
	clc
	adc #vramBase
	jsr ExceptionVramPointer
	iny
	iny
	rts
	
SUB_TC_brk:
	lda tmp+4
	and #$FFE0		;mask off inline-position
	clc
	adc #$20		;advance to next line
	clc
	adc tmp+6		;include left margin
	jsr ExceptionVramPointer
	iny		;goto next char
	rts	

;print hex value. arg0: 24bit pointer to adress of hex value. arg1=length	in bytes(masked to $1f)
SUB_TC_hToS:
	lda tmp	;push current string pointer to stack
	pha
	lda tmp+2
	pha
	iny
	phy			;push current string counter to stack	

	lda [tmp],y ;get argument, pointer to word to print
	sta tmp+10
	iny
	lda [tmp],y	;offfset high byte+bank
	sta tmp+11
	iny
	iny
	lda [tmp],y	;length
	and #$1f
	asl a				;*2, nibbles to print
	sta tmp+8		

	jsr PrintHexToStack

	ply		;restore original string status
	iny
	iny
	iny
	iny		;goto next string char
	pla
	sep #$20
	sta tmp+2
	rep #$31
	pla
	sta tmp
	clc
	rts

PrintHexToStack:
	tsc			;get stack pointer, use as pointer for string
	sta tmp+13	;store stack buffer because we're going to fuck up the stack
	pea TC_end		;push string terminator
	ldy #0
	PrintHexToStackLoop:
		phy
		tya
		lsr a
		tay
		lda [tmp+10],y
		bcc PrintHexToStackLo
			and #$f0	;get high nibble
			lsr a
			lsr a
			lsr a
			lsr a
			bra PrintNibbleToStack
			
		PrintHexToStackLo:
			and #$0f				;get low nibble

		PrintNibbleToStack:
		ply
		clc
		adc #'0'	;shift to ASCII range
		cmp #'9'+1
		bcc PrintNibbleNoChar
			adc #8-2	;shift into upper case letter range(-1 because of set carry, another -1 cause we're comparing '9'+1)
		PrintNibbleNoChar:
		sep #$20
		pha		;print to stack
		rep #$31
		iny
		cpy tmp+8
		bcc PrintHexToStackLoop
	
	stz tmp+1	;save string pointer
	tsc
	inc a			;+1 because stack always points to next stack-slot
	sta tmp
	jsr ExceptionPrintLoop		

	lda tmp+13	;restore stack
	tcs	
	rts
.ends
