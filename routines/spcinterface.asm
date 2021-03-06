.include "routines/h/spcinterface.h"
.section "spchandler"


/*
check if spc sends report data
register spc stimulus callbacks here
callbacks are simple routines, usually not part of objects/classes
7 different callback types are available
on calling, zp is standard #ZP, a is 16bit argument
callback routines must all reside in bank $c0
empty slots are indicated by $ffff
if an empty slot is encountered while processing an incoming stimulus, an error message is issued
*/

play_Spc:
	php
	rep #$31
	lda.l APUIO0
	pha
	lda.l APUIO2
	pha

	lda 1,s
	lda 2,s
	lda 3,s
	lda 4,s
	and.w #modStimulusCommand
	cmp.w #modStimulusCommand
	bne SpcHandlerNoSpcReport
		lda 1,s	;lda.l APUIO1	;try to detect changes first, only trigger callback on changes
		cmp.b lastStimulusBuffer
		beq SpcHandlerNoSpcReport

			sta.b lastStimulusBuffer	
			lda 4,s
			and.w #stimulusCallbackCount-1
			asl a
			tax
			lda.b stimulusCallbacks.pointer,x
			cmp #stimulusEmpty
			bne execStimulusCallback
				pea E_SpcNoStimulusCallback
				jsr PrintException

		execStimulusCallback:
			tax
			lda 1,s	;lda.l APUIO2	;put mod data into a. lower 8 bit is effect data, upper 8bit reserved(maybe note/instrument data in the future)
			phd
			pea ZP
			pld
			php
			jsr (0,x)
			plp
			pld

SpcHandlerNoSpcReport:
	pla
	pla
	lda.b SpcHandlerState
	and.w #$1f			;have 32 states maximum
	asl a
	tax
	jsr (SpcHandlerSubroutineJumpLUT,x)
		
	plp
	rts

;stops currently playing stream, song, then waits for driver to return to idle state(wait for all scheduled sound effects to play)
SpcWaitAllCommandsProcessed:
	php
	sep #$20
	stz.b SpcStreamVolume
	jsr SpcStopSong

SpcWaitLoop:
		lda.b SpcCmdFifoStart
		cmp.b SpcCmdFifoEnd				;check if fifo is empty
		bne SpcWaitLoop
	
		lda.b SpcHandlerState
		cmp.b #SpcIdle.PTR
		bne SpcWaitLoop
	plp
	rts

kill_Spc:
	jsr SpcStopSongInit
	rep #$31
	lda #OBJR_kill
	sta 3,s
	rts

SpcSetReportTypeInit:
	rep #$31
	lda.b SpcHandlerArgument0		;store type and sub-arg
	sta.l APUIO1
	sep #$20

	lda.b #SpcCmdReportType		;exec command
	sta.l APUIO0
	
	lda #SpcSetReportTypeWait.PTR
	sta.b SpcHandlerState					;goto "wait SE ack"-state
	rts

SpcSetReportTypeWait:
	sep #$20
	lda.l APUIO0
	cmp.b #SpcCmdReportType
	bne SpcSetReportTypeWaitNoIdle			;wait until spc has ack'd the speed change before returning

	lda.b #SpcIdle.PTR
	sta.b SpcHandlerState					;return to idle once spc has answered

SpcSetReportTypeWaitNoIdle:
	rts

SpcSetChMaskInit:
	sep #$20
	lda.b SpcHandlerArgument0		;store mask
	sta.l APUIO1

	lda.b #SpcCmdSetSongChMask		;exec command
	sta.l APUIO0
	
	lda.b #SpcSetChMaskWait.PTR
	sta.b SpcHandlerState					;goto "wait SE ack"-state
	rts

SpcSetChMaskWait:
	sep #$20
	lda.l APUIO0
	cmp.b #SpcCmdSetSongChMask
	bne SpcSetChMaskWaitNoIdle			;wait until spc has ack'd the speed change before returing

	lda.b #SpcIdle.PTR
	sta.b SpcHandlerState					;return to idle once spc has answered

SpcSetChMaskWaitNoIdle:
	rts

SpcSetSpeedInit:
	sep #$20
	lda.b SpcHandlerArgument0		;store speed
	sta.l APUIO1

	lda.b #SpcCmdSetSongSpeed		;exec command
	sta.l APUIO0
	
	lda.b #SpcSetSpeedWait.PTR
	sta.b SpcHandlerState					;goto "wait SE ack"-state
	rts

SpcSetSpeedWait:
	sep #$20
	lda.l APUIO0
	cmp.b #SpcCmdSetSongSpeed
	bne SpcSetSpeedWaitNoIdle			;wait until spc has ack'd the speed change before returing

	lda.b #SpcIdle.PTR
	sta.b SpcHandlerState					;return to idle once spc has answered

SpcSetSpeedWaitNoIdle:
	rts	
	
SpcUploadSampleset:
	sep #$20
	lda.b #SpcCmdUploadSamplePack					;send "upload song" command
	jsr SpcCmdWaitAck

;upload SamplePack here
	lda.b SpcHandlerArgument0				;get song number to upload
	sta.b PtPlayerCurrentSamplePack
	
	rep #$31				;multiply song number by 3 and use as index into song pointertable
	and.w #$00ff
	sta.b PtPlayerDataPointerLo
	asl a
	clc
	adc.b PtPlayerDataPointerLo
	tax

	lda.l PtPlayerSamplePackPointertable,x	;store pointer to song
	sta.b PtPlayerDataPointerLo
		
	lda.l PtPlayerSamplePackPointertable+1,x
	sta.b PtPlayerDataPointerHi	

	ldy.w #$0000
	lda.b [PtPlayerDataPointerLo],y		;get song length
	dec a					;substract length word
	dec a
	sta.b PtPlayerSmplBufferPosLo
	iny					;increment source pointer to actual song offset
	iny
	sep #$20

SpcUploadSamplePackTransfer1:		
		lda.b [PtPlayerDataPointerLo],y		;write 3 bytes to ports
		sta.l APUIO1
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO2
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO3
		iny
		
		lda.b #SpcCmdUploadSongT1		;write ack transfer 1 to port0
		jsr SpcCmdWaitAck
	
SpcUploadSamplePackTransfer2:		
		lda.b [PtPlayerDataPointerLo],y		;write 3 bytes to ports
		sta.l APUIO1
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO2
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO3
		iny
		
		lda.b #SpcCmdUploadSongT2		;write ack transfer 1 to port0
		jsr SpcCmdWaitAck
					
		cpy.b PtPlayerSmplBufferPosLo		;check if transfer length is exceeded
		bcc SpcUploadSamplePackTransfer1
		
		lda.b #SpcCmdUploadSamplePackDone		;send "upload song complete" commadn if transfer is done
		sta.l APUIO0
	
		lda.b #SpcIdle.PTR
		sta.b SpcHandlerState					;return to idle

SpcUploadSamplePackWaitExit:
	lda.b SpcUploadedFlag
	ora.b #$40						;set sample pack uploaded flag.
	sta.b SpcUploadedFlag

	rts	


SpcStopSongInit:
	rep #$31
	lda #0
	sta.l APUIO1
	sta.l APUIO2
	sep #$20
	lda.b #SpcCmdStopSong		;write ack transfer 1 to port0
	jsr SpcCmdWaitAck

	lda.b #SpcIdle.PTR
	sta.b SpcHandlerState					;return to idle once spc has answered

SpcStopSongWaitNoIdle:
	rts

SpcPlaySoundeffectUpload:
	rep #$31
	lda.b SpcHandlerArgument0		;store arguments
	sta.l APUIO1
	lda.b SpcHandlerArgument1
	and.w #$7fff				;mask off msb and use as wurst
	ora.b SpcSoundEffectFlipFlag
	sta.l APUIO2
	lda.b SpcSoundEffectFlipFlag
	eor.w #$8000
	sta.b SpcSoundEffectFlipFlag
	sep #$20
	lda.b #SpcCmdPlaySoundEffect		;exec command
	sta.l APUIO0
	
	lda.b #SpcPlaySoundeffectWait.PTR
	sta.b SpcHandlerState					;goto "wait SE ack"-state
	rts

;dont use this cause it sometimes plays a sound effect twice
SpcPlaySoundeffectWait:	
	sep #$20
	lda.l APUIO0

	cmp.b #SpcCmdPlaySoundEffect
	bne SpcPlaySoundeffectWaitNoIdle			;wait until spc has ack'd the soundeffect before returing

	lda.b #SpcIdle.PTR
	sta.b SpcHandlerState					;return to idle once spc has answered

SpcPlaySoundeffectWaitNoIdle:
	rts
	
		
init_Spc:
	sep #$20
	lda.b #:PtplayerSpcCode
	ldx.w #PtplayerSpcCode
	sta.b PtPlayerDataPointerBa
	stx.b PtPlayerDataPointerLo

	rep #$31
	ldy.w #$0000				;clear data pointer
	lda.w #$BBAA
	jsr SpcWaitAck

	sep #$20
	lda.b #$CC				;send "start transfer"
	bra PtPlayerInitDoTransfer

PtPlayerInitGetByte:
	lda.b [PtPlayerDataPointerLo],y
	iny
	xba
	lda.b #$00
	bra PtPlayerInitClearSpcPort0

PtPlayerInitGetNextByte:
	xba
	lda.b [PtPlayerDataPointerLo],y
	iny
	xba
	jsr SpcWaitAck
	inc a

PtPlayerInitClearSpcPort0:
	rep #$20
	sta.l APUIO0
	sep #$20
	dex
	bne PtPlayerInitGetNextByte

	jsr SpcWaitAck

PtPlayerInitAddLoop:
	adc.b #$03
	beq PtPlayerInitAddLoop

PtPlayerInitDoTransfer:
	pha
	rep #$20
	lda.b [PtPlayerDataPointerLo],y
	iny
	iny
	tax
	lda.b [PtPlayerDataPointerLo],y
	iny
	iny
	sta.l APUIO2
	sep #$20
	cpx.w #$0001				;whats this?
	lda.b #$00
	rol a
	sta.l APUIO1
	adc.b #$7F
	pla
	sta.l APUIO0
	cpx.w #$0001				;fix to be able to upload apucode during active nmi
	bcc PtPlayerInitDone

	jsr SpcWaitAck	;hope this doesn't break anything
	bvs PtPlayerInitGetByte

PtPlayerInitDone:
	sep #$20
	lda.b #SpcIdle.PTR
	sta.b SpcHandlerState			;go to idle state

;init some variables
	lda.b #$a0
	sta.b SpcSongSpeed			;set speed to default
	lda.b #$0f
	sta.b SpcSongChMask			;set song channel mask to default
	jsr clearStimulusCallbackBuffer
	rts

clearStimulusCallbackBuffer:
	php

	rep #$31
	ldy #stimulusCallbackCount
	ldx #0

	clearStimulusCallbackBufferLoop:
		lda #stimulusEmpty
		sta.b stimulusCallbacks.pointer,x
		txa
		clc
		adc.w #_sizeof_callbackBuff
		tax
		dey
		bne clearStimulusCallbackBufferLoop
	plp
	rts		

;check if there's a new command in the fifo, else return
;fifo buffer organization is:
;each entry: 1 command byte, 3 argument bytes
;fifo has 16 entries/64bytes total
SpcIdle:
	sep #$20
	lda #0
	sta.l APUIO0					;clear port0
	
	lda.b SpcCmdFifoStart
	cmp.b SpcCmdFifoEnd				;check if fifo is empty
	beq SpcIdleFifoEmpty
	
;theres a spc command present:
	rep #$31
	and.w #$3f					;limit fifo pointer to 64 bytes
	tax						
	lda.b SpcCmdFifo,x				;get command
	sta.b SpcHandlerState					;store command/state and argument 1
	
	lda.b SpcCmdFifo+2,x				;get command
	sta.b SpcHandlerArgument1				;store arguments 1 and 2

	lda.b SpcHandlerState				;directly execute fetched command
	and.w #$1f					;except when its an idle command
	cmp.w #1					;because this would allow for unlimited nesting and possibly stack overflow
	beq SpcIdleFifoEmpty
	
	asl a
	tax
	jsr (SpcHandlerSubroutineJumpLUT,x)
	
	sep #$20
	lda.b SpcCmdFifoStart				;goto next fifo entry next frame
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoStart	
	
SpcIdleFifoEmpty:
	rts

;legacy
SpcUploadSongWait:
SpcStopSongWait:
	rts
	
SpcUploadSong:
	sep #$20
	lda.b #SpcCmdUploadSong					;send "upload song" command
	jsr SpcCmdWaitAck

;upload song here
	lda.b SpcHandlerArgument0				;get song number to upload
	sta.b PtPlayerCurrentSong
	
	rep #$31				;multiply song number by 3 and use as index into song pointertable
	and.w #$00ff
	sta.b PtPlayerDataPointerLo
	asl a
	clc
	adc.b PtPlayerDataPointerLo
	tax

	lda.l SongLUT,x	;store pointer to song
	sta.b PtPlayerDataPointerLo
		
	lda.l SongLUT+1,x
	sta.b PtPlayerDataPointerHi	

	ldy.w #$0000
	lda.b [PtPlayerDataPointerLo],y		;get song length
	dec a					;substract length word
	dec a
	sta.b PtPlayerSmplBufferPosLo
	iny					;increment source pointer to actual song offset
	iny
	sep #$20

SpcUploadSongTransfer1:		
		lda.b [PtPlayerDataPointerLo],y		;write 3 bytes to ports
		sta.l APUIO1
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO2
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO3
		iny
		
		lda.b #SpcCmdUploadSongT1		;write ack transfer 1 to port0
		jsr SpcCmdWaitAck
	
SpcUploadSongTransfer2:		
		lda.b [PtPlayerDataPointerLo],y		;write 3 bytes to ports
		sta.l APUIO1
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO2
		iny
		lda.b [PtPlayerDataPointerLo],y
		sta.l APUIO3
		iny
		
		lda.b #SpcCmdUploadSongT2		;write ack transfer 1 to port0
		jsr SpcCmdWaitAck
			
		cpy.b PtPlayerSmplBufferPosLo		;check if transfer length is exceeded
		bcc SpcUploadSongTransfer1
		
		lda.b #SpcCmdUploadSongDone		;send "upload song complete" commadn if transfer is done
		sta.l APUIO0
	
		lda.b #SpcIdle.PTR
		sta.b SpcHandlerState					;return to idle

SpcUploadSongWaitExit:
	lda.b SpcUploadedFlag
	ora.b #$80						;set song uploaded flag.
	sta.b SpcUploadedFlag
	rts	

;request command from spc, wait for ack
SpcCmdWaitAck:
	php
	sep #$20
	sta.l APUIO0
	jsr SpcWaitAck
	plp
	rts

;wait for spc ack and throw exception if spc response takes too long
SpcWaitAck:
	php
	rep #$10
	phx
	ldx #0

SpcWaitAckLoop:
		dex
		beq SpcWaitAckTimeout
		cmp.l APUIO0
		bne SpcWaitAckLoop
	plx
	plp
	rts

SpcWaitAckTimeout:
	pea E_SpcTimeout
	jsr PrintException


;stops currently playing song/stream
SpcStopSong:
	php
	rep #$31
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax	
	sep #$20
	lda.b #SpcStopSongInit.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd
	plp
	rts

;in:	a,8bit: SE number to play
;	x,16bit: volume & pitch low byte: pitch(use default if zero, multiplied by 16). high byte: volume(use default if zero) bit7:sign, bits6-4:panning, bits 3-0:volume(multiplied with $10)	
SpcPlaySoundEffect:
	php
	rep #$31
	pha					;push SE number
	phx					;push arguments
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	pla					;get arguments
	sta.b SpcCmdFifo+2,x			;store in fifo arguments 2,3
	
	pla					;fetch song number again
	sep #$20
	sta.b SpcCmdFifo+1,x
	lda.b #SpcPlaySoundeffectUpload.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd
	plp
	rts

;same as above, but doesn't use x as input
SpcPlaySoundEffectSimple:
	php
	rep #$31
	phx					;push arguments
	pha					;push SE number

	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	lda.w #0
	sta.b SpcCmdFifo+2,x			;store in fifo arguments 2,3
	
	pla					;fetch song number again
	sep #$20
	sta.b SpcCmdFifo+1,x
	lda.b #SpcPlaySoundeffectUpload.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd
	plx
	plp
	rts

;in: a,8bit: song number to play
playSong:
	php
	rep #$31
	pha					;push song number
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	
	pla					;fetch song number again
	sep #$20
	sta.b SpcCmdFifo+1,x
	lda.b #SpcUploadSong.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd
	
	stz.b SpcStreamVolume			;mute eventually playing stream, stop stream
	
	lda.b SpcUploadedFlag
	and.b #$7f						;clear song uploaded flag. will be set once song upload has been completed later on
	sta.b SpcUploadedFlag
	plp
	rts

;in: a,8bit: streamset number to play
playStream:
	php
	sep #$20
	pha
	rep #$31
	stz.b SpcStreamFrame
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	
	sep #$20
	pla					;store frameset number
	sta.b SpcCmdFifo+1,x
	lda.b #SpcStreamData.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd

	sep #$20
	stz.b SpcStreamVolume			;mute eventually playing stream, stop stream
	plp
	rts
	
;in: a,8bit: sample pack number to upload
SpcIssueSamplePackUpload:
	php
	rep #$31
	pha					;push song number
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	
	pla					;fetch song number again
	sep #$20
	sta.b SpcCmdFifo+1,x
	lda.b #SpcUploadSampleset.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd

	lda.b SpcUploadedFlag
	and.b #$bf						;clear sample pack uploaded flag. will be set once song upload has been completed later on
	sta.b SpcUploadedFlag
	
	plp
	rts

SpcStreamData:
	sep #$20
	lda.b #$7f				;turn on streaming volume
	sta.b SpcStreamVolume
	
	lda.b SpcHandlerArgument0		;get frameset number to stream
	sta.b SpcCurrentStreamSet		;multiply by 5 to get pointer into frameset table			
	rep #$31
	and.w #$ff
	sta.b _tmp
	asl a
	asl a
	clc
	adc.b _tmp
	
	tax
	lda.l StreamSetLut+3,x	;get number of frames for this set
	sta.l APUIO1				;write number of frames to stream to spc
				
	sep #$20	
	lda.b #SpcCmdReceiveStream				;send "upload song" command
	sta.l APUIO0

	lda.l APUIO0
	cmp.b #SpcCmdReceiveStreamComplete			;don't switch to streamer yet if spc is still finishing the last transfer.(only applicable if last command was streaming)
	beq SpcStreamDataWaitSpcLastStream
	
	lda.b #SpcStreamDataWait.PTR
	sta.b SpcHandlerState					;goto "wait for spc to ack song upload" state
	
SpcStreamDataWaitSpcLastStream:	
	rts


SpcStreamDataReturnIdle:
	sep #$20
	lda.w HdmaFlags
	and.b #$7f					;disable spc stream on hdma channel 7
	sta.w HdmaFlags	
	lda.b #SpcIdle.PTR						;return to idle if spc signalizes that transfer is complete
	sta.b SpcHandlerState

SpcStreamDataExit:
	rts
	
SpcStreamDataWait:
	sep #$20
	lda.l APUIO0
	cmp.b #SpcCmdReceiveStreamComplete			;check if transfer complete
	beq SpcStreamDataReturnIdle
	cmp.b #SpcCmdReceiveStream				;wait until spc has ack'd upload song command
	bne SpcStreamDataExit					;else try again next frame	
	
	lda.b SpcCurrentStreamSet				;get current frameset number
	rep #$31
	and.w #$ff
	sta.b _tmp					;multiply by 5
	asl a
	asl a
	clc
	adc.b _tmp
	
	tax
	lda.l StreamSetLut,x				;store offset of first frame in set
	sta.b _tmp+2
	lda.l StreamSetLut+1,x
	sta.b _tmp+3
	
	lda.l APUIO1						;get frame request number
									;multiply with 144, get pointer to requested frame. warning: one bank holds $1c7 frames, or $fff0 bytes of data. must wrap to next bank if bigger.
	sta.b _tmp+5					;store frame request number
	sta.b SpcStreamFrame
	pha
	lda.b SpcStreamVolume			;only write current frame if stream hasnt been stopped. otherwise external routines might be confused when transitioning between streams
	and.w #$ff
	bne DontClearSpcStreamFrame
	
	stz.b SpcStreamFrame
	
DontClearSpcStreamFrame:
	pla

SpcStreamCalcFrameOffsetLoop:
	cmp.w #SpcFramesPerBank					;check if number of frames exceeds bank limit
	bcc SpcStreamCalcFrameOffsetNoBankWrap

	sep #$20						;if it does, increase bank
	inc.b _tmp+4
	rep #$31						;and substract one bank full of samples from total amount
	sec
	sbc.w #SpcFramesPerBank
	bra SpcStreamCalcFrameOffsetLoop			;do this until we're in the bank the frame actually is in

SpcStreamCalcFrameOffsetNoBankWrap:
	asl a							;multiply by 144
	asl a
	asl a
	asl a							;first multiply by 16
	sta.b _tmp+2
	
	asl a							;then by 128
	asl a
	asl a
	
	clc
	adc.b _tmp+2					;this is x*144
	sta.b _tmp+2					;and save in pointer

;line 1, command
	lda.w #36/2
	sta.b _tmp					;set scanline counter
	lda.w #SpcScanlineWaitCount						;store 1 in frame count
	ldx.w #0						;clear hdma table pointer
	txy							;clear brr source counter
	
	sta.l HdmaSpcBuffer,x

	lda.w #SpcCmdSubmitStreamNumber				;send "submit frame #"-cmd
	sta.l HdmaSpcBuffer+1,x
	
	lda.b _tmp+5					;get frame submit number
	sta.l HdmaSpcBuffer+2,x

	lda.b SpcStreamVolume
	sta.l HdmaSpcBuffer+4,x					;store volume
	
	inx
	inx
	inx
	inx
	inx
;line 2, waitloop &  frame transmit
SpcStreamSetupHdmaTableLoop:
	lda.w #1
	sta.l HdmaSpcBuffer,x				;one line
	
	lda.b [_tmp+2],y				;brr data to ports APUIO0-APUIO3
	sta.l HdmaSpcBuffer+1,x

	iny
	iny
	
	lda.b [_tmp+2],y
	sta.l HdmaSpcBuffer+3,x

	inx
	inx
	inx
	inx
	inx
	
	iny
	iny

	lda.w #1
	sta.l HdmaSpcBuffer,x				;one line
	
	lda.b [_tmp+2],y				;brr data to ports APUIO0-APUIO3
	sta.l HdmaSpcBuffer+1,x

	iny
	iny
	
	lda.b [_tmp+2],y
	sta.l HdmaSpcBuffer+3,x

	inx
	inx
	inx
	inx
	inx
	
	iny
	iny	
	dec.b _tmp
	bne SpcStreamSetupHdmaTableLoop

;this doesnt work right. reason is that the the stream data sometimes contains "false" commands.
;write spc command here: (only play soundeffect, stop song/stream is allowed here)
	stz.b _tmp				;clear spc command field
	stz.b _tmp+2
	lda.w #1
	sta.l HdmaSpcBuffer,x				;one line

	lda.b _tmp
	sta.l HdmaSpcBuffer+1,x				
	
	lda.b _tmp+2
	sta.l HdmaSpcBuffer+3,x

	inx
	inx
	inx
	inx
	inx

;terminate hdma table:	
	lda.w #0
	sta.l HdmaSpcBuffer,x
	
	lda.w #HdmaSpcBuffer & $ffff
	sta.l DMASRC7L					;hdma source offset
	
	sep #$20
	lda.w HdmaFlags
	ora.b #DMA_CHANNEL7_ENABLE					;enable spc stream on hdma channel 7
	sta.w HdmaFlags
	
	lda.b #RAM					;hdma source bank
	sta.l DMASRC7B
	
	lda.b #DMAP_4_REG_WRITE_ONCE				;hdma config, direct, 4 regs write once
	sta.l DMAP7
	
	lda.b #APUIO0 & $ff					;bbus target, apu port APUIO0-APUIO3
	sta.l DMADEST7
	
	rts
	
;in: SpcSongSpeed,8bit: song speed(timer duration. default is #$a0. lower=faster, higher=slower
SpcSetSongSpeed:
	php
	rep #$31
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	
	sep #$20
	lda.b SpcSongSpeed
	sta.b (SpcCmdFifo+1),x
	lda.b #SpcSetSpeedInit.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd
	
	plp
	rts

;in: SpcSongSpeed,8bit: song speed(timer duration. default is #$a0. lower=faster, higher=slower
SpcSetSongChannelMask:
	php
	rep #$31
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	
	sep #$20
	lda.b SpcSongChMask
	sta.b (SpcCmdFifo+1),x
	lda.b #SpcSetChMaskInit.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd
	
	plp
	rts

;input: a,16bit: 0=none 1=timecode 2=channel-levels(vol out) 3=special mod command (mod command $e0. this is "set filter", unused in almost any player
;4=instrument report. takes upper 8 bit argument as instrument to report
SpcSetReportType:
	php
	rep #$31
	pha
	lda.b SpcCmdFifoEnd			;get current position in spc command fifo buffer		
	and.w #$ff
	tax
	
	pla
	and.w #$ff07				;8 types max + argument
	sta.b (SpcCmdFifo+1),x
	
	sep #$20
	lda.b #SpcSetReportTypeInit.PTR
	sta.b SpcCmdFifo,x
	
	lda.b SpcCmdFifoEnd
	clc
	adc.b #4
	and.b #$3f				;16x4byte entries maximum 
	sta.b SpcCmdFifoEnd
	
	plp
	rts

registerStimulusCallback:
	php
	rep #$31
	ldx #3*_sizeof_callbackBuff		;hack, this should be dynamically selectable instead
	sta.b stimulusCallbacks.pointer,x

	plp
	rts
	
;legacy code:
PtPlayerInit:
PtPlayerMainHandler:
PtPlayerUploadVolEcho:
	rts
	
;plays sound effect with panning set to current objects x-position
SpcPlaySoundEffectObjectXPos:
	pea E_Todo
	jsr PrintException
		
.ends
