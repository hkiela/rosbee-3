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

DAT   Version Byte "Rosbee II V1.1 June 2013 " , 0

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

'String buffer
  MaxStr = 257        'Stringlength is 256 + 1 for 0 termination

'PID constamts
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
'  ser           : "Parallax Serial Terminal"           ' Serial communication object
  t             : "Timing"
  PID           : "PID Connect V5_3"                    ' PID contr. 4 loops. for wheels
  num             : "simple_numbers"                    ' Number to string conversion
  Ser           : "FullDuplexSerial_rr005"              ' PC command and debug interface
'  PWM           : "PWM_32_v4.spin"                     ' Steer servo pwm
  STRs          : "STRINGS2hk"
  
Var Long SpeedCom, DoShowParameters, MainTime
    Long dTxPin, dRxPin     '' Debug serial port

    Long s, ms, us
    
    'Motors
    Long MPos[MotorCnt], MVel[MotorCnt], MInput[MotorCnt], MOutput[MotorCnt], PIDCog, PIDMode, PWMCog, CMDProcCog
    Long CMDProcStack[200]
    Long Setp[MotorCnt] 'Actual position and velocity, Setpoint
    Long EngU[MotorCnt] 'The user units for readout and commanding a servo motor
    Byte ActPID, SerCog
    
    'PID Connect vars                    
    Long PIDCCog, QiKCog
    Long Err[PID#PIDCnt]                     'Last error in drive

    'Command program variables
    Long Enable, Command, LastAlarm, PfStatus, PcControl  
'    Long pcSpeed, pcDirection, pcCntr, pcMoveMode, Sender, XbeeTime, XbeeCmdCntr, LastPar1[CmdLen]
    Long  Sender,  LastPar1[CmdLen], XbeeTime, XbeeCmdCntr

    'Platform vars
    Long MoveSpeed, MoveDir, lMoveSpeed, lMoveDir, MoveMode,  A2, Rv  'A1, A2 wheel angle, Rv is speed ratio
    
    Long DirRamp, SpeedRamp, Enabled, WheelsEnabled   
    Word MainCntr
        
    'Parameters for saving and loading a config
    Long StartVar, sK[MotorCnt], sKp[MotorCnt], sKI[MotorCnt], sILim[MotorCnt]
    Long sPosScale[MotorCnt], InvertOutput[MotorCnt], InvertVelEncoder[MotorCnt], InvertPosEncoder[MotorCnt], PlatFormID
    Long  Check, EndVar

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

  EnableWheels 'Disable

  repeat
    MainCntr++                            'Blink LED 50% DC during enable
    T1:=cnt                              
'    lch:= ser.RxCheck                     ' Check serial port
    if ser.rxavail
      DoCommand
'      ser.position(40,0)
'      ser.dec(ii)
      lch:=0
 
'    DoXbeeCmd
 '     DoCommand
'    ProcessCommand
    
 '   if DoShowParameters
    if MainCntr // 50 == 0
      ShowScreen
      ShowParameters


 '   !outa[Led]                            'Toggle I/O Pin for debug
    MainTime:=(cnt-T1)/80000  
    t.Pause1ms(10)
   
'=================== Init Do Xbee comm ==========================
PRI DoCmdInit
  MaxWaitTime := 4000                    'ms wait time for incoming string  
  StrSp:=0
  
  JoyComActive:=0                      'Reset communication state var's
  PcComActive:=0
  
  ByteFill(@StrBuf,0,MaxStr)
  ByteFill(@cStrBuf,0,MaxStr)
  
'  XbeeCog:=xBee.start(xTXD, xRXD, 0, xBaud)     'Start xbee:  start(pin, baud, lines)


'===== Do Xbee comm: Get Xbee string, parse it and process new values ==========================
PRI DoCommand 

    StrCnt++
'   StrInMaxTime(stringptr, maxcount,ms)
    Ser.StrInMaxTime(@StrBuf,MaxStr,MaxWaitTime)   'Non blocking max wait time
    if Strsize(@StrBuf)>1                           'Received string must be larger than n char's skip rest
      ByteMove(@cStrBuf,@StrBuf,MaxStr)             'Copy received string in display buffer for debug
'   StrSp:=0
'      ser.tx("b")

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
    -1: 'Nothing
    0: Move0(Speed, Dir)   'Normal forward backward
{    1: Move1(Speed/3, Dir)   'Cross movement
    2: Move2(Speed/8, Dir)   'Rotate
    3: Move3                 'individual wheels
 }

' ---------------- 'Disable move of platform -------------------------------
PUB DisableMove
  Enabled := false   'Disable platform
  ResetBit(@PfStatus,EnableBit)
  MoveSpeed:=0
  MoveDir:=0

' ---------------- 'Enable move of platform -------------------------------
PUB EnableMove
  Enabled := true    'Enable platform 
  SetBit(@PfStatus,EnableBit)
  Movespeed:=0
  MoveDir:=0
      
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
  ser.position(0,40)
'  ser.position(0,10)
   ser.str(string("Debug XB "))
  t1:=cnt
  OK:=1

  StrP:=0  'Reset line pointer
  Sender:=0
  StrLen:=strsize(@StrBuf)  
  ser.dec(StrLen)
  ser.tx(" ")
  ser.str(@StrBuf)
  ser.tx(CE)
  ser.tx(CR)

  if StrLen > (MaxStr-1)       'Check max len
'    ser.dec(MaxStr-1)
'    ser.tx(" ")
    OK:=-1                      'Error: String too long
    
  if StrLen == 0                'Check zero length
    OK:=-2                      'Error: Null string
    
  if OK==1                      'Parse string
    lCh:=sGetch
'    ser.Tx(" ")
    repeat while (lch<>"$") and (OK == 1)       'Find start char
      ser.Tx(">")
'        Return -5  'timeout
      lCh:=sGetch
      if StrP == StrLen
        OK:=-3                  'Error: No Command Start char found
        Quit                    'Exit loop

    ser.str(string(" Sender : " ))
    if OK == 1
      Sender:=sGetPar
    ser.dec(Sender)
'    ser.Tx(" ")
'    ser.Tx("3")
'    lch:=sGetch   'Get comma
'     ser.tx(CR)
      Case Sender
        '=== Move commands from PC
        0: DisableMove
           'Enabled := false   'Disable platform
           'ResetBit(@PfStatus,EnableBit)

        1: EnableMove                    'Enableplatform

        2: MoveSpeed := sGetPar          'New speed and direction command
           ser.Tx(CR)
           MoveDir := sGetPar
           MoveMode := 0
             
        7:   ResetFe                      'Reset errors
             ResetPfStatus
             
        -99: ser.str(string(" -99: Unexpected end of str! " ))

        -98: ser.str(string(" -98: Unexpected end of str! " ))


 '       902: PcControl:=sGetpar   'Enable DisablePf PC control 1 = pc 0 is joystick

{        905: PcComActive:= 1
             JoyComActive:=0
             PcCntr := sGetPar
             wSpeed[0]:=sGetPar   ' wSpeed[nWheels], wAngle[nWheels]               
             wSpeed[1]:=sGetPar               
             wSpeed[2]:=sGetPar               
             wSpeed[3]:=sGetPar
             wAngle[0]:=sgetPar              
             wAngle[1]:=sgetPar              
             wAngle[2]:=sgetPar              
             wAngle[3]:=sgetPar
             pcMoveMode:=3  'individual wheel control              
}          
 '       906: 'PcComActive:=1      'Autonomous mode

{        908: ResetPfStatus        'Reset platform status
'             ResetMaxCurrent
             pid.ResetCurrError
             ResetPfStatus   
       909: PingEnable := sGetPar
             DoUSsensors(PingEnable)
}            
        '=== Status commands
'        911: DoSensors2PC   'US sensors
''        912: DoStatus2PC     'Status and errors
''        913: DoPos2Pc        'Position to PC
''        914: DoCurrents2PC   'Report currents
''        916: DoPIDSettings   'Send PID parameters to PC   
       
  XbeeTime:=cnt-t1
  XbeeCmdCntr++    
Return OK

' ---------------- Get next parameter from string ---------------------------------------
PRI sGetPar | j, ii, lPar, Ch, minus
  j:=0
  Bytefill(@LastPar1,0,CmdLen)   'Clear buffer

  ser.str(string(" In GetPar : " ))
'  ser.tx(Ch)
  repeat until Ch => "0" and Ch =< "9"  or Ch == "-" or Ch == 0    'skip non numeric
    ser.tx("{")
    ch:=sGetch
    ser.tx(Ch)

  if Ch == 0
'    ser.tx(">")
'    ser.str(string(" 1: Unexpected end of str! " ))
    Return -99  'error unexpected end of string

  if ch == "-"
    minus:=true
    byte[@LastPar1][j++]:=ch
    ch:=sGetch
  else
    minus:=false
      
  ser.str(string(" GetPar : " ))
  repeat while  Ch => "0" and Ch =< "9"
'    if Ch == 0
'      ser.tx(">")
'      ser.str(string(" 2: Unexpected end of str! " ))
'      Return -98  'error unexpected end of string
    if j=<CmdLen
'      ser.tx("|")
'      ser.dec(j)
'      ser.tx(">")
'      ser.tx(Ch)
      byte[@LastPar1][j]:=ch
      j++
      ser.str(@LastPar1)
      Ch:=sGetch           'skip next
 
  ser.str(string(" Par : " ))
  ser.str(@LastPar1)
  LPar:=ser.strtodec(@LastPar1)
  ser.tx("=")
  ser.dec(lPar)
  ser.tx(" ")
Return Lpar

' ---------------- Get next character from string ---------------------------------------
Pri sGetCh | lch 'Get next character from commandstring
   lch:=Byte[@StrBuf][StrP++]
   ser.tx("\")          
   ser.tx(lch)
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

' ----------------  Toggle reporting ---------------------------------------
PRI ToggleReport  
  !DoShowParameters

' ----------------  Clear errors of drives ---------------------------------------
PRI ClearErrors | i 
  repeat i from 0 to PID#PIDCnt-1
    Err[i]:=0
  ShowParameters  
 
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
  ResetFE
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
  PID.SetMaxCurr(0,3000)
  PID.SetInvert(0,-1,-1,1)  ' #pid, position, velocity, output
  
  PID.SetKi(1,800)
  PID.SetK(1,1000)
  PID.SetKp(1,1000)
  PID.SetIlimit(1,1000)
  PID.SetPosScale(1,1)
  PID.SetFeMax(1,200)
  PID.SetMaxCurr(1,3000)
  PID.SetInvert(0,-1,-1,1)  ' #pid, position, velocity, output

  PlatformID:=2001
  DirRamp:=10
  SpeedRamp:=1

' ----------------  Init main program ---------------------------------------
PRI InitMain
  dira[Led]~~                             'Set I/O pin for LED to output…
  !outa[Led]                              'Toggle I/O Pin for debug
  SerCog:=Ser.start(RXD, TXD, 0, Baud)     'Start serial:  start(pin, baud, lines)  ser.Clear
  t.Pause1ms(100)

  !outa[Led]                               'Toggle I/O Pin for debug
  ser.tx(ser#CS)
  t.Pause1ms(100)
  
  DoShowParameters:=true

'  ser.str(string("Tx and Rx pn settings: "))
'  ser.dec(dRxPin)
'  ser.Tx(" ")
'  ser.dec(dTxPin) 
'  ser.tx(CR)

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


'================================= Reports ============================================
' ----------------  Prepare most wanted datastrings in background ---------------------
PRI PrepareMotorReport | i   'Compose report string
    strs.EraseString(@StrPIDReport)  'Init report string
    
    strs.concatenate(@StrPIDReport,string("$97,"))
    strs.concatenate(@StrPIDReport,num.dec(PID.GetPIDCntr))
    strs.concatenate(@StrPIDReport,string(", "))

    repeat i from 0 to MotorIndex                       '2 encoders
      strs.concatenate(@StrPIDReport,num.dec(PID.GetEncPos(i)))
      strs.concatenate(@StrPIDReport,string(", "))
      
 '   strs.concatenate(@StrPIDReport,num.dec(MAEPos[0]))  '1 abs encoder
 '   strs.concatenate(@StrPIDReport,string(", "))   

    repeat i from 0 to MotorIndex                       '2 FE
      strs.concatenate(@StrPIDReport,num.dec(PID.GetFE(i)))
      strs.concatenate(@StrPIDReport,string(", "))

    strs.concatenate(@StrPIDReport,num.dec(pid.GetActVel(0)))   ' Wheel velocity 
    strs.concatenate(@StrPIDReport,string(", "))

    repeat i from 0 to MotorCnt-1       'Actual currents
      strs.concatenate(@StrPIDReport,num.dec(PID.GetActCurrent(i)))
      strs.concatenate(@StrPIDReport,string(", "))

    repeat i from 0 to MotorCnt-1       'Max currents
      strs.concatenate(@StrPIDReport,num.dec(PID.GetMaxCurrent(i)))
      strs.concatenate(@StrPIDReport,string(", "))      
  
    repeat i from 0 to MotorCnt-1       'PID loop status
      strs.concatenate(@StrPIDReport,num.dec(PID.GetPIDMode(i)))
      strs.concatenate(@StrPIDReport,string(", "))      
  
    repeat i from 0 to MotorCnt-1       'FE Status
      strs.concatenate(@StrPIDReport,num.dec(PID.GetFETrip(i)))
      strs.concatenate(@StrPIDReport,string(", "))

                                         'QiK-error
    strs.concatenate(@StrPIDReport,num.dec(PID.GetError(i)))
    strs.concatenate(@StrPIDReport,string(", "))

    strs.concatenate(@StrPIDReport,num.dec(pid.GetPIDLeadTime))     ' Loop time      
    strs.concatenate(@StrPIDReport,string(", "))

    strs.concatenate(@StrPIDReport,num.dec(SafetyCntr))         ' SafetyCntr      
    strs.concatenate(@StrPIDReport,string(", "))

    strs.concatenate(@StrPIDReport,string("#",CR))  
'    repeat while BlockSemaphore  '' Wait until release
'    BlockSemaphore:=true
 '   ByteMove(@StrPIDReport,@cStrPIDReport,lMaxStr)
'    BlockSemaphore:=false

' ---------------- Send program status to PC ---------------------------------------
PRI DoStatus2PC
  strs.EraseString(@StrMiscReport)  'Init report string
  strs.concatenate(@StrMiscReport,string("$99,"))

  strs.concatenate(@StrMiscReport,num.dec(PfStatus))
  strs.concatenate(@StrMiscReport,string(", "))

  strs.concatenate(@StrMiscReport,num.dec(SafetyTimeout))
  strs.concatenate(@StrMiscReport,string(", "))
  strs.concatenate(@StrMiscReport,num.dec(SafetyTimerEnable))
  strs.concatenate(@StrMiscReport,string(", "))

  strs.concatenate(@StrMiscReport,string("#",CR))

  
' ---------------- Send PID parameters to PC ---------------------------------------
PRI DoPID2PC | i
  strs.EraseString(@StrMiscReport)  'Init report string
  strs.concatenate(@StrMiscReport,string("$98,"))

  repeat i from 0 to MotorCnt-1       'Max currents
    strs.concatenate(@StrMiscReport,num.dec(PID.GetKi(i) ))   '#0
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetK(i) ))    '#1
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetKp(i) ))   '#2
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetIlimit(i) ))  '#3
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetPosScale(i) ))  '#4
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetVelScale(i) ))  '#5
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetFeMax(i) ))     '#6
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetMaxVel(i) ))    '#7
    strs.concatenate(@StrMiscReport,string(", "))
    strs.concatenate(@StrMiscReport,num.dec(PID.GetMaxSetCurrent(i) ))  '#8
    strs.concatenate(@StrMiscReport,string(", "))

'  strs.concatenate(@StrMiscReport,num.dec(PID.GetMAEOffset(0) ))        '#9
   strs.concatenate(@StrMiscReport,string(", "))

  strs.concatenate(@StrMiscReport,string("#",CR))
                                                     
   
   
'' ################## Old report  #######################################
' ----------------  Show PID parameters ---------------------------------------
PRI ShowParameters | i
  ser.Position(0,pControlPars)
  ser.str(string("{ "))
  ser.str(@Version)
  ser.tx(CR)
  ser.str(string("$PlatformID= "))
  ser.dec(PlatformID)
  ser.str(string("$PID Cycle Time (ms)= "))
  ser.dec(PIDCTime)
  
  ser.str(string(CR,"$SerialCog= "))
  ser.dec(SerCog)
  ser.str(string(" $PWM Cog= "))
  ser.dec(PWMCog)
  ser.str(string(" $EncoderCog= "))
  ser.dec(PID.GetEncCog)
  ser.str(string(" $PIDCog= "))
  ser.dec(PIDCog)
  ser.str(string(" $QiKCog= "))
  ser.dec(PID.GetQIKCog)


  ser.str(string(" $CMDProcCog= "))
  ser.dec(CMDProcCog)

  
  ser.str(string( " $nPIDloops= "))
  ser.dec(MotorCnt)

  ser.str(string(CR,"$KI= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(PID.getKI(i),6))
    ser.tx(",")
  ser.str(string(CR,"$K= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(PID.getK(i),6))
    ser.tx(",")
  ser.str(string(CR,"$Kp= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(PID.getKp(i),6))
    ser.tx(",")
  ser.str(string(CR,"$PosScale= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(pid.GetPosScale(i),6))
    ser.tx(",")
  ser.str(string(CR,"$Ilimit= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(pid.GetIlimit(i),6))
    ser.tx(",")

  ser.str(string(CR,"$PIDMode= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(PID.GetPIDMode(i),6))
    ser.tx(",")

  ser.str(string(CR,"$FElimit= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(PID.GetFEMax(i),6))
    ser.tx(",")

  ser.str(string(CR,"$CurrLim= "))
  repeat i from 0 to MotorIndex
    ser.str(num.decf(PID.GetMaxSetCurrent(i),6))
    ser.tx(",")

' ----------------  Clear input area ---------------------------------------
PRI ClearInputArea  | i
  ser.Position(0,pInput)
  ser.tx(">")                              
  repeat i from 0 to 5
    ser.str(string("                                                                 "))
    ser.tx(CE)
    ser.tx(CR)

' ----------------  Show actual value screen ---------------------------------------
PRI ShowScreen | i, CurrentError

    ser.Position(0,pActualPars)                      'Show actual values PID

    ser.str(string(CR,"$Setp= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(Setp[i],6))
      ser.tx(",")

    ser.str(string(CR,"$ActPos= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetActPos(i),6))
      ser.tx(",")

    ser.str(string(CR,"$Vel= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetActVel(i),6))
      ser.tx(",")
    ser.str(string(CR,"$DeltaVel= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetDeltaVel(i),6))
      ser.tx(",")
    ser.str(string(CR,"$MSetVel= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetSetVel(i),6))
      ser.tx(",")
    ser.str(string(CR,"$Ibuf= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetIbuf(i),6))
      ser.tx(",")
    ser.str(string(CR,"$PIDOut= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetPIDOut(i),6))
      ser.tx(",")
    ser.str(string(CR,"$Current= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetActCurrent(i),6))
      ser.tx(",")
    ser.str(string(CR,"$DriveErr=  "))
    repeat i from 0 to MotorIndex
      ser.hex(Err[0],2)
      ser.str(string("   | "))
    ser.str(string(CR,"$MaxCurr= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetMaxCurrent(i),6))
      ser.str(string(","))
    ser.str(string(CR,"$Fe= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetFE(i),6))
      ser.str(string(","))

    ser.str(string(CR,"$FeTrip= "))
    repeat i from 0 to MotorIndex
      ser.str(num.decf(PID.GetFETrip(i),6))
      ser.str(string(","))
    ser.str(num.decf(PID.GetFEAnyTrip,6))
    ser.str(string(CR,"$CurTrip= "))
    repeat i from 0 to MotorIndex
      CurrentError:=PID.GetCurrError(i)
      if CurrentError                                   'Disable platform moves when current error
        DisableMove
      ser.str(num.decf(CurrentError,6))
      ser.str(string(","))
    ser.str(num.decf(PID.GetAnyCurrError,6))
      
    ser.str(string(CR,CR,"$PIDTime= "))
    ser.dec(PID.GetPIDTime)
    ser.str(string(" $PIDIntrTime= "))
    ser.dec(PID.GetPIDLeadTime)
    ser.str(string(" $Main loop Time (ms)= "))
    ser.dec(MainTime)

    
    ser.tx(ser#CE)
    ser.str(string(" $Enabled= "))
    ser.dec(Enabled)
    ser.str(string(" $WheelsEnabled= "))
    ser.dec(WheelsEnabled)

    
    ser.str(string(" $PIDCntr= "))
    ser.dec(PID.GetPIDCntr)

    ser.tx(CE)
    ser.tx(" ")
    ser.str(string(CR,"$PlatfSpeed= "))
    ser.str(num.decf(MoveSpeed,4))
    ser.str(string(" $Dir= "))
    ser.str(num.decf(MoveDir,4))
    ser.str(string(" $Mode= "))
    ser.str(num.decf(MoveMode,4))
    ser.str(string(" $PfStatus= "))
    ser.str(num.dec(PfStatus))

    ser.str(string(CR,"$DebugCntr= "))
    ser.str(num.decf(DebugCntr,4))

    ser.str(string(" $PcComActive= "))
    ser.str(num.decf(PcComActive,4))
    

''     ser.tx(CR)
    ser.str(string(CR,"$Cmd= ",CE))
    ser.dec(StrCnt)
    ser.tx(" ")
    ser.str(@StrBuf)
    ser.str(string(CR,"$XStat= "))
    ser.dec(XStat)
    ser.str(string(" $XbeeCmdCntr= "))
    ser.dec(XbeeCmdCntr)
    ser.str(string(" $Sender= "))
    ser.dec(Sender)
'    ser.tx("}")
    ser.tx(CE)


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