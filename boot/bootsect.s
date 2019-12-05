	.code16
# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
# SYS_SIZE is the number of clicks (16 bytes) to be loaded.
# 0x3000 is 0x30000 bytes = 196kB, more than enough for current
# versions of linux
#
	.equ SYSSIZE, SYS_SIZE
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# iself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE! currently system is at most 8*65536 bytes long. This should be no
# problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

	.equ SETUPLEN, 4		# nr of setup-sectors
	.equ BOOTSEG, 0x07c0		# original address of boot-sector
	.equ INITSEG, 0x9000		# bootsect.s被移动到0x90000
	.equ SETUPSEG, 0x9020		# setup starts here
	.equ SYSSEG, 0x1000		# system loaded at 0x10000 (65536).
	.equ ENDSEG, SYSSEG + SYSSIZE	# where to stop loading

# ROOT_DEV:	0x000 - same type of floppy as boot.
#		0x301 - first partition on first drive etc
	.equ ROOT_DEV, 0x301
	ljmp    $BOOTSEG, $_start
_start:
	mov	$BOOTSEG, %ax
	mov	%ax, %ds
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$256, %cx
	sub	%si, %si
	sub	%di, %di
	rep	
	movsw
	ljmp	$INITSEG, $go # cs中为$INITSEG，eip中为$go
go:	mov	%cs, %ax
	mov	%ax, %ds
	mov	%ax, %es
# put stack at 0x9ff00.
	mov	%ax, %ss
	mov	$0xFF00, %sp		# arbitrary value >>512

# load the setup-sectors directly after the bootblock.
# Note that 'es' is already set up.

load_setup:
	mov	$0x0000, %dx		# dh为磁头号，即磁头为0，dl为驱动号，驱动为0
	mov	$0x0002, %cx		# ch为磁道号低8位，即磁道为0，cl为开始扇区，开始扇区是2
	mov	$0x0200, %bx		# address = 512, in INITSEG
	.equ    AX, 0x0200+SETUPLEN  # AH为0x02表示读磁盘扇区到内存，AL为0x04表示读取4个扇区
	mov     $AX, %ax		# es:bx指向数据缓冲区，如果出错那么CF标志置位
	int	$0x13				# read it
	jnc	ok_load_setup		# ok - continue，如果carry flag没有置位跳转到ok_load_setup
	mov	$0x0000, %dx
	mov	$0x0000, %ax		# reset the diskette
	int	$0x13
	jmp	load_setup

ok_load_setup:

# 获取磁盘参数，特别是每个磁道的扇区数

	mov	$0x00, %dl			# DL为驱动器号0
	mov	$0x0800, %ax		# AH为0表示获取磁盘参数
	int	$0x13
	mov	$0x00, %ch			# BL包含驱动器类型,CH最大磁道号的低8位，CL包含每磁道最大扇区数，DH最大磁头数，DL驱动器数量，
							# ES:DI磁盘参数表，出错则CF置位，ah为状态码
	#seg cs
	mov	%cx, %cs:sectors+0	# 保存磁道扇区数到sectors变量中
	mov	$INITSEG, %ax		# 恢复ES，值为0x9000
	mov	%ax, %es

# 打印一些信息，中断参考https://zh.wikipedia.org/wiki/INT_10H

	mov	$0x03, %ah			# 读取光标位置
	xor	%bh, %bh			# BX包含页码参数
	int	$0x10
							# 返回值中DH为行高，DL为列
	mov	$25, %cx			# CX保存字符串长度
	mov	$0x0007, %bx		# BH为页码，第0页，BL为颜色，page 0, attribute 7 (normal)
	mov $msg1, %bp			# ES:BP为字符串偏移
	mov	$0x1301, %ax		# AH=0x13表示写字符串，AL=0x01表示写模式
	int	$0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

	mov	$SYSSEG, %ax		# SYSSEG为0x1000，也就是将system加载到内存0x10000开始的内存地址
	mov	%ax, %es			# segment of 0x010000
	call	read_it			# ES为输入，读取system到内存
	call	kill_motor		# 关闭电机

/*
	在Linux中软驱的主设备号是2，次设备号=type*4+nr，其中type为2表示1.2MB类型，7为1.44MB类型
	nr为0至3对应软驱A、B、C、D，那么/dev/PS0(2,28)对应的28=7*4+0，即1.44MB类型的软驱A
*/
	#seg cs					# 使用CS段
	mov	%cs:root_dev+0, %ax # 取root_dev处定义的根设备号
	cmp	$0, %ax				# 如果ax为0，表示根设备号没有被定义
	jne	root_defined
	#seg cs
	mov	%cs:sectors+0, %bx	# 获取扇区数
	mov	$0x0208, %ax		# /dev/ps0 - 1.2Mb
	cmp	$15, %bx			# 比较扇区数
	je	root_defined
	mov	$0x021c, %ax		# /dev/PS0 - 1.44Mb
	cmp	$18, %bx
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	#seg cs
	mov	%ax, %cs:root_dev+0

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:

	ljmp	$SETUPSEG, $0	# 跳转到0x90200地址

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
sread:	.word 1+ SETUPLEN		# 当前已经读的扇区数，sectors read of current track
head:	.word 0					# 当前的磁头号，current head
track:	.word 0					# 当前的磁道，current track

read_it:
	mov	%es, %ax
	test	$0x0fff, %ax    	# 0x0fff & AX 进行与计算，因为里面存的是段地址,需要进4为所以相当于0xffff&AX
die:	jne 	die				# es must be at 64kB boundary
	xor 	%bx, %bx			# bx为当前段的起始地址，bx is starting address within segment
rp_read:
	mov 	%es, %ax
 	cmp 	$ENDSEG, %ax		# ENDSEG是系统镜像的大小加起始地址0x10000, have we loaded all yet?
	jb	ok1_read				# ax != ENDSEG时跳转
	ret
ok1_read:
	#seg cs
	mov	%cs:sectors+0, %ax		# 磁道上扇区数
	sub	sread, %ax				# 扇区数-已读扇区数=剩下的扇区AX
	mov	%ax, %cx				
	shl	$9, %cx					# cx=cx*512
	add	%bx, %cx				# cx=cx+bx，此次读操作后段内读入字节数
	jnc 	ok2_read			# jnc表示当前的加法没有进位，即没有超过16位（64K）
	xor 	%ax, %ax			# AX清0
	sub 	%bx, %ax			# AX为0x0000 - bx得到，段内最多还能读取多少字节
	shr 	$9, %ax				# 将字节转化为扇区，也就是段内还能存放多少扇区
ok2_read:
	call 	read_track
	mov 	%ax, %cx
	add 	sread, %ax
	#seg cs
	cmp 	%cs:sectors+0, %ax
	jne 	ok3_read
	mov 	$1, %ax
	sub 	head, %ax
	jne 	ok4_read
	incw    track 
ok4_read:
	mov	%ax, head
	xor	%ax, %ax
ok3_read:
	mov	%ax, sread
	shl	$9, %cx
	add	%cx, %bx
	jnc	rp_read
	mov	%es, %ax
	add	$0x1000, %ax
	mov	%ax, %es
	xor	%bx, %bx
	jmp	rp_read

read_track:
	push	%ax
	push	%bx
	push	%cx
	push	%dx
	mov	track, %dx			# 当前磁道号
	mov	sread, %cx			# 已经读取的扇区数
	inc	%cx					# 增加扇区号
	mov	%dl, %ch			# 当前磁道扇区号
	mov	head, %dx			# 磁头号
	mov	%dl, %dh			# 磁头号
	mov	$0, %dl				# 驱动器号
	and	$0x0100, %dx		# 磁头号不大于1
	mov	$2, %ah				# 读取磁盘扇区
	int	$0x13				# 读取的ES:BX
	jc	bad_rt				# 出错则跳转到bad_rt
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	ret
bad_rt:	mov	$0, %ax			# AX=0是重置磁盘
	mov	$0, %dx
	int	$0x13
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	jmp	read_track

#  关闭软驱电动机
kill_motor:
	push	%dx
	mov	$0x3f2, %dx			# 软驱控制卡驱动端口
	mov	$0, %al
	outsb  					# 将ES:SI
	pop	%dx
	ret

sectors:
	.word 0

msg1:
	.ascii "Loading SS's system ..."
	.byte 13,10

	.org 508
root_dev:
	.word ROOT_DEV # 508字节和509字节定义根设备号
boot_flag:
	.word 0xAA55
	
	.text
	endtext:
	.data
	enddata:
	.bss
	endbss:
