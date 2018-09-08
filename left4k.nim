import sdl2,  sdl2.image as image,  sdl2.mixer as mixer, sdl2.audio
import math, random, algorithm
import gltext

type  
  byte = char
  GameState = enum RESTART, RUNNING, GAMEOVER 

const 
  ScreenWidth = 1024
  ScreenHeight = 768
  TWOPI = 2.0 * PI

var
  offscreen:TexturePtr= nil
  pixels : array[ 240*240, int32 ]
  lightmap : array[ 240*240, int32 ]
  brightness : array[ 512, int32 ]
  Map  : array[ 1024*1024, int32 ]
  sprites  : array[ 18*4*16*12*12, int32 ]
  

type
  Entity = tuple[ x,y ,dir, health, under, dead, timer, d8, d3 : int32 ]
  GameData = tuple[score, hurtTime, bonusTime, xWin0, yWin0, xWin1, yWin1, level, shootDelay, 
                   rushTime , damage, ammo, clips, closestHitDist , closestHit: int32]

var
  entities : array[320, Entity]
  gameData : GameData
  xCam, yCam , tick: int32
  shoot_fx, reload_fx : ptr Chunk
 

gameData.rushTime= 150 
gameData.damage = 20
gameData.ammo = 20
gameData.clips = 20

var 
  myfont : Font = gltext.LoadFont("myfont.fnt")
  fontTarget : FontTarget

 
var
  mainWindow : WindowPtr
  renderer : RendererPtr
  evt = sdl2.defaultEvent
  running = true
  playSounds = true 
  gameState : GameState = GAMEOVER
  mouseX, mouseY : int32
  moveUp, moveDown, moveLeft, moveRight, doReload, clicked : bool = false ;



proc Cosine( degrees : int ) : float = cos( degToRad(degrees.float) )
proc Sine( degrees : int ) : float = sin( degToRad(degrees.float) )

proc fireGun(playerDir, C, S : float64);
  
proc getMap(  x, y : int ) : int32 =  
  result = Map[ (x and 1023) or ((y and 1023) shl 10) ]; 
  
proc setMap( x, y, v : int ) = 
  Map[ (x and 1023) or ( (y and 1023) shl 10 ) ] = int32(v); 

proc drawString(txt : string, x, y : int32) =
  discard # writeText( fontTarget, txt, x * ScreenWidth/240, y * ScreenHeight / 240 );


proc setLM( x,y : float, value: int  ) =
  lightMap[ int(x) + int(y) * 240 ] = int32(value)

proc setLM( x,y : int, value: int  ) =
  lightMap[ int(x) + int(y) * 240 ] = int32(value)
  
proc getLM( x,y : int ) : int32 = lightMap[ x + y * 240 ] 
  
proc getLM( x,y : float ) : int32 = lightMap[ int(x) + int(y) * 240 ] 
  
proc randFloat( a: int ): float32 = float32( random.rand( a ) )

proc randInt( a: int ): int32  = int32( random.rand( a ) )
  
proc Red( pixel : int32 ) : int = ( pixel shr 16 ) and 0xff
proc Green( pixel : int32 ) : int = ( pixel shr 8) and 0xff 
proc Blue( pixel : int32 ) : int = pixel and 0xff

proc Pixel( r, g, b : int ) : int32 = int32( min(b,0xff) or ( min(g,0xff) shl 8) or (min(r,0xff) shl 16) )


proc Setup() =
  system.zeroMem( pixels.addr, sizeof pixels);
  for n in countup( low(sprites), high(sprites) ): sprites[n] = 0
  #sprites[] = 0;
  
  let offs :float = 30.0;
  for i in countup(0,511):
    brightness[i] = int32(255.0 * offs / (float(i) + offs))
    if i < 4: 
      brightness[i] = int32(brightness[i] * i )div 4
  var pix = 0
  for i in countup(0,17):
    var 
      skin : int32 = 0xFF9993      # flesh color
      clothes : int32 = 0xffffff   # white clothes
    if i > 0:
      skin = 0xa0ff90    # green skin
      clothes = (randInt(0x1000000) and 0x7f7f7f)   # random clothes
    for t in countup(0,3): # frames of animation?
      for d in countup(0,15): # 16 directions
        var dir : float64 = d.float * PI * 2.0 / 16.0;
        case t 
          of 1: 
            dir += 0.5 * PI * 2 / 16
          of 3: 
            dir -= 0.5 * PI * 2 / 16
          else: 
            discard
        var 
          C = cos(dir)
          S = sin(dir)
        for y in countup(0,11):
          var col : int32 = 0x000000
          for x in countup( 0,11 ):
            var 
              xPix = int(C * float(x - 6) + S * float(y - 6) + 6.5)
              yPix = int(C * float(y - 6) - S * float(x - 6) + 6.5)

            if i == 17:
              if (xPix > 3 and xPix < 9 and yPix > 3 and yPix < 9):
                col = 0xff0000 and ((t.int32 and 1) * 0xff00);
            else:
              if (t == 1) and (xPix > 1) and (xPix < 4) and (yPix > 3) and (yPix < 8): 
                col = int32(skin);
              elif ((t == 3) and (xPix > 8) and (xPix < 11) and (yPix > 3) and (yPix < 8)):
                col = int32(skin);

              if ((xPix > 1) and (xPix < 11) and (yPix > 5) and (yPix < 8)):
                  col = clothes;
              elif ((xPix > 4) and (xPix < 8) and (yPix > 4) and (yPix < 8)):
                  col = skin;
            sprites[pix] = col;
            pix += 1
            col = (if col> 1: 1 else: 0);
        
proc Shutdown() = discard

proc findWall(x, y : int) : bool =
  for yy in countup(y-1,y+1):
    for xx in countup(x-1,x+1):
      if getMap(int32 xx,int32 yy)< 0xFF0000'i32:
        return true
  return false
  
  
proc WinLevel() =
  for n in countup( low(pixels), high(pixels) ): #memset( pixels, 0, sizeof pixels);
    pixels[n] = 0

  tick = 0;
  gameData.level += 1;  
  randomize(4329+gameData.level);  #srand( SDL_GetTicks() );

  for y in countup(0,1023):
    for x in countup(0,1023):
      var 
        br = randInt(32) + 112
        i = x + (y * 1024)
      Map[i] = int32( ((br div 3) shl 16)  or ((br) shl 8) )
      if (x < 4) or (y < 4) or (x >= 1020) or (y >= 1020):
        Map[i] = int32( 0xFFFEFE )

  # this makes 70 rooms in the level ?
  for i in countup(0,69):
    var 
      w = (randInt(8) + 2) 
      h = (randInt(8) + 2) 
      xm = (randInt(64 - w - 2) + 1) * 16
      ym = (randInt(64 - h - 2) + 1) * 16
      
    w = w * 16 + 5
    h = h * 16 + 5
      
    if i==68:  # number 68 is starting room
      entities[0].x = xm+w div 2;
      entities[0].y = ym+h div 2;
      entities[0].under = 0x808080;
      entities[0].health = 1;

    gameData.xWin0 = xm+5;
    gameData.yWin0 = ym+5;
    gameData.xWin1 = xm + w-5;
    gameData.yWin1 = ym + h-5;
    for y in countup(ym, ym+h-1):#(int y = ym; y < ym + h; y++)
      for x in countup(xm, xm+w-1): #(int x = xm; x < xm + w; x++)
        var d = x - xm;
        if xm + w - x - 1 < d: 
          d = xm + w - x - 1;
        if y - ym < d:
          d = y - ym;
        if ym + h - y - 1 < d:
          d = ym + h - y - 1;

        setMap(x, y, 0xFF8052) # this is the border of the walls
        if d > 4:
          var br = randInt(16) + 112
          if ((x + y) and 3) == 0:
              br += 16;
          setMap(x,y, Pixel( (br * 3 div 3) , (br * 4 div 4) ,(br * 4 div 4)) );
        if i == 69:
          setMap(x, y , getMap(x,y) and 0xff0000 );  # win room has a red floor

    # doorways
    for j in countup(0,1):
      var 
        xGap = randInt(w - 24) + xm + 5
        yGap = randInt(h - 24) + ym + 5
        ww = 5
        hh = 5

      xGap = xGap div 16 * 16 + 5;
      yGap = yGap div 16 * 16 + 5;
      if randInt(2) == 0:
        xGap = xm + (w - 5) * randInt(2)
        hh = 11
      else:
        ww = 11
        yGap = ym + (h - 5) * randInt(2)
      for y in countup( yGap, yGap+hh.int32-1):
        for x in countup( xGap, xGap+ww.int32-1): 
          var br = randInt(32) + 112 - 64;
          if (x+y) %% 3==0 : 
            br += 16;
          setMap(x,y, Pixel( (br * 3 div 3) , (br * 4 div 4) , (br * 4 div 4) ) );

  # set all walls to 0xFFFFFF
  for y in countup(1,1022):
    for x in countup(1,1022):
      if not findWall(x,y):
        setMap( x,y, 0xffffff )
  
        
        
proc updateLightmap( playerDir: float ) =
  for i in countup(0,959): # update visibility in 960 directions around player (240 pixels * 4 sides)
    var 
      xt = (i mod 240) - 120
      yt = (( i div 240 ) mod 2 ) * 239 - 120;

    if i >= 480:
      swap( xt, yt )
    
    var dd = arctan2(float(yt), float(xt)) - playerDir  # get angle of raycast
    if (dd < -PI):
      dd += TWOPI 
    elif (dd >=  PI):
      dd -= TWOPI 

    var 
      brr = int32((1 - dd * dd) * 255)
      dist = 120
      
    if brr < 0:
        brr = 0;
        dist = 32;
        
    if tick < 60: 
      brr = brr * tick  div 60;  # this makes light slowly increase first 2 seconds

    for j in countup(0,dist-1):
      var
        xx = xt * j div 120 + 120
        yy = yt * j div 120 + 120
        xm = xx + xCam - 120
        ym = yy + yCam - 120

      if getMap(xm,ym) == 0xffffff:  # hit a wall, stop expanding light
        break; 

      var 
        xd = (xx - 120) * 256 div 120
        yd = (yy - 120) * 256 div 120
        ddd = (xd * xd + yd * yd) div 256
        br = brightness[ddd] * brr div 255

      if ddd < 16:
        var tmp  = int32( 128 * (16 - ddd) div 16 )
        br = br + tmp * (255 - br) div 255
      setLM( xx, yy, br ) #      lightmap[xx + yy * 240] = br;
  
proc RestartGame() =
  gameData.level = 0;
  gameData.shootDelay = 0;
  gameData.rushTime=150;
  gameData.damage=20;
  gameData.ammo=20;
  gameData.clips=20;
  gameState = RUNNING;
  WinLevel();
  assert gameState==RUNNING


proc nextMonster( n : int, playerDir, C, S : float ) =
  var 
    e = entities[n].addr
    xPos = e.x
    yPos = e.y
   
  if e.health == 0: #respawn
    xPos = (randInt(62) + 1) * 16 + 8;
    yPos = (randInt(62) + 1) * 16 + 8;

    var 
      xd = xCam - xPos
      yd = yCam - yPos

    if (xd * xd + yd * yd) < (180 * 180):
      xPos = 1
      yPos = 1

    if (getMap(xPos ,yPos) < 0xfffffe ) and
        ((n <= 128) or (gameData.rushTime > 0) or ((n > 255) and (tick == 1))):
      e.x = xPos;
      e.y = yPos;
      e.under = getMap( xPos, yPos );
      setMap(xPos , yPos , 0xfffffe );
      e.timer = int32(if gameData.rushTime > 0: 1 else:0) or ( if randInt(3)==0: 127 else: 0 );
      e.health = 1;
      e.dir = n.int32 and 15;
    else:
      return
  else:
    var
      xd = xPos - xCam
      yd = yPos - yCam

    if n >= 255:
      if xd * xd + yd * yd < 8 * 8:
        setMap( xPos, yPos, e.under )
        e.health = 0;
        gameData.bonusTime = 120;
        if ((n and 1) == 0):
          gameData.damage = 20; # health
        else:
          gameData.clips = 20; # add clips
        return;
    elif (xd * xd + yd * yd > 340 * 340):
      setMap(xPos , yPos , e.under);
      e.health = 0;
      return;

  var 
    xm = xPos - xCam + 120
    ym = e.y - yCam + 120
    d = e.dir
  if n == 0:
    d = (((playerDir / (PI * 2) * 16 + 4.5 + 16)).int32 and 15);

  d += ((e.d3 div 4) and 3) * 16;

  var p = (0 * 16 + d) * 144;
  if n > 0:
    p += ((n and 15) + 1).int32 * 144 * 16 * 4;

  if n > 255:
    p = (17 * 4 * 16 + ((n and 1).int32 * 16 + (tick and 15))) * 144;

  # draw 12x12 sprite around xm, ym
  for y in countup( ym-6, ym+5):
    for x in countup( xm-6, xm+5):
      var c = sprites[p]
      p+=1
      if  (c > 0) and (x >= 0) and (y >= 0) and (x < 240) and (y < 240):
        pixels[x + y * 240] = c;

  var moved = false

  if e.dead > 0:
    e.health += randInt(3) + 1;
    e.dead = 0;
    var 
      rot = 0.25
      amount = 8
      poww = 32.float


    if e.health >= 2+gameData.level:
      rot = PI * 2
      amount = 60
      poww = 16
      setMap(xPos, yPos, 0xa00000 )
      e.health = 0
      gameData.score += gameData.level
    for  i in countup(0,amount-1):
      var 
        pow = float(randInt(100) * randInt(100)) * poww / 10000+4
        dir = float(randInt(100) - randInt(100)) / 100.0 * rot
        xdd = ( cos(playerDir + dir) * pow) + float(randInt(4) - randInt(4))
        ydd = ( sin(playerDir + dir) * pow) + float(randInt(4) - randInt(4))
        col = (randInt(128) + 120)
      for j in countup(2, int(pow-1)): #      for (int j = 2; j < pow; j++)
          var 
            xd = int( float(xPos) + xdd * (float(j) / pow))
            yd = int( float(yPos) + ydd * (float(j) / pow))
          if getMap(xd,yd) >= 0xff0000: 
            break;
          if randInt(2) != 0:
            setMap(xd,yd, col  shl 16  );  # blood splatters
    return

  var 
    xPlayerDist = xCam - xPos
    yPlayerDist = yCam - yPos
    yDist = float(yPlayerDist)
    xDist = float(xPlayerDist)

  if n <= 255:
    var       
      rx = -(C * xDist - S * yDist)
      ry = C * yDist + S * xDist

    if (rx > -6) and (rx < 6) and (ry > -6) and (ry < 6) and (n > 0) :
      gameData.damage+=1
      gameData.hurtTime += 20;
    if (rx > -32) and (rx < 220) and (ry > -32) and (ry < 32) and (randInt(10) == 0):
      e.timer+= 1;
    if (int(rx) > 0) and (int32(rx) < gameData.closestHitDist) and (ry > -8) and (ry < 8):
      gameData.closestHitDist = int32(rx);
      gameData.closestHit = int32(n)

    for i in countup(0,1):
      var
        xa,ya :int32 = 0
        xPos = e.x
        yPos = e.y

      if n == 0:
        if moveLeft: xa-=1
        if moveRight: xa+=1
        if moveUp: ya-=1
        if moveDown: ya+=1
      else:
        if e.timer < 8: 
          return;

        if e.d8 != 12:
          xPlayerDist = (e.d8) mod 5 - 2;
          yPlayerDist = (e.d8) div 5 - 2;
          if randInt(10) == 0:
            e.d8 = 12;

        var 
          xxd = sqrt( xDist * xDist) 
          yyd = sqrt( yDist * yDist )
        if (float(randInt(1024)) / 1024.0) < (yyd / xxd):
          if yPlayerDist < 0: 
            ya-=1
          if yPlayerDist > 0: 
            ya+=1
        if ( float(randInt(1024)) / 1024.0) < (xxd / yyd):
          if xPlayerDist < 0: 
            xa-=1;
          if xPlayerDist > 0: 
            xa+=1;

        moved = true;
        var dir = arctan2(yDist, xDist)
        e.dir = (((dir / (((PI * 2) * 16) + 4.5 + 16))).int32 and 15);

      ya *= i.int32;
      xa *= (1 - i).int32

      if (xa != 0 ) or (ya != 0):
        setMap(xPos, yPos, e.under )
        var moveIt = true
        for xx in countup( xPos+xa-3, xPos+xa+2):
          for yy in countup( yPos+ya-3, yPos+ya+2):
            if getMap(xx , yy) >= 0xfffffe:
              setMap(xPos ,yPos, 0xfffffe);
              e.d8 = randInt(25);
              moveIt = false
        if moveIt:
          moved = true;
          e.x += xa;
          e.y += ya;
          e.under = getMap(xPos + xa, yPos + ya );
          setMap(xPos+xa,yPos + ya,  0xfffffe);
        continue;
    if moved:
      e.d3+=1;
# end nextmonster

  

  
proc RunGame() =
  tick+=1
  gameData.rushTime+=1 
  if gameData.rushTime >= 150: 
    gameData.rushTime = -randInt(2000) 

  # Move player:
  var 
    playerDir = arctan2( float(mouseY - 120), float(mouseX - 120) )
    shootDir = (playerDir + float(randInt(100) - randInt(100)) / 100.0 * 0.2)
    C = cos(-shootDir)
    S = sin(-shootDir)

  xCam = entities[0].x
  yCam = entities[0].y

  updateLightmap(playerDir)

  # draw map/background into pixels from map[]?
  for y in countup(0,239): 
      var 
        xm = xCam - 120
        ym = y + yCam - 120
      for x in countup(0,239):
        pixels[x + y * 240] = getMap(xm + x ,  ym ) ;


  # closest Hit of raycast
  gameData.closestHitDist = 0;
  for j in countup(0,249):
    var 
      xm = xCam + int(C * float(j div 2))
      ym = yCam - int(S * float(j div 2))
    if getMap(xm , ym ) == 0xffffff: 
      break; # hit wall, stop cast
    gameData.closestHitDist = int32(j div 2)
  # closestHit = monster number closest to player, updated in nextMonster
  gameData.closestHit = 0;

  for m in countup(0,255+16):
    nextMonster(m, playerDir,C, S);

  gameData.shootDelay-=1
  var shoot : bool = (gameData.shootDelay<0) and clicked

  if shoot:
    fireGun(playerDir, C, S)
    if playSounds:
      let ch = playChannel(-1,shoot_fx, 0);
      if ch<0: 
        discard # echo("Error playing shoot sound!\n")
      else: 
        discard volume(ch, 16);


  if gameData.damage >= 220:
    clicked = false;
    gameData.hurtTime = 255;
    tick =0;
    gameState=GAMEOVER;
  elif (doReload and gameData.ammo > 20 and gameData.clips < 220):
    gameData.shootDelay = 30;
    gameData.ammo = 20;
    gameData.clips += 10;
    if playSounds :
      var ch = playChannel(-1, reload_fx, 0)
      if ch<0 :
        discard # echo("Error playing reload sound!\n")
      else: 
        discard volume(ch, 16);
  elif ((xCam > gameData.xWin0 ) and (xCam < gameData.xWin1) and (yCam > gameData.yWin0) and (yCam < gameData.yWin1)):
     WinLevel();
  
  
proc UpdateScreen() =
  gameData.bonusTime = int32(gameData.bonusTime * 8 div 9);
  gameData.hurtTime = gameData.hurtTime shr 1;
  
  for y in countup(0,239):
    for x in countup(0,239):
      var noise = if gameState==RUNNING: 0 else: randInt(16) * 4 
      let 
        c = pixels[ x + y * 240] 
        lum = getLM(x,y)
      setLM( x, y, 0 );
      var 
        r = ( Red(c) * lum) div 255 + noise
        g = ( Green(c) * lum ) div 255 + noise
        b = ( Blue(c) * lum ) div 255 + noise

      r = (r * (255 - gameData.hurtTime) div 255 ) + gameData.hurtTime;
      g = (g * (255 - gameData.bonusTime) div 255) + gameData.bonusTime;
      pixels[x + y * 240] = Pixel(r,g,b) ;
    if ((y mod 2 == 0) and (y >= gameData.damage) and (y < 220)):
      for x in countup(232,237):
        pixels[y * 240 + x] = 0x800000; #health bar
    if (y mod 2 == 0 and (y >= gameData.ammo and y < 220)):
      for x in countup(224,229):
        pixels[y * 240 + x] = (0x808000)  # ammo bar
    if (y mod 10 < 9 and (y >= gameData.clips and y < 220)):
      for x in countup( 221, 222 ):
        pixels[y * 240 + 221] = (0xffff00); # clips bar

    
proc UpdateGame() =
  if gameState==GAMEOVER:
    tick+=1
    drawString("Left 4k Dead", 10, 50 )
    if tick>60 and clicked:
      RestartGame()
  elif gameState==RUNNING:
    RunGame()
    if tick < 60:
      drawString("Level " & $gameData.level, 90, 70);
      drawString( "Press F1 to disable sounds", 150, 190 );
      drawString( "Press F10 to quit", 150, 200  );
    else:
      drawString("%d" & $gameData.score, 4,228);
      
  UpdateScreen()
    
    
proc UserInput() =
  var event  = sdl2.defaultEvent
  while pollEvent(event):  
    var kind : EventType = event.kind
    let pressed = kind==KeyDown
    if kind==QuitEvent:
      running = false;
    elif kind==KeyDown or kind==KeyUp:
      case event.key.keysym.sym
      of K_a:
        moveLeft = pressed
      of K_d: 
        moveRight = pressed
      of K_w: 
        moveUp = pressed;
      of K_s: 
        moveDown = pressed
      of K_r: 
        doReload = pressed
      of K_F1: 
        if pressed :
          playSounds= not playSounds;
      of K_F10: 
        running = false;
      else:
        discard ""
    elif kind==MouseButtonDown or kind==MouseButtonUp:
      clicked = event.button.button == ButtonLeft and kind==MouseButtonDown
    elif kind==MouseMotion:
      mouseX = int32(event.motion.x * 240 div ScreenWidth)
      mouseY = int32(event.motion.y * 240 div ScreenHeight)
    else:
      continue
   

    
proc findClosestHit( C, S : float ) : tuple[xp, yp: int ] =
  let dist = float(gameData.closestHit)
  result = ( 120 + int( C * dist ), 120 - int( -S * dist ) )
    
proc fireGun(playerDir, C, S : float64) =
  if gameData.ammo >= 220:
    gameData.shootDelay = 2;
    clicked = false;
  else:
    gameData.shootDelay = 1;
    gameData.ammo += 4;

  # monster hit then kill it
  if gameData.closestHit > 0:
    entities[gameData.closestHit].dead = 1;
    entities[gameData.closestHit].timer = 127;

  # this section draws the bullets ?
  var glow = 0
  for j in countdown(gameData.closestHitDist,0) :#(int j = closestHitDist; j >= 0; j--)
    let 
      xm = min( 239, float(C * float(j)) + float(120) )
      ym = min( 239, -float(S * float(j)) + float(120) )
    let
      isum = int(xm+(ym * 240))
    if (xm > 0) and (ym > 0) and (xm < 240) and (ym < 240):
      if (randInt(20) == 0) or (j == gameData.closestHitDist):
        pixels[isum] = int32(0xffffff);  # 'tracer' type bullets
        glow = 200;             # glow near impact
      setLM( xm, ym, (glow * (255 - lightmap[isum]) / 255).int32 ) ; #lightmap[isum] += int32(glow * (255 - lightmap[isum]) / 255);
    glow = int(glow * 20 / 21)

  if gameData.closestHitDist < 120:  # is the closest hit within the viewable area?
    gameData.closestHitDist -= 3
    let (xx,yy) = findClosestHit(C,S);
    
    # let xx = uint(120 + C * gameData.closestHitDist)
    # let yy = uint(120 - S * gameData.closestHitDist)
    # for (int x = -12; x <= 12; x++)d
    for x in countup( -12, 12):    # sparks/light near bullet impact
      for y in countup( -12, 12 ):    #for (int y = -12; y <= 12; y++)
        let xd = xx + x;
        let yd = yy + y;
        if (xd >= 0 and yd >= 0 and xd < 240 and yd < 240):
          let value = int32(2000 / (x * x + y * y + 10)) * int32( (255 - getLM(xd ,yd ) ) / 255)
          setLM( xd, yd, getLM(xd,yd) + value )
           #lightmap[xd + yd * 240] += 2000 / (x * x + y * y + 10) * (255 - lightmap[xd + yd * 240]) / 255;

    for i in countup(0,9): #    for (int i = 0; i < 10; i++)
      let pow :float64 = randFloat(100) * randFloat(100) * (8.float / 10000.float);
      let dir : float64 = float32(randInt(100) - randInt(100)) / 100.0
      let xd :int = int(float(xx) - cos(playerDir + dir) * pow) + randInt(4) - randInt(4)
      let yd :int = int(float(yy) - sin(playerDir + dir) * pow) + randInt(4) - randInt(4)
      if (xd >= 0) and (yd >= 0) and (xd < 240) and (yd < 240):
          if gameData.closestHit > 0:
            setLM( xd, yd, 0xff0000 )          # red
            #lightmap[xd + yd * 240] = (0xff0000)  
          else:
              #//lightmap[xd + yd * 240] = 0xcacaca;  // light gray
              setLM( xd, yd, 0xeaeaea)  # light gray
              #lightmap[xd + yd * 240] = 0xeaeaea;  
  
  
#  ----------------- Main Starts here -------------------------------

discard sdl2.init(INIT_VIDEO or INIT_AUDIO)
discard image.init(image.IMG_INIT_PNG); #initialize SDL_image

discard mixer.init( cast[cint](mixer.MIX_INIT_FLAC) )

FlushEvent(ord KeyDown)
FlushEvent(ord MouseButtonDown)
FlushEvent(ord MouseMotion)

# this is commented out in sdl2 ??
const  MIX_DEFAULT_FORMAT* = AUDIO_S16
  
if openAudio(mixer.MIX_DEFAULT_FREQUENCY,MIX_DEFAULT_FORMAT, 2, 1024)!=0:
  echo("Error initializing audio channels!\n")
  quit(-3)


shoot_fx = loadWAV("shoot.wav")
reload_fx = loadWAV("reload.wav")
mainWindow = createWindow("Left4kDead", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, ScreenWidth, ScreenHeight,
                              SDL_WINDOW_SHOWN or SDL_WINDOW_INPUT_GRABBED  );
renderer = createRenderer(mainWindow, -1, 0);
offscreen = createTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, 240, 240 );

myfont = LoadFont("myfont.fnt");
#fontTarget = CreateFontTarget(myfont, renderer, ScreenWidth, ScreenHeight);  
Setup();

var 
  frames :uint32 = 0
  start = getTicks()
  frameTicks  = uint32(1000 / 30) # 30 fps
  nextFrame = getTicks() + frameTicks

 
while running:
  let t = getTicks();
  if t < nextFrame :
    delay( nextFrame - t );
    continue;

  # if ( nextFrame + frameTicks ) < t : # framerate is dropping below 30 fps
  #     nextFrame+= frameTicks          
  #     UpdateGame()
  #     echo("Skip")
  #     continue                        # skip rendering a frame

  nextFrame += frameTicks
  UserInput()
  UpdateGame()
  updateTexture( offscreen, nil, addr pixels, 240*sizeof(int32) );
  renderer.copy( offscreen, nil, nil);
  #BlitFontTarget(fontTarget,renderer);
  renderer.present()
  frames+=1 
  #ClearFont(fontTarget);

#destroy fontTarget
destroy renderer
destroy mainWindow
