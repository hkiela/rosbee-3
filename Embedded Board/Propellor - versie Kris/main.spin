{{
  Entry point for the Rosbee II Parallax control board.

  This is the cog which communicates with the on board notebook with ROS, using the standard protocol for serial communication.
  See http://lectoraatmechatronica.wikispaces.com/file/view/Serieel%20protocol%20voor%20robotica%20r1.2.pdf/381442566/Serieel%20protocol%20voor%20robotica%20r1.2.pdf
  (in Dutch, will be translated soon)
  This implementation uses a subset of available commands of the protocol. The messages implemented are:
  '$0\r' -> halt robot
  '$1\r' -> start robot
  '$2,vx,rot\r', ie '$2,100,-100\r' -> Turn / move robot with specified values vx and rot.

  vx is the forward velocity, in mm/s.
  rot is the rotational speed in mrad/s.

  This implementation should echo the current values using the same protocol (to be implemented).

  Heartbeat / watchdog timer: tbd.

  Reversions:
  0.1: DV - basic implementation, without watchdog or command echos.

  License: MIT (see included LICENSE file) 


}}
CON
  ' clock settings
  _clkmode=xtal1+pll16x
  _xinfreq = 5000000 
        
  Led = 27

  'Time related Constants
  CLK_FREQ = ((_clkmode-xtal1)>>6)*_xinfreq
  MS_001 = CLK_FREQ / 1_000
  US_001 = CLK_FREQ / 1
          
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

  '' Serial port 
   CR = 13                      
   LF = 10
   CE = 11                 'CE: Clear to End of line
   TXD = 30
   RXD = 31
   Baud = 115200 '256000 '115200 '250000 '1000000 '115200 '230400 '115200
  
   ' Misc characters
   ST = 36 'dollar sign
   SEP = 44 'comma, used to seperate command params.
   MINUS = 45 'minus
   DOT = 46 'dot

   SERIAL_MESSAGE_MAX_LENGTH = 64

   
   WHEEL_BASE_WIDTH = 0.368
   MM_PER_S_TO_CNTS_PER_PIDCYCLE = 20.00
   COUNTS_PER_ROTATION =  1856
   COUNTS_PER_MM = 4.803115031
   MM_PER_COUNT = 0.20819822
   WHEEL_CIRCUMFERENCE = 123.0 * PI 'MM

   
   FilterCnt = 50
   
   DEBUG = 0 'Debug flag for additional spam on the serial terminal.
   REPORT = 0 'Flag to enable or disable reporting setPL setPR actVL actVR
  
OBJ
  t             : "Timing"
  PID           : "PID Connect V5_3"             ' PID contr. 4 loops. for wheels
  num           : "simple_numbers"                      ' Number to string conversion
  serial        : "FullDuplexSerial_rr005"              ' PC command and debug interface
  STRs          : "STRINGS2hk"
  F32           : "F32" ' float32 support 

var 
  Byte SerialCog ' Cog for serial communication
  Byte SerialMSG[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the incoming string
  Byte SerialMSGOUT[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the outgoing string
  Byte ParserBuffer[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the parser
  Byte p ' Pointer to a position in the incoming string buffer
  Long error 'Error value, error is filled if there are problems with reading / parsing the message. If the error = 0,
             'was parsed succesfully.          
  
  Byte PIDCog 'Cog for the PID control system
  Byte QiKCog 'Cog for the QIK motor drivers
  Byte F32cog ''cog for floating point calculations
    
  Long Setp[MotorCnt] 'Shared with the PID cog, contais the setpoint for each motor.
  Long enco[MotorCnt] 'stores the current motor count

  Long velTH[FilterCnt] 'Moving average array for rotation velocity values
  Long velX[FilterCnt]  'Moving average array for forward velocity values
  Byte FilterIDX        'Index for Average Filter
  
  Long actVelMMS 'Long used to store actual speed in mm/s for feedback over serial
  Long actVelRadS 'Long used to store actual rotation speed in mrad/s for feedback over serial 

  Long maincnt 'Long to store main loopcnt

  Long oldTime[MotorCnt] 'Stores times for velocity calculation 
  

pub main | i
  {{
    Entry point for this system. Starts the serial, PID and floating point cogs.

    This method will continuously call handleSerial 
    Parameters:
      none
    Returns: none and never.

  }} 
  SerialCog:=serial.start(RXD, TXD, 0, Baud)
  F32cog:=f32.start
  
  'serial.str(string("Starting..."))
  'serial.tx(13) 
  'serial.tx(10)
  PIDCog:=PID.Start(PIDCTime, @Setp,  Enc0Pin, EncCnt, TxQ, RxQ, nPIDLoops) 'thr4, 5 and 6
  pid.setallpidmode(1) '' 1 = velocity control
  repeat while PID.GetPIDStatus<>2                      'Wait while PID initializes

  SetPIDPars
  waitcnt(500_000_000+cnt) ''Wait a few seconds for the powersupply to stabelize. 
  'setp[0] :=0
  'setp[1] :=0
  maincnt :=0
  FilterIDX :=0
  
  Repeat i from 0 to (MotorCnt - 1)
    setp[i]    :=0
    oldTime[i] :=0
    enco[i] := PID.GetActPos(i)

  repeat i from 0 to (FilterCnt - 1)
    velTH[i] := 0
    velX[i]  := 0
  
  'PID.BrakeWheels(50)
  
  'serial.str(string("Now accepting commands..."))
  'serial.tx(13) 
  'serial.tx(10)
  repeat
    'if serial.rxavail == true
    'T0 := cnt
      handleSerial
    'Serial.Dec(elapsedms(T0))
    'Serial.tx(13)
    'calculateActVelocity
    'sendResponse
    Serial.tx(10)
    'maincnt++
    'sendResponse
  



  
pri move(vx, rot) | setpL, setpR
  {{
    Move the platform with the given vx and rotation.
    This calculates the setpoints for each wheel and sets it to the setp array for the PID cog. The PID cog then uses this for the platform control 

    Parameters:
      vx: vertical velocity (mm/s)
      rot: rotational velocity  (mrad/s)
    Returns: none

    Modifies:
      Setp: the setpoint is set according to the vx and rot

    If DEBUG is set, this will also send debug information to the serial terminal. 

    Possible pitfall is concurrency on the setp array, where the PID cog might read one fresh value and one old value
    as there is no proper way to mark the array as synchronized / volatile without adding semaphores to this cog and the PID cog.
  }}
  if DEBUG
    Serial.str(string(" vx: "))
    Serial.dec(vx)
    Serial.str(string(" rot: "))
    Serial.dec(rot)

  ' left = round((vx + WHEEL_BASE_WIDTH/2 *rot)/MM_PER_S_TO_CNTS_PER_PIDCYCLE)
  ' right = round((vx - WHEEL_BASE_WIDTH/2 *rot)/MM_PER_S_TO_CNTS_PER_PIDCYCLE)
  
  setpL := f32.fround(f32.fdiv(f32.fadd(f32.ffloat(vx) , f32.fmul( f32.fdiv( constant(WHEEL_BASE_WIDTH), f32.ffloat(2)) , f32.ffloat(rot) )),MM_PER_S_TO_CNTS_PER_PIDCYCLE)) ' = round(500 - (wheel base width * 100))
  setpR := f32.fround(f32.fdiv(f32.fsub(f32.ffloat(vx) , f32.fmul( f32.fdiv( constant(WHEEL_BASE_WIDTH), f32.ffloat(2))  , f32.ffloat(rot) )),MM_PER_S_TO_CNTS_PER_PIDCYCLE))
  
  if setpL < 129 and setpL > -129 ' only update setpoints if the setpoint is in R{-128, 128}     
    setp[0] := setpL
  if setpR < 129 and setpR > -129  
    setp[1] := setpR * -1 ''Invert right wheel direction

  if DEBUG
    Serial.str(string(" Setpl: "))
    Serial.dec(setp[0])
    Serial.str(string(" Stepr: "))
    Serial.dec(setp[1])
    Serial.str(string(13," Error: "))
    Serial.dec(error)
    serial.tx(13) 
    'serial.tx(10)
                                

PRI handleSerial | val, i, j, messageComplete
  {{
    Reads the serial message transmitted and parses this message.
    Depending on the message, this function will call 'move' to move the platform.

    This also sends back the appropriate message according to the protocol. 

    Parameters: none

    Returns: none

    Modifies:
      error: (2<<1) will be added to error if the message buffer is full and no termination char was found

     If DEBUG is set, this will also send debug information to the serial terminal.
    
    Todo:
      Add a proper return message for the '2' type with current speeds.
      Add support for error transmission back to the control computer.
      Check if the wordfill works correctly.
  }}

'  returnActualVelocity
  
  if REPORT
    Serial.str(string(" SetpR: "))
    Serial.dec(setp[0])
    Serial.str(string(" StepL: "))
    Serial.dec(setp[1])    
    Serial.str(string(" ActVR: "))
    Serial.dec(PID.GetActVel(0))                             
    Serial.str(string(" ActVL: "))
    Serial.dec(PID.GetActVel(1))
    Serial.str(string(" EncPosR: "))
    Serial.dec(PID.GetEncPos(0))                        'GetEncPos
    Serial.str(string(" EncPosL: "))
    Serial.dec(PID.GetEncPos(1))
    Serial.str(string(" DVelR: "))
    Serial.dec(PID.GetDeltaVel(0))                      'GetDeltaVel
    Serial.str(string(" DVelL: "))
    Serial.dec(PID.GetDeltaVel(1))
    Serial.str(string(" VScaleR: "))
    Serial.dec(PID.GetVelScale(0))                      'GetVelScale(i)
    Serial.str(string(" VScaleL: "))
    Serial.dec(PID.GetVelScale(1))
    serial.tx(13) 
    'serial.tx(10)
                                                              
  serial.rxflush
  
  bytefill(@SerialMSG,0,SERIAL_MESSAGE_MAX_LENGTH) ''empty SerialMSG     
  '!outa[LED]
  i := 0 ' iterator counter for filling SerialMSG
  j := 0  'iterator for sending back te contents of SerialMSG
  error:=0 'resets the error value to 0, as this is a new serial message 
  messageComplete := false
  repeat until serial.rx == ST 'Busy wait until a '$' has been received
  repeat until messageComplete 'Busy wait until a termination char has received or an error has occurred   
    val := serial.rx
    if (val == CR)
      messageComplete := true
      error := 0
    if(i == SERIAL_MESSAGE_MAX_LENGTH and not messageComplete)' message buffer full and no termination char found.
      messageComplete := true
      error |= (2 << 0)
    SerialMSG[i] := val
    
    i++
  ''SerialMSG[i+1] := 0 ''String afsluiten  
  '!outa[LED]  

  if(DEBUG)
    repeat until i == j ''echo Serial MSG
      serial.tx(SerialMSG[j])
      j++
    serial.tx(10)
          
  if(error == 0)
    case SerialMSG[0] ' 0 is the first character after the '$' in the message.
      "0":  'halt robot
        serial.str(string("$0 "))
        'serial.tx(13) 
        'serial.tx(10)
                                                                                                                       '<-------26-04-2013
        move(0,0)
      "1":  'start robot
        serial.str(string("$1 "))
        'serial.tx(13) 
        'serial.tx(10)
        '' enable wheels / todo                        
      "2":
        'serial.str(string("$2")) ''This requires further string parsing.
                                                                                                              '<-------26-04-2013  
        sendResponse
        'calculateActVelocity
        parseParam
        'serial.tx(10)       
     
      "3":  'get error from Qik
        serial.str(string("$3 "))
        serial.dec(pid.geterror(0))
        serial.str(string(" "))
        'serial.tx(13) 
        'serial.tx(10)

      other:
        'serial.str(string("Unexpected message. Halting."))
        'serial.tx(13) 
        'serial.tx(10)
        '' disableWheels //todo
    'sendResponse

  else
    serial.str(string("Error with errno: "))
    serial.dec(error)
    serial.tx(13) 
    serial.tx(10)
         
PRI parseParam | vx, vy, rot
  {{
    Parses the parameters from the serial message.
    The rotational and vertical velocity are sent to the move method for to move the platform

    Parameters: none
    Returns: none

    Modifies:
      p: the pointer within the parser
      error: adds a value if an error is found while parsing.

    Todo:
      Move 'p' as a global variable to within this function and pass it to parseNumber.      
  }}
  vx := 0
  vy := 0   
  rot := 0
  p := 1  'pointer within the parser. The first (=0) character is the type of the message and has already been used by handleSerial.
          'The second (=1) char is the beginning of the message left to parse.  
  if(serialMSG[p] == SEP)
    p++
    vx := parseNumber(SEP)
    if(serialMSG[p] == SEP)
      p++
      vy := parseNumber(SEP)
      if(serialMSG[p] == SEP)
        p++
        rot := parseNumber(CR)
      else
        error |= (2 << 1)      
    else
      error |= (2<<2)
  else
    error|= (2 << 3)

  if(error == 0)
    move(vx,rot)
  else
    move(0,0)
    if(DEBUG)
      serial.str(string("Error encountered, halting..."))
      serial.str(string("Errno: "))
      serial.dec(error)
      serial.tx(13) 
      serial.tx(10)     
PRI parseNumber(term) : value | n, i, done, hasError
  {{
    Parses a number from the serialMSG, starting at index 'p' until the 'term' char has been found.
    Also stops parsing if the SERIAL_MAX_MESSAGE_LENGTH has been found

    Parameters:
      term: the termination char to end this number (ie. ',' or 'CR')
    Returns:
      value: the number of the parsed value
    Modifies:
      error: if an error occurd while parsing, the error value will be increased.
      p: the pointer will be increased until 'p' is at the same index as the 'term' char or in between if an error occurred. 
  }}
  value := 0 ''return value
  i := 0 ''pointer for internal array
  done := false
  hasError := false
  bytefill(@ParserBuffer,0,SERIAL_MESSAGE_MAX_LENGTH)
  
  repeat until done
    if (serialMSG[p] == term or serialMSG[p] == 0)
      done := true
    if (p == SERIAL_MESSAGE_MAX_LENGTH and not done)
      done := true
      hasError := true
      error |= (2<<4)
    if(not done)
      ParserBuffer[i] := serialMSG[p]
      i++
      p++
    

  if(not hasError)
    parserbuffer[++i] := 0  
    value := serial.strToDec(@ParserBuffer)   

  if(DEBUG)
    serial.str(string("Value: "))
    serial.dec(value)
    serial.tx(13) 
    serial.tx(10)    
  return value

PRI SetPIDPars
  {{
    Sets various PID parameters of the PID cog.
    Parameters: none
    Returns: none
    Modifies: none.
  }}
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

PRI updateMotorCnt
{{

}}
  

PRI sendResponse | i, totalX, totalTH, PIDpS, velL, velR, velMMS, velRADS
{{
    Return the actual velocity over serial to the controller PC

    ' left = round((vx - WHEEL_BASE_WIDTH/2 *rot)/MM_PER_S_TO_CNTS_PER_PIDCYCLE)
    ' right = round((vx + WHEEL_BASE_WIDTH/2 *rot)/MM_PER_S_TO_CNTS_PER_PIDCYCLE)
    
    setpL := f32.fround(f32.fdiv(f32.fadd(f32.ffloat(vx) , f32.fmul( f32.fdiv( constant(WHEEL_BASE_WIDTH), f32.ffloat(2)) , f32.ffloat(rot) )),MM_PER_S_TO_CNTS_PER_PIDCYCLE)) ' = round(500 - (wheel base width * 100))
    setpR := f32.fround(f32.fdiv(f32.fsub(f32.ffloat(vx) , f32.fmul( f32.fdiv( constant(WHEEL_BASE_WIDTH), f32.ffloat(2))  , f32.ffloat(rot) )),MM_PER_S_TO_CNTS_PER_PIDCYCLE))

    Long actVelMMS 'Long used to store actual speed in mm/s for feedback over serial
  Long actVelRadS 'Long used to store actual rotation speed in mrad/s for feedback over serial

            # distance traveled is the average of the two wheels 
            d = ( d_left + d_right ) / 2
            # this approximation works (in radians) for small angles
            th = ( d_right - d_left ) / self.base_width
            # calculate velocities
            self.dx = d / elapsed
            self.dr = th / elapsed




    TODO: ADD MAIN.SPIN SPIN TIME
          ADD MAIN.SPIN COUNTER



  Long velTH[FilterCnt] 'Moving average array for rotation velocity values
  Long velX[FilterCnt]  'Moving average array for forward velocity values
  Byte FilterIDX        'Index for Average Filter
  
}}

actVelMMS  := 0
actVelRadS := 0

actVelMMS  := f32.fround(f32.fdiv(f32.fmul(f32.fadd(f32.ffloat(PID.GetActVel(0)) ,f32.ffloat(-PID.GetActVel(1)) ),MM_PER_S_TO_CNTS_PER_PIDCYCLE), f32.ffloat(2)))
actVelRadS := f32.fround(f32.fdiv(f32.fmul(f32.fsub(f32.ffloat(PID.GetActVel(0)) ,f32.ffloat(-PID.GetActVel(1)) ),MM_PER_S_TO_CNTS_PER_PIDCYCLE),constant(WHEEL_BASE_WIDTH)))

PIDpS := 1000 / PIDCTime

velL :=  f32.fround(f32.fmul(f32.fmul(f32.ffloat(-PID.GetActVel(1)),f32.ffloat(PIDpS)),MM_PER_COUNT))
velR :=  f32.fround(f32.fmul(f32.fmul(f32.ffloat(PID.GetActVel(0)),f32.ffloat(PIDpS)),MM_PER_COUNT))


velMMS := (velL + velR) / 2
velRADS := f32.fround(f32.fdiv(f32.fsub(f32.fmul(f32.fmul(f32.ffloat(PID.GetActVel(0)),f32.ffloat(PIDpS)),MM_PER_COUNT),f32.fmul(f32.fmul(f32.ffloat(-PID.GetActVel(1)),f32.ffloat(PIDpS)),MM_PER_COUNT)), WHEEL_BASE_WIDTH))



'(counts*nr of pid cycle per s)*mm_per_count

{
velX[FilterIDX]  := f32.fround(f32.fdiv(f32.fmul(f32.fadd(f32.ffloat(PID.GetActVel(0)) ,f32.ffloat(-PID.GetActVel(1)) ),MM_PER_S_TO_CNTS_PER_PIDCYCLE), f32.ffloat(2)))
velTH[FilterIDX] := f32.fround(f32.fdiv(f32.fmul(f32.fsub(f32.ffloat(PID.GetActVel(0)) ,f32.ffloat(-PID.GetActVel(1)) ),MM_PER_S_TO_CNTS_PER_PIDCYCLE),constant(WHEEL_BASE_WIDTH)))

Repeat i from 0 to (FilterCnt - 1) 
  totalX += velX[i]
  totalTH += velTH[i]

actVelMMS := totalX/FilterCnt
actVelRadS := totalTH/FilterCnt

if (++FilterIDX == FilterCnt)
  FilterIDX := 0

}

'actVelMMS := (actVelMMS * 104) /100
'actVelRadS := (actVelRadS *104) /100 

'debug
'Serial.str(string("actvelmms, actvelrads, velmms, velrads: "))
'Serial.dec(actVelMMS)
'Serial.str(string(", "))
'Serial.dec(actVelRadS)
'Serial.str(string(", "))
'Serial.dec(velMMS)
'Serial.str(string(", "))
'Serial.dec(velRADS)



'real  
Serial.str(string("$2,"))
Serial.dec(actvelMMS)
Serial.str(string(",0,"))
Serial.dec(actvelRADS)
'Serial.str(string(", "))
'Serial.dec(PID.GetPIDCntr)
'Serial.str(string(","))
'Serial.dec(PID.GetError(0))
'Serial.str(string(","))
'Serial.dec(PID.GetCurrError(0))
'Serial.str(string(","))
'Serial.dec(PID.GetCurrError(1))
'Serial.str(string(","))
'Serial.dec(PID.GetPIDTime)
'Serial.str(string(","))
'Serial.dec(PID.GetActPos(0))
'Serial.str(string(","))
'Serial.dec(PID.GetActPos(1))
'Serial.str(string(","))
'Serial.dec(PID.GetActCurrent(0))
'Serial.str(string(","))
'Serial.dec(PID.GetActCurrent(1))
'Serial.str(string(", "))
'Serial.dec(maincnt)
'Serial.str(string(","))
'serial.tx(13) 
'serial.tx(10)

PRI calculateVelocity | i, velLeft, velRight
  {
            # distance traveled is the average of the two wheels 
            d = ( d_left + d_right ) / 2
            # this approximation works (in radians) for small angles
            th = ( d_right - d_left ) / self.base_width
            # calculate velocities
            self.dx = d / elapsed
            self.dr = th / elapsed
  
  
  
  velLeft := f32.fround(f32.fmul(f32.fdiv(f32.fdiv(f32.fsub(f32.ffloat(PID.GetActPos(1)), f32.ffloat(enco[1])),constant(COUNTS_PER_MM)), f32.ffloat(elapsedms(oldtime[1]))),f32.ffloat(1000))) 
  velRight := f32.fround(f32.fmul(f32.fdiv(f32.fdiv(f32.fsub(f32.ffloat(PID.GetActPos(0)), f32.ffloat(enco[0])),constant(COUNTS_PER_MM)), f32.ffloat(elapsedms(oldtime[0]))),f32.ffloat(1000)))

  velLeft *= -1

  'DEBUG
  Serial.str(string("velLeft, velRight, encleft, encright: "))
  Serial.dec(velLeft)
  Serial.str(string(", "))
  Serial.dec(velRight)
  Serial.str(string(", "))
  Serial.dec(PID.GetActPos(1))
  Serial.str(string(", "))
  Serial.dec(PID.GetActPos(0))
  serial.tx(13)



  Repeat i from 0 to (MotorCnt - 1)
    oldTime[i] :=0
    enco[i] := PID.GetActPos(i)
  }

  

PRI elapsedms(tstart)

return ||(cnt - tstart) / MS_001

PRI elapsedus(tstart)

return ||(cnt - tstart) / US_001                                            