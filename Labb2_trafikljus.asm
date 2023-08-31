.eqv ENABLE_INT 0x1

.eqv INTERNAL_INT_MSK 0x7C
.eqv EXT_TIME_INT 0x400
.eqv EXT_BUTTON_INT 0x800

.eqv PED_TL_ADDRESS 0xFFFF0010
.eqv NORMAL_TL_ADDRESS 0xFFFF0011
.eqv ENABLE_TIMER_ADDRESS 0xFFFF0012
.eqv BUTTON_PRESSED_ADDRESS 0xFFFF0013
	
	.data 
timer: 	.word 0
state: .space 1 # state carsTL/pedTL # 0 => green/red | 1 => yellow/red | 2 => red/green | 3 => red/redB | 4 => yellow/red

isButtonPressed: .space 1 #sticky button

	.ktext 0x80000180
	la $k0, interrupt
	jr $k0 
	nop
	
	.text

main:
	# starting colors green_red
	sb $zero, state		
	la $t0, PED_TL_ADDRESS
	addi $t1, $zero, 1
	sb $t1, 0($t0)
	la $t0, NORMAL_TL_ADDRESS
	addi $t1, $zero, 4
	sb $t1, 0($t0)
	
	#prepare interrupt
	mfc0 $t0, $12			# get status register
	ori $t0, $t0, EXT_TIME_INT 	# bit 10 => 1
	ori $t0, $t0, EXT_BUTTON_INT 	# bit 11 => 1
	ori $t0, $t0, ENABLE_INT	# bit 0  => 1
	mtc0 $t0, $12			# set status register
	
	
	#set button pressed resently to 0 (false)
	sb $zero, isButtonPressed
	
	# enable the timer
	la $a0, ENABLE_TIMER_ADDRESS
	addi $t0, $zero, 1 
	sb $t0, 0($a0)

loop:
	nop
	j loop
	
	li $v0, 10	# exit
	syscall

interrupt:
	subu $sp, $sp, 24
	sw $t0, 0($sp)
	sw $t1, 4($sp)
	sw $t2, 8($sp)
	sw $a0, 12($sp)
	sw $ra, 16($sp)
	
	mfc0 $k1, $13	#get cause 
	# check if any internal interrupts
	andi $t0, $k1, INTERNAL_INT_MSK # bit [3 - 8]
	bne $t0, $zero, restore # do nothing
	
	#check external interrupts
	andi $t0, $k1, EXT_TIME_INT	# read bit 10 from cause
	bne $t0, $zero, runTimer
	andi $t0, $k1, EXT_BUTTON_INT
	bne $t0, $zero, buttonPressed
	
	j restore	#should never get here
	
blink:
	subu $sp, $sp, 16
	sw $t0, 0($sp)
	sw $t1, 4($sp)
	
	#change colors to red_redB
	#cars traffic light red
	la $t0, NORMAL_TL_ADDRESS
	addi $t1, $zero, 1
	sb $t1, 0($t0)
	#pedestrians traffic light redB
	lw $t0, timer 		
	add $t2, $t2, $t0	# fix offset t2 is argument # t2 is now the timer 
	la $t0, PED_TL_ADDRESS
	andi $t2, $t2, 1	# first bit is used for checking odd or even timer 
	bne $t2, $zero, dark
	#light:
	addi $t1, $zero, 1	#light
	j light
	dark:
	addi $t1, $zero, 0	#dark
	light:
	sb $t1, 0($t0)
	

	lw $t0, 0($sp)
	lw $t1, 4($sp)
	addu $sp, $sp, 16
	jr $ra
runTimer:
	
	# prepare max timer to send as an argument to MODTimer
	lb $a0, state
	
	addi $t1, $zero, 0		# if current state is green_red
	beq $a0, $t1, max_timer_10	# set max timer to 10
	
	addi $t1, $zero, 2		# if current state is red_green
	beq $a0, $t1, max_timer_7	# set max timer to 7
	
	addi $t1, $zero, 1		# if current state is yellow_red
	beq $a0, $t1, max_timer_3	# set max timer to 3
	
	addi $t1, $zero, 4		# if current state is yellow2_red 
	beq $a0, $t1, max_timer_3	# set max timer to 3
	
	addi $t1, $zero, 3		# if current state is red_redB
	addi $t2, $zero, 0		# today we use t2 as argument cuz why not (this is used just to avoid effecting time in blink function)
	jal blink			# deal with blinking lights (does not modify any register)
	beq $a0, $t1, max_timer_3	# set max timer to 3
	
	
	max_timer_10:
	addi $a0, $zero, 10		# set MODTimer argument $a0 to 10 
	j start_MODTimer
	
	max_timer_7:
	addi $a0, $zero, 7		# set MODTimer argument $a0 to 7
	j start_MODTimer
	
	max_timer_3:
	addi $a0, $zero, 3		# set MODTimer argument $a0 to 3
	j start_MODTimer
	
	start_MODTimer:
	jal MODTimer
	
	# (timer = maxtimer && isButtonPressed = 1) => modify state 		 a * b 
	# (timer !=maxtimer || isButtonPressed = 0) => do not modify state	(a'+ b')'
	# if timer != max timer and button is pressed not pressed skip modifying state
	bne $t0, $a0, restore 		# timer != maxtimer # should not bother with moving to next state if the timer did not reach max time
	lb $t1, isButtonPressed
	beq $t1, $zero, skip_MOD_state 	# if the sticky botton is not pressed previusly skip modifying the state
	
	regret_skip_MOD_state:
	j nextState		# move the the next state 
	
	skip_MOD_state:
	lb $a0, state
	addi $t1, $zero, 3
	# this is here becuse the sticky button (isButtonPressed) is set to 0 before a full round is done
	# extra feature "walkers can press the button while the light is blinking red"
	bge $a0, $t1, regret_skip_MOD_state #regret skip mod state if the state is yellow/redB (state = 3)
	j restore		#skip MOD_State
	
MODTimer:
	
	# else increase the timer by 1 if it is less than the argument $a0
	lw $t0, timer
	beq $t0, $a0, skip_increase
	addi $t0, $t0, 1
	sw $t0, timer

	skip_increase:
	jr $ra	

nextState:
	lb $t0, state
	# cars
	# 1 read
	# 2 yellow
	# 4 green
	
	# ped
	# 0 dark 
	# 1 red
	# 2 green
	
	green_red:
	addi $t1, $zero, 0
	bne $t0, $t1, yellow_red# jump to next check if current state is not green_red
	addi $t1, $zero, 1
	sb $t1, state		# next state (1)
	sw $zero, timer 	# reset timer 
	#change colors to yellow_red
	#cars traffic light yellow
	la $t0, NORMAL_TL_ADDRESS
	addi $t1, $zero, 2	
	sb $t1, 0($t0)		# yellow
	#pedestrians traffic light is allready red so no modification needed
	# ...
	j restore
	
	
	yellow_red:
	addi $t1, $zero, 1
	bne $t0, $t1, red_green	# jump to next check if current state is not yellow_red
	addi $t1, $zero, 2
	sb $t1, state		# next state (2)
	sw $zero, timer		# reset timer
	#change colors to red_green
	#cars traffic light red
	la $t0, NORMAL_TL_ADDRESS
	addi $t1, $zero, 1
	sb $t1, 0($t0)		# red
	#pedestrians traffic light green
	la $t0, PED_TL_ADDRESS
	addi $t1, $zero, 2
	sb $t1, 0($t0)		# green
	j restore
	
	
	red_green:
	addi $t1, $zero, 2
	bne $t0, $t1, red_redB# jump to next check if current state is not red_green
	addi $t1, $zero, 3
	sb $t1, state		# next state (3)
	sw $zero, timer		# reset timer
	# change isButtonPressed to 0 
	# enabling pedestrians button 
	la $t1, isButtonPressed 
	sb $zero, 0($t1)
	##problem for blinking lights solved in the blink function 
	addi $t2, $zero, 1	# start blinking dark # t2 is an argument in blink
	jal blink
	j restore
	
	
	red_redB: 		#if none of the above then it should be yellow_redB no more checks is needed
	addi $t1, $zero, 3
	bne $t0, $t1, yellow2_red# jump to next check if current state is not red_redB
	addi $t1, $zero, 4
	sb $t1, state		# next state (4)
	sw $zero, timer		# reset timer
	#change colors to yellow_red
	#cars traffic light yellow
	la $t0, NORMAL_TL_ADDRESS
	addi $t1, $zero, 2
	sb $t1, 0($t0)
	#pedestrians traffic light red
	la $t0, PED_TL_ADDRESS
	addi $t1, $zero, 1
	sb $t1, 0($t0)
	j restore
	
	yellow2_red:
	sb $zero, state		# next state (0)
	sw $zero, timer 	# reset timer 
	#change colors to green_red
	#cars traffic light green
	la $t0, NORMAL_TL_ADDRESS
	addi $t1, $zero, 4
	sb $t1, 0($t0)
	#pedestrians traffic light is allready red so no modification needed
	# ...
	j restore
	
	
	
buttonPressed:
	
	# restore if drive button is pressed
	la $a0, BUTTON_PRESSED_ADDRESS
	lb $t0, 0($a0)
	addi $t1, $zero, 2		
	beq $t0, $t1, restore 
	
	# else walk button is pressed
	
	#set button pressed resently to 1 (true)
	la $t0, isButtonPressed
	addi $t1, $zero, 1
	sb $t1, 0($t0)
	
	j restore

restore:
	
	lw $t0, 0($sp)
	lw $t1, 4($sp)
	lw $t2, 8($sp)
	lw $a0, 12($sp)
	lw $ra, 16($sp)
	addu $sp, $sp, 24
	
	#CLEAR TIMER and BUTTON FROM CAUSE REGISTER
	li $k0, EXT_TIME_INT
	li $k1, EXT_BUTTON_INT
	or $k0, $k0, $k1
	xori $k0, $k0, 0xFFFFFFFF
	mfc0 $k1, $13
	and $k0, $k1, $k0
	mtc0 $k0, $13
	
	eret
