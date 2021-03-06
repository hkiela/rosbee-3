''=============================================================================
'' Stalker II control program program
'' HJK Aug 2012
'' Uses latest PID4b object with integrated encoders and QiK
'' PID extended for braking
'' This program is used to modify and test PID parameters
'' Uses 100 MHz clock and Xbee is trown out
'' PC comm version with messages adapted from 2DOF ethernet controller
''=============================================================================
'' Commands:  0, = Disable platform
''            1, = Enable platform. Steer servo's active
''            2,speed,dir, Move platform
''            3,speed, dir1, dir2,  Move platform  
''=============================================================================

DAT   Version Byte "Rosbee II V1.0 oct 2012 " , 0

CON
'Set 80Mhz
  _clkmode=xtal1+pll16x
' _clkmode = xtal1 + pll8x  'Spinstamp  
  '_xinfreq = 6250000      'MRS1  100 MHz
  _xinfreq = 5000000      'MRS1
'  _xinfreq = 10_000_000  'spin stamp

'' Led
  Led = 27
  
'' Serial port 
   CR = 13
   LF = 10
   CE = 11                 'CE: Clear to End of line
   TXD = 30
   RXD = 31
   Baud = 115200 '256000 '115200 '250000 '1000000 '115200 '230400 '115200
   CmdLen = 10
   ' Misc characters
   ST = 36 'dollar sign
   SEP = 44 'comma, used to seperate command params.
   MINUS = 45 'minus
   DOT = 46 'dot

'String buffer (depricated?)
  MaxStr = 257        'Stringlength is 256 + 1 for 0 termination

  SERIAL_MESSAGE_MAX_LENGTH = 64

'PID constants
  nPIDLoops = 2
  MotorCnt = nPIDLoops
  MotorIndex = MotorCnt - 1
'  Drive0   = 10           ' Drive 0 address, 2 motors per address
'  Drive1   = Drive0 +1    ' Drive 1

  PIDCTime = 10           ' PID Cycle time ms

'Serial pins QiK
  TXQ      = 26           ' Serial out to QiC
  RXQ      = 25           ' Serial in
  
' Quadrature encoders
  Enc0Pin  = 0            'Start pin
  EncCnt   = 2            'Number of encoders

   
'Terminal screen positions
  pControlPars = 0
  pActualPars = pControlPars + 12
  pMenu       = pActualPars + 24
  pInput      = pMenu + 18

'Platform status bits
   Serialbit     = 0              '0= Serial Debug of 1= Serial pdebug port on
   USAlarm       = 1              'US alarm bit: 1= object detected in range
   PingBit       = 2              '0= Ping off 1= Ping on
   EnableBit     = 3              '0= Motion DisablePfd 1= Motion enabled
   PCEnableBit   = 4              'PC Enable -> Pf Enable
   PCControlBit  = 5              'PC In control
   CommCntrBit   = 6              'Xbee Timout error
   MotionBit     = 7              'Platform moving
   FeBit         = 8              'FE error on any axis
   CurrBit       = 9              'Current error on any axis
   MAEBit        = 10             'MAE encoder alarm
   NoAlarmBit    = 15             'No alarm present   
 
OBJ
  t             : "Timing"
  PID           : "PID Connect V5_2"             ' PID contr. 4 loops. for wheels
  num             : "simple_numbers"                      ' Number to string conversion
  serial           : "FullDuplexSerial_rr005"              ' PC command and debug interface
  STRs          : "STRINGS2hk"
  
Var

  Byte SerialCog ' Cog for serial communication
  Byte SerialMSG[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the incoming string
  Byte ParserBuffer[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the parser
  Byte p ' Pointer to a position in the incoming string buffer

    Long SpeedCom, DoShowParameters, MainTime
    Long dTxPin, dRxPin     '' Debug serial port

    Long s, ms, us
    
    'Motors
    Long MPos[MotorCnt], MVel[MotorCnt], MInput[MotorCnt], MOutput[MotorCnt], PIDCog, PIDMode, PWMCog, CMDProcCog
    Long CMDProcStack[200]
    Long Setp[MotorCnt] 'Actual position and velocity, Setpoint
    Long EngU[MotorCnt] 'The user units for readout and commanding a servo motor
    Byte ActPID, SerCog
    
    'PID Connect vars                    
    Byte PIDCCog, QiKCog
    Long Err[PID#PIDCnt]                     'Last error in drive

    'Command program variables
    Byte Enable, Command, LastAlarm, PfStatus, PcControl  
'    Long pcSpeed, pcDirection, pcCntr, pcMoveMode, Sender, XbeeTime, XbeeCmdCntr, LastPar1[CmdLen]
    Long  Sender,  LastPar1[CmdLen], XbeeTime, XbeeCmdCntr

    'Platform vars
    Long MoveSpeed, MoveDir, lMoveSpeed, lMoveDir, MoveMode,  A2, Rv  'A1, A2 wheel angle, Rv is speed ratio
    
    Long DirRamp, SpeedRamp, Enabled, WheelsEnabled   
    Word MainCntr
        
    'Parameters for saving and loading a config
    Long StartVar, sK[MotorCnt], sKp[MotorCnt], sKI[MotorCnt], sILim[MotorCnt]
    Long sPosScale[MotorCnt], PlatFormID, Check
    Long EndVar

    'Input string handling
    Byte StrBuf[MaxStr], cStrBuf[MaxStr]        'String buffer for receiving chars from serial port
    Long StrSP, StrCnt, StrP, StrLen, XStat     'Instring semaphore, counter, Stringpointer
    Long SerEnabled, oSel0, CmdDone
    Long JoyComActive, PcComActive              'State var for comm monotoring
    Long MaxWaitTime    'Wait time for new Xbee string

    Long DebugCntr
    
  'Host reporting 
   Byte StrPIDReport[MaxStr]    'Position Report string for BG reporting
   Byte StrMiscReport[MaxStr]   'Report string various other data
'   Byte IPString[lMaxStr]        'String  with IP address            

 'Safety
  Long SafetyCog, SafetyStack[50], SafetyCntr, SafetyTimer, SafetyTimeout, SafetyTimerEnable, NoAlarm, CurrError
  
' ---------------- Main program ---------------------------------------
PUB main | lSpeed, lch , Offset, Up, Cntr, ii, OldCnt, T1
  InitMain
  !outa[Led]                             ' Toggle I/O Pin for debug
  pid.setpidmode(0,1) ' pid loop 0: velocity control (1)
  pid.setpidmode(1,1) ' pid loop 1: velocity control (1)
  setp[0] := 100
  setp[1] := 100
  enable := 1
  EnableWheels 'Disable

  wheelsenabled := 1
  lmovespeed := 1000

  move0(100,0)
  
  movemode := 0
  movespeed := 1000
  movedir := 0 
  repeat
    MainCntr++                            'Blink LED 50% DC during enable
    T1:=cnt                              
'    lch:= serialRxCheck                     ' Check serial port
    if serial.rxavail
      handleSerial
'      serial.position(40,0)
'      serial.dec(ii)
      lch:=0
 



    !outa[Led]                            'Toggle I/O Pin for debug
    MainTime:=(cnt-T1)/80000  
    t.Pause1ms(10)
PRI handleSerial | val, i, j, messageComplete, error  
  '!outa[LED]
  i := 0
  j := 0  
  messageComplete := false
  repeat until serial.rx == ST 'Busy wait until a '$' has been received
  repeat until messageComplete   
    val := serial.rx
    if (val == CR)
      messageComplete := true
      error := 0
    if(i == SERIAL_MESSAGE_MAX_LENGTH and ~messageComplete)
      messageComplete := true
      error := 1
    SerialMSG[i] := val
    i++
  '!outa[LED]  

  
  repeat until i == j
    serial.tx(SerialMSG[j])
    j++    
  
  case SerialMSG[0]
    "0":  'halt robot
      serial.str(string("$0")) 
      disableWheels
    "1":  'start robot
      serial.str(string("$1"))
      enableWheels                        
    "2":
      serial.str(string("$2")) ''This requires further string parsing.
      parseParam       
    other:
      serial.str(string("Unexpected message. Halting."))
      disableWheels
      
PRI parseParam | vx, vy, rot, error
  vx := 0
  vy := 0
  rot := 0
  p := 1 ''pointer binnen de parser 
  if(serialMSG[p] == SEP)
    p++
    vx := parseNumber(SEP, error)
    if(serialMSG[p] == SEP)
      p++
      vy := parseNumber(SEP, error)
      if(serialMSG[p] == SEP)
        p++
        rot := parseNumber(CR, error)
      else
        error += 4
    else
      error += 3
  else
    error += 2
  serial.str(string("Error: "))
  serial.dec(error)
  serial.str(string("Carret: "))
  serial.dec(p)
  serial.str(string("val: "))
  serial.char(serialMSG[p])
  serial.str(string("vx: "))
  serial.dec(vx)
  serial.str(string("vy: "))
  serial.dec(vy)
  serial.str(string("rot: "))
  serial.dec(rot)  
 ' machineOperate(vx,vy,rot)
  move0(vx,0)
  movemode := 0
  movespeed := vx
  movedir := 0


       
PRI parseNumber(term, error) : value | n, i, done, hasError
  value := 0 ''uiteindelijke returnwaarde
  i := 0 ''pointer voor de tijdelijke array
  done := false
  hasError := false
  
  repeat until done
    if serialMSG[p] == term or serialMSG[0] == 0
      done := true
    if (p == SERIAL_MESSAGE_MAX_LENGTH and not done)
      done := true
      hasError := true
      error += (2<<4)
    if(not done)
      ParserBuffer[i] := serialMSG[p]
      i++
      p++
  if(not hasError)  
    value := serial.strToDec(@ParserBuffer)   
  
  serial.str(string("Value: "))
  serial.dec(value)
  return value
   
'=================== Init Do Xbee comm ==========================
PRI DoCmdInit
  MaxWaitTime := 4000                    'ms wait time for incoming string  
  StrSp:=0
  
  JoyComActive:=0                      'Reset communication state var's
  PcComActive:=0
  
  ByteFill(@StrBuf,0,MaxStr)
  ByteFill(@cStrBuf,0,MaxStr)
  
'===== Do Xbee comm: Get Xbee string, parse it and process new values ==========================
PRI DoCommand 

    StrCnt++
'   StrInMaxTime(stringptr, maxcount,ms)
    serial.StrInMaxTime(@StrBuf,MaxStr,MaxWaitTime)   'Non blocking max wait time
    if Strsize(@StrBuf)>1                           'Received string must be larger than n char's skip rest
      ByteMove(@cStrBuf,@StrBuf,MaxStr)             'Copy received string in display buffer for debug

      XStat:=DoXCommand                             'Check input string for new commands

' ---------------- Process Input commands into motion commands---------------------------------------
PRI ProcessCommand
  MoveMode:=0

  Repeat
    DebugCntr++
    Move(MoveSpeed, MoveDir, MoveMode)
'    Move(100, 30, 0)



' ---------------- 'Move mode control platform -------------------------------
PRI Move(Speed, Dir, Mode)
  Case Mode
     0: Move0(Speed, Dir)   'Normal forward backward



    
' ---------------- 'Move platform with speed and direction front/rear wheel steering -----------------
PRI Move0(Speed, Dir) | lAngle   
  if Dir>lMoveDir   'Direction rampgenerator
    lMoveDir:=lMoveDir + DirRamp <# Dir

  if Dir<lMoveDir
    lMoveDir:=Dir #> lMoveDir - DirRamp
  
  if Speed>lMoveSpeed
    lMoveSpeed:=lMoveSpeed + SpeedRamp <# Speed

  if Speed<lMoveSpeed
    lMoveSpeed:=Speed #> lMoveSpeed - SpeedRamp

  if Speed==0    'Disable wheels to save battery
     DisableWheels
  else
    if Enabled
      EnableWheels
    else
      DisableWheels
      
  if WheelsEnabled
    Setp[0]:= -lMoveSpeed - lMoveDir
    Setp[1]:= lMoveSpeed  - lMoveDir


' -------------- DoXCommand: Get command parameters from Xbee input string --------------
PRI DoXCommand | OK, i, j, Par1, Par2, lCh, t1, c1     
  serial.position(0,40)
'  serial.position(0,10)
   serial.str(string("Debug XB "))
  t1:=cnt
  OK:=1

  StrP:=0  'Reset line pointer
  Sender:=0
  StrLen:=strsize(@StrBuf)  
  serial.dec(StrLen)
  serial.tx(" ")
  serial.str(@StrBuf)
  serial.tx(CE)
  serial.tx(CR)

  if StrLen > (MaxStr-1)       'Check max len
'    serial.dec(MaxStr-1)
'    serial.tx(" ")
    OK:=-1                      'Error: String too long
    
  if StrLen == 0                'Check zero length
    OK:=-2                      'Error: Null string
    
  if OK==1                      'Parse string
    lCh:=sGetch
'    serial.Tx(" ")
    repeat while (lch<>"$") and (OK == 1)       'Find start char
      serial.Tx(">")
'        Return -5  'timeout
      lCh:=sGetch
      if StrP == StrLen
        OK:=-3                  'Error: No Command Start char found
        Quit                    'Exit loop

    serial.str(string(" Sender : " ))
    if OK == 1
      Sender:=sGetPar
    serial.dec(Sender)
'    serial.Tx(" ")
'    serial.Tx("3")
'    lch:=sGetch   'Get comma
'     serial.tx(CR)
      Case Sender
        '=== Move commands from PC
        0: Enabled := false   'Disable platform
           ResetBit(@PfStatus,EnableBit)

        1: Enabled := true    'Enable platform 
           SetBit(@PfStatus,EnableBit)
'           Movespeed:=50

        2: MoveSpeed := sGetPar     
           serial.Tx(CR)
           MoveDir := sGetPar
           MoveMode := 0
             
        7:   ResetFe
             ResetPfStatus
             
        -99: serial.str(string(" -99: Unexpected end of str! " ))

        -98: serial.str(string(" -98: Unexpected end of str! " ))


       
  XbeeTime:=cnt-t1
  XbeeCmdCntr++    
Return OK

' ---------------- Get next parameter from string ---------------------------------------
PRI sGetPar | j, ii, lPar, Ch, minus2
  j:=0
  Bytefill(@LastPar1,0,CmdLen)   'Clear buffer

  serial.str(string(" In GetPar : " ))
'  serial.tx(Ch)
  repeat until Ch => "0" and Ch =< "9"  or Ch == "-" or Ch == 0    'skip non numeric
    serial.tx("{")
    ch:=sGetch
    serial.tx(Ch)

  if Ch == 0
'    serial.tx(">")
'    serial.str(string(" 1: Unexpected end of str! " ))
    Return -99  'error unexpected end of string

  if ch == "-"
    minus2:=true
    byte[@LastPar1][j++]:=ch   
    ch:=sGetch
  else
    minus2:=false
      
  serial.str(string(" GetPar : " ))
  repeat while  Ch => "0" and Ch =< "9"
'    if Ch == 0
'      serial.tx(">")
'      serial.str(string(" 2: Unexpected end of str! " ))
'      Return -98  'error unexpected end of string
    if j=<CmdLen
'      serial.tx("|")
'      serial.dec(j)
'      serial.tx(">")
'      serial.tx(Ch)
      byte[@LastPar1][j]:=ch
      j++
      serial.str(@LastPar1)
      Ch:=sGetch           'skip next
 
  serial.str(string(" Par : " ))
  serial.str(@LastPar1)
  LPar:=serial.strtodec(@LastPar1)
  serial.tx("=")
  serial.dec(lPar)
  serial.tx(" ")
Return Lpar

' ---------------- Get next character from string ---------------------------------------
Pri sGetCh | lch 'Get next character from commandstring
   lch:=Byte[@StrBuf][StrP++]
   serial.tx("\")          
   serial.tx(lch)
'   Cmd[Lp++]:=lch
Return lch

' ----------------  Send Version to PC   ---------------------------------------
PRI DoVersion2PC   
  strs.EraseString(@StrMiscReport)  'Init report string
  strs.concatenate(@StrMiscReport,string("$95,"))

  strs.concatenate(@StrPIDReport,@Version)
  strs.concatenate(@StrPIDReport,string(", "))

  strs.concatenate(@StrPIDReport,string("#",CR))  
' ----------------  Set output   ---------------------------------------
PRI DoSetOutput(ParNr, Value)   

' ----------------  Get input and send value to PC  ---------------------------------------
PRI DoGetInput2PC(ParNr)  

' ----------------  ResetController   ---------------------------------------
PRI ResetController 
  Reboot

' ----------------  Reset max motor Current      ---------------------------------------
PRI ResetCurrent    
  PID.ResetMaxCurrent

' ---------------- 'Reset current errors -------------------------------
PRI ResetCurError | i
  PID.ResetCurrError


' ----------------  Clear Max current ---------------------------------------
PRI ResetMaxCurrent | i 
  PID.ResetCurrError


' ----------------  Clear errors of drives ---------------------------------------
PRI ClearErrors | i 
  repeat i from 0 to PID#PIDCnt-1
    Err[i]:=0
 
 ' ----------------  Enable wheels  ---------------------------------------
PRI EnableWheels
  PID.SetPIDMode(0,1)                     'Enable vel wheel and
  PID.SetPIDMode(1,1)               
  WheelsEnabled:=true

' ----------------  Disable wheels  ---------------------------------------
PRI DisableWheels
  PID.SetPIDMode(0,0)                     'Disable vel wheel and
  PID.SetPIDMode(1,0)                 
  WheelsEnabled:=false
  
' ----------------  Brake wheels  ---------------------------------------
PRI BrakeWheels(BrakeValue) | lB

  PID.BrakeWheels(BrakeValue)                     'Brake wheels
                    
'  ShowParameters
  
' ----------------  Disable all wheels and steerin ---------------------------------------
PRI Disable 
  PID.KillAll
  Enabled:=false
'  ShowParameters  

' ---------------- Reset platform -------------------------------
PRI ResetPfStatus 

  pid.ClearErrors
  PfStatus:=0
  ResetBit(@PfStatus,USAlarm)          'Reset error bits in PfStatus
  ResetBit(@PfStatus,CommCntrBit)
  SetBit(@PfStatus,NoAlarmBit)
  NoAlarm:=true                        'Reset global alarm var
  LastAlarm:=0                         'Reset last alarm message
  
'  PcSpeed:=0                           'Reset setpoints
  MoveSpeed:=0
  MoveDir:=0
 
' ----------------  Clear FE trip ---------------------------------------
PRI ResetFE | i 
  PID.ResetAllFETrip
  ResetBit(@PfStatus,FEbit)

' ----------------  Set PID parameter  ---------------------------------------
PRI SetPIDParameter(ParNr, ServoNr, Value)
  Case ParNr
    0: PID.SetKi(ServoNr,Value)             '#0
    1: PID.SetK(ServoNr,Value)              '#1
    2: PID.SetKp(ServoNr,Value)             '#2
    3: PID.SetIlimit(ServoNr,Value)         '#3
    4: PID.SetPosScale(ServoNr,Value)       '#4
    5: PID.SetVelScale(ServoNr,Value)       '#5
    6: PID.SetFeMax(ServoNr,Value)          '#6
    7: PID.SetMaxVel(ServoNr,Value)         '#7
    8: PID.SetMaxCurr(ServoNr,Value)        '#8
    
' ----------------  Set PID pars not default ---------------------------------------
PRI SetPIDPars | i
  'Set control parameters wheels
  PID.SetKi(0,800)
  PID.SetK(0,1000)
  PID.SetKp(0,1000)
  PID.SetIlimit(0,1000)
  PID.SetPosScale(0,1)
  PID.SetFeMax(0,200)
  PID.SetMaxCurr(0,4500)
  
  PID.SetKi(1,800)
  PID.SetK(1,1000)
  PID.SetKp(1,1000)
  PID.SetIlimit(1,1000)
  PID.SetPosScale(1,1)
  PID.SetFeMax(1,200)
  PID.SetMaxCurr(1,4500)

  PlatformID:=2001
  DirRamp:=10
  SpeedRamp:=1

' ----------------  Init main program ---------------------------------------
PRI InitMain
  dira[Led]~~                             'Set I/O pin for LED to output…
  !outa[Led]                              'Toggle I/O Pin for debug
  SerCog:=serial.start(RXD, TXD, 0, Baud)     'Start serial:  start(pin, baud, lines)  serial.Clear
  t.Pause1ms(100)

  !outa[Led]                               'Toggle I/O Pin for debug
  serial.tx(serial#CS)
  t.Pause1ms(100)
  
  DoShowParameters:=true

'  serial.str(string("Tx and Rx pn settings: "))
'  serial.dec(dRxPin)
'  serial.Tx(" ")
'  serial.dec(dTxPin) 
'  serial.tx(CR)

  !outa[Led]                           'Toggle I/O Pin for debug
  DoCmdInit
  !outa[Led]                           'Toggle I/O Pin for debug


  CMDProcCog := cognew(ProcessCommand, @CMDProcStack)

  t.Pause1ms(100)

  
''-------- This Block Starts the PWM Object ----------
'{  PWMCog:=PWM.Start                    ' Initialize PWM cog
 { PWM.Servo(Steer0,SteerOffset[0])     ' Define Pin0 with a standard center position servo signal ; 1500 = 1.5ms
  PWM.Servo(Steer1,SteerOffset[1])       
  PWM.Servo(Steer2,SteerOffset[2])     
  PWM.Servo(Steer3,SteerOffset[3])      
 }
  !outa[Led]                               'Toggle I/O Pin for debug
  
'  PIDCog:=PID.Start(PIDCTime, @Setp, nPIDLoops)  
  PIDCog:=PID.Start(PIDCTime, @Setp,  Enc0Pin, EncCnt, TxQ, RxQ, nPIDLoops) 'thr4, 5 and 6
  PIDMode:=PID.GetPIDMode(0)                            'Set open loop mode
  repeat while PID.GetPIDStatus<>2                      'Wait while PID initializes

  SetPIDPars
'  ShowParameters                                        'Show control parameters
  !outa[Led]                                            'Toggle I/O Pin for debug


  t.Pause1ms(1000)
  !outa[Led]                        'Toggle I/O Pin for debug

   Enabled:=false                    

' ----------------  Clear input area ---------------------------------------
PRI ClearInputArea  | i
  serial.Position(0,pInput)
  serial.tx(">")                              
  repeat i from 0 to 5
    serial.str(string("                                                                 "))
    serial.tx(CE)
    serial.tx(CR)  

' ---------------- 'Set bit in 32 bit Long var -------------------------------
PRI SetBit(VarAddr,Bit) | lBit, lMask
  lBit:= 0 #> Bit <# 31    'Limit range
  lMask:= |< Bit           'Set Bit mask
  Long[VarAddr] |= lMask   'Set Bit
    

' ---------------- 'Reset bit in 32 bit Long var -------------------------------
PRI ResetBit(VarAddr,Bit) | lBit, lMask
  lBit:= 0 #> Bit <# 31    'Limit range
  lMask:= |< Bit           'Set Bit mask
  
  Long[VarAddr] &= !lMask  'Reset bit
    
' ---------------- 'Test bit in 32 bit Long var -------------------------------
PRI TestBit(VarAddr,Bit) | lBit, lMask
  lBit:= 0 #> Bit <# 31    'Limit range
  lMask:= |< Bit           'Set Bit mask
Return Long[VarAddr] | lMask >> 0   'Test Bit     Nog testen


   
{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}