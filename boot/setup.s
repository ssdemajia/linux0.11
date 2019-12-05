	.code16
# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
#	setup.s		(C) 1991 Linus Torvalds
#
# setup.s is responsible for getting the system data from the BIOS,
# and putting them into the appropriate places in system memory.
# both setup.s and system has been loaded by the bootblock.
#
# This code asks the bios for memory/disk/other parameters, and
# puts them in a "safe" place: 0x90000-0x901FF, ie where the
# boot-block used to be. It is then up to the protected mode
# system to read them from there before the area is overwritten
# for buffer-blocks.
#

# NOTE! These had better be the same as in bootsect.s!
# setup.s主要利用BIOS中断读取机器系统数据，并将数据保存在0x90000开始的地址
	.equ INITSEG, 0x9000	# bootsect.s会把自己加载到这里
	.equ SYSSEG, 0x1000	# system loaded at 0x10000 (65536).
	.equ SETUPSEG, 0x9020	# this is the current segment

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

	ljmp $SETUPSEG, $_start	
_start:
# 打印现在setup.s中
	mov %cs, %ax
	mov %ax, %es
	mov %ax, %ds
	mov	$0x03, %ah			# 读取光标位置
	xor	%bh, %bh			# BX包含页码参数
	int	$0x10
							# 返回值中DH为行高，DL为列
	mov	$27, %cx			# CX保存字符串长度
	mov	$0x0007, %bx		# BH为页码，第0页，BL为颜色，page 0, attribute 7 (normal)
	mov $msgss, %bp			# ES:BP为字符串偏移
	mov	$0x1301, %ax		# AH=0x13表示写字符串，AL=0x01表示写模式
	int	$0x10

# 读取指针位置，参考：http://stanislavs.org/helppc/int_10-3.html
	mov	$INITSEG, %ax	# this is done in bootsect already, but...
	mov	%ax, %ds
	mov	$0x03, %ah		# read cursor pos
	xor	%bh, %bh
	int	$0x10			# save it in known place, con_init fetches
	mov	%dx, %ds:0		# 保存行数、列数到0x90000.

# Get memory size (extended mem, kB)
	mov	$0x88, %ah 
	int	$0x15
	mov	%ax, %ds:2 		# 获取从1MB内存后扩展了AX个1KB内存
# 将内存大小显示	
	mov	$0x03, %ah			# 读取光标位置
	xor	%bh, %bh			# BX包含页码参数
	int	$0x10
							# 返回值中DH为行高，DL为列
	mov	$15, %cx			# CX保存字符串长度
	mov	$0x0007, %bx		# BH为页码，第0页，BL为颜色，page 0, attribute 7 (normal)
	mov $msgmem, %bp			# ES:BP为字符串偏移
	mov	$0x1301, %ax		# AH=0x13表示写字符串，AL=0x01表示写模式
	int	$0x10
	# 打印十六进制的内存大小
	mov %ds:2, %bp
	call print_hex
	call print_nl

# Get video-card data:
	mov	$0x0f, %ah  	# 0x0f获取video-card state
	int	$0x10
	mov	%bx, %ds:4		# bh = display page
	mov	%ax, %ds:6		# al = video mode, ah = window width

# check for EGA/VGA and some config parameters，http://stanislavs.org/helppc/int_10-12.html
	mov	$0x12, %ah		# Video子系统配置
	mov	$0x10, %bl
	int	$0x10
	mov	%ax, %ds:8		
	mov	%bx, %ds:10
	mov	%cx, %ds:12

# 取第一个硬盘的参数表，Get hd0 data

	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x41, %si # 将ds:4*0x41的地址的值存入ds:si中，这个是中断向量0x41
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0080, %di	# di是目的地址
	mov	$0x10, %cx
	rep
	movsb

# 取第二个硬盘的参数表，Get hd1 data

	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x46, %si
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0090, %di	# 传输地址
	mov	$0x10, %cx
	rep
	movsb

# 检查是否存在第二块硬盘，也就是hd1，参考：http://stanislavs.org/helppc/int_13-15.html
# Check that there IS a hd1 :-)
	mov	$0x01500, %ax	
	mov	$0x81, %dl		# 0x81表示第二块磁盘
	int	$0x13
	jc	no_disk1
	cmp	$3, %ah			# 如果没有第二块
	je	is_disk1
no_disk1:
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0090, %di
	mov	$0x10, %cx
	mov	$0x00, %ax
	rep
	stosb
is_disk1:

# 接下来进入保护模式

	cli			# no interrupts allowed ! 

# first we move the system to it's rightful place

	mov	$0x0000, %ax
	cld			# 'direction'=0, movs moves forward
do_move:
	mov	%ax, %es	# destination segment
	add	$0x1000, %ax
	cmp	$0x9000, %ax
	jz	end_move
	mov	%ax, %ds	# source segment
	sub	%di, %di
	sub	%si, %si
	mov 	$0x8000, %cx
	rep
	movsw
	jmp	do_move

# then we load the segment descriptors

end_move:
	mov	$SETUPSEG, %ax	# right, forgot this at first. didn't work :-)
	mov	%ax, %ds
	lidt	idt_48		# 加载中断描述符表到idt，load idt with 0,0
	lgdt	gdt_48		# 加载全局描述符表到寄存器gdt，load gdt with whatever appropriate

# that was painless, now we enable A20

	call	empty_8042	# 8042 is the keyboard controller
	#mov	$0xD1, %al	# command write
	#out	%al, $0x64
	#call	empty_8042
	#mov	$0xDF, %al	# A20 on
	#out	%al, $0x60
	#call	empty_8042
	inb     $0x92, %al	# open A20 line(Fast Gate A20).
	orb     $0b00000010, %al
	outb    %al, $0x92

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.

	mov	$0x11, %al		# initialization sequence(ICW1)
					# ICW4 needed(1),CASCADE mode,Level-triggered
	out	%al, $0x20		# send it to 8259A-1
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2
	out	%al, $0xA0		# and to 8259A-2
	.word	0x00eb,0x00eb
	mov	$0x20, %al		# start of hardware int's (0x20)(ICW2)
	out	%al, $0x21		# from 0x20-0x27
	.word	0x00eb,0x00eb
	mov	$0x28, %al		# start of hardware int's 2 (0x28)
	out	%al, $0xA1		# from 0x28-0x2F
	.word	0x00eb,0x00eb		#               IR 7654 3210
	mov	$0x04, %al		# 8259-1 is master(0000 0100) --\
	out	%al, $0x21		#				|
	.word	0x00eb,0x00eb		#			 INT	/
	mov	$0x02, %al		# 8259-2 is slave(       010 --> 2)
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0x01, %al		# 8086 mode for both
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0xFF, %al		# mask off all interrupts for now
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1

# well, that certainly wasn't fun :-(. Hopefully it works, and we don't
# need no steenking BIOS anyway (except for the initial loading :-).
# The BIOS-routine wants lots of unnecessary data, and it's less
# "interesting" anyway. This is how REAL programmers do it.
#
# Well, now's the time to actually move into protected mode. To make
# things as simple as possible, we do no register set-up or anything,
# we let the gnu-compiled 32-bit programs do that. We just jump to
# absolute address 0x00000, in 32-bit protected mode.
	mov	$0x0001, %ax	# protected mode (PE) bit
	lmsw	%ax		# 加载机器状态字，This is it!
	mov	%cr0, %eax	# get machine status(cr0|MSW)	
	bts	$0, %eax	# turn on the PE-bit 
	mov	%eax, %cr0	# protection enabled
				
				# segment-descriptor        (INDEX:TI:RPL)
	.equ	sel_cs0, 0x0008 # select for code segment 0 (  001:0 :00) 
	; ljmp	$sel_cs0, $0	# jmp offset 0 of code segment 0 in gdt

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	$0x64, %al	# 8042 status port
	test	$2, %al		# is input buffer full?
	jnz	empty_8042	# yes - loop
	ret

# 打印16位的16进制格式数字串到屏幕
print_hex:
	mov $4, %cx
	mov (%bp), %dx
	print_digit:
		rol $4, %dx
		mov $0x0e0f, %ax
		and %dl, %al
		add $0x30, %al
		cmp $0x33, %al
		jl  outp
		add 0x07, %al
	outp:
		int $0x10
	loop print_digit
	ret

# 打印换行回车到屏幕
print_nl:
	mov $0x0e0a, %ax
	int $0x10
	mov $0x0e0d, %ax
	int $0x10
	ret

gdt:
	.word	0,0,0,0		# dummy

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9A00		# code read/exec
	.word	0x00C0		# granularity=4096, 386

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9200		# data read/write
	.word	0x00C0		# granularity=4096, 386

idt_48:
	.word	0			# idt limit=0
	.word	0,0			# idt base=0L

gdt_48:
	.word	0x800			# gdt limit=2048, 256 GDT entries
	.word   512+gdt, 0x9		# gdt base = 0X9xxxx, 
	# 512+gdt is the real gdt after setup is moved to 0x9020 * 0x10
msgss:
	.ascii "Now we are in setup.s ..."
	.byte 13,10
msgmem:
	.ascii "Memory size: 0x"
.text
endtext:
.data
enddata:
.bss
endbss:
