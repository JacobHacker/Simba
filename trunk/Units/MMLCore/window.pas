{
	This file is part of the Mufasa Macro Library (MML)
	Copyright (c) 2009 by Raymond van Venetië and Merlijn Wajer

    MML is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    MML is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with MML.  If not, see <http://www.gnu.org/licenses/>.

	See the file COPYING, included in this distribution,
	for details about the copyright.

    Window class for the Mufasa Macro Library
}

unit Window;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, mufasatypes,
  {$IFDEF MSWINDOWS}
  windows,  // For windows API
  {$ENDIF}
  graphics,
  LCLType,
  bitmaps,
  LCLIntf // for ReleaseDC and such

  {$IFDEF LINUX}, xlib, x, xutil{$ENDIF};

type

    {
       TMWindow Class handles all interaction with the Operating System Display
       Getting Window ID's, Window Bitmap Data, Window Size.

       It also abstracts data allocation from the user. Downside is there can't
       be more than one Data in memory.

       EG: One uses ReturnData, but must Free the data with FreeReturnData;
           If one calls ReturnData, one must first free the ReturnData, before
           calling ReturnData again.

    }

    TMWindow = class(TObject)
      function GetColor(x,y : integer) : TColor;
            function ReturnData(xs, ys, width, height: Integer): TRetData;
            procedure FreeReturnData;
            procedure GetDimensions(out W, H: Integer);
            function GetDimensionBox(out Box : TBox) : boolean;
            procedure ActivateClient;
            {$IFDEF LINUX}
            function SetTarget(XWindow: x.TWindow): integer; overload;
            {$ENDIF}

            {$IFDEF MSWINDOWS}
            function UpdateDrawBitmap:boolean;
            {$ENDIF}
            function SetTarget(Window: THandle; NewType: TTargetWindowMode): integer; overload;
            function SetTarget(ArrPtr: PRGB32; Size: TPoint): integer; overload;
            function SetTarget(Bitmap : TMufasaBitmap) : integer;overload;
            function TargetValid: Boolean;

            procedure SetWindow(Window: TMWindow);
            procedure SetDesktop;

            procedure OnTargetBitmapDestroy( Bitmap : TMufasaBitmap);
            {
              Freeze Client Feature.
              This will force the MWindow unit to Store the current Client's
              data in whatever internal structure it will use, and returndata /
              copyclienttobitmap will not renew this data until Unfreeze() is
              called.
            }

            function Freeze: boolean;
            function Unfreeze: boolean;

            constructor Create;
            destructor Destroy; override;

        private
          FreezeState: Boolean;
          FrozenData : PRGB32;
          FrozenSize : TPoint;
          TargetBitmap : TMufasaBitmap;
          {:Called before setting the NewTarget, deletes stuff related to OldTarget and sets the new targetmode}
          procedure OnSetTarget(NewTarget,OldTarget : TTargetWindowMode);
        public
              // Target Window Mode.
              TargetMode: TTargetWindowMode;


              {$IFDEF MSWINDOWS}
              //Target handle; HWND
              TargetHandle : Hwnd;
              DrawBmpDataPtr : PRGB32;
              DesktopHWND : Hwnd;
              DesktopDC : HDC;
              //Works on linux as well, test it out
              TargetDC : HDC;
              DrawBitmap : TBitmap;
              DrawBmpW,DrawBmpH : integer;
              {$ENDIF}

              {$IFDEF LINUX}
              // X Display
              XDisplay: PDisplay;

              // Connection Number
              XConnectionNumber: Integer;

              // X Window
              CurWindow: x.TWindow;

              // Desktop Window
              DesktopWindow: x.TWindow;

              // X Screen
              XScreen: PScreen;

              // X Screen Number
              XScreenNum: Integer;

              // The X Image pointer.
              XWindowImage: PXImage;

              // XImageFreed should be True if there is currently no
              // XImage loaded. If one is loaded, XImageFreed is true.

              // If ReturnData is called while XImageFreed is false,
              // we throw an exception.
              // Same for FreeReturnData with XImageFreed true.
              XImageFreed: Boolean;

              {$ELSE}

              {$ENDIF}

              ArrayPtr: PRGB32;
              ArraySize: TPoint;

              property Frozen: boolean read FreezeState;



    end;

implementation

uses
    windowutil, // For utilities such as XImageToRawImage
    GraphType // For TRawImage
    ;

constructor TMWindow.Create;
begin
  inherited Create;

  Self.FrozenData:= nil;
  Self.FrozenSize := Classes.Point(-1,-1);
  Self.FreezeState := False;

  Self.ArrayPtr := nil;
  Self.ArraySize := Classes.Point(-1, -1);

  Self.TargetBitmap := nil;

  {$IFDEF MSWINDOWS}
  Self.DrawBitmap := TBitmap.Create;
  Self.DrawBitmap.PixelFormat:= pf32bit;
  Self.TargetMode:= w_Window;
  Self.TargetHandle:= 0;
  Self.TargetDC := 0;
  Self.DesktopHWND:= GetDesktopWindow;
  Self.DesktopDC:= GetDC(0);
  Self.SetDesktop;
  Self.UpdateDrawBitmap;
  {$ENDIF}

  {$IFDEF LINUX}
  Self.XImageFreed:=True;
  Self.TargetMode := w_XWindow;

  Self.XDisplay := XOpenDisplay(nil);
  if Self.XDisplay = nil then
  begin
    // throw Exception
  end;
  Self.XConnectionNumber:= ConnectionNumber(Self.XDisplay);
  Self.XScreen := XDefaultScreenOfDisplay(Self.XDisplay);
  Self.XScreenNum:= DefaultScreen(Self.XDisplay);

  // The Root Window is the Desktop. :-)
  Self.DesktopWindow:= RootWindow(Self.XDisplay, Self.XScreenNum);
  Self.CurWindow:= Self.DesktopWindow;

  {$ENDIF}

end;

destructor TMWindow.Destroy;
begin
  if FreezeState then
    if FrozenData <> nil then
      FreeMem(FrozenData);

  FreeReturnData;  // checks if it is freed or not. if it is not freed, it frees.
  {$IFDEF LINUX}
  XCloseDisplay(Self.XDisplay);
  {$ENDIF}
  {$IFDEF MSWINDOWS}
  if TargetMode = w_Window then
    ReleaseDC(TargetHandle,TargetDC);
  DrawBitmap.Free;
  {$ENDIF}
  inherited;
end;


procedure TMWindow.OnSetTarget(NewTarget,OldTarget : TTargetWindowMode);
begin
  case OldTarget of
    w_Window: begin
                {$IFDEF WINDOWS}
                if not Self.TargetDC= Self.DesktopDC then
                  ReleaseDC(Self.TargetHandle,Self.TargetDC);
                {$ELSE}
                raise Exception.Create('Handle/DC not supported on Linux');
                {$ENDIF}
              end;
    w_XWindow: Self.FreeReturnData;
  end;
  //Set them to zero, just in case ;-).
  if NewTarget <> w_BMP then
    Self.TargetBitmap := nil;
  if NewTarget <> w_ArrayPtr then
    self.ArrayPtr := nil;
  Self.TargetMode:= NewTarget;
end;

procedure TMWindow.SetWindow(Window: TMWindow);
begin
  case Window.TargetMode of
    w_BMP :
      Self.SetTarget(Window.TargetBitmap);
    w_Window, w_HDC:
        {$IFDEF WINDOWS}
        Self.SetTarget(Window.TargetHandle, Window.TargetMode);
        {$ELSE}
         writeln('TMWindow.SetWindow - Handle not supported');
        {$ENDIF}

    // I don't think array can ever be set at this point.
    // Let's just add it anyway. ;)
    w_ArrayPtr:
        Self.SetTarget(Window.ArrayPtr, Window.ArraySize);

    w_XWindow:
        {$IFDEF LINUX}
        Self.SetTarget(Window.CurWindow);
        {$ELSE}
        writeln('TMWindow.SetWindow - XImage not supported');
        {$ENDIF}
  end;
end;

procedure TMWindow.SetDesktop;
begin
  {$IFDEF LINUX}
  Self.SetTarget(Self.DesktopWindow);
  {$ELSE}
  OnSetTarget(w_window, Self.TargetMode);
  Self.TargetDC:= DesktopDC;
  Self.TargetHandle:= DesktopHWND;
  UpdateDrawBitmap;
  {$ENDIF}
end;


function TMWindow.TargetValid: Boolean;
{$IFDEF LINUX}
var
  old_handler: TXErrorHandler;
  Attrib: TXWindowAttributes;
{$ENDIF}
begin
  case Self.TargetMode of
    w_BMP : result := TargetBitmap <> nil;
    w_Window :
      begin
        {$IFDEF WINDOWS}
          result := IsWindow(self.TargetHandle);
        {$ELSE}
          Raise Exception.Create('TargetValid: Linux and w_Window');
          result := False;
        {$ENDIF}
      end;
    w_ArrayPtr : result := ArrayPtr <> nil;
    w_HDC :
    begin
      {$IFDEF WINDOWS}
       result := Self.TargetDC <> 0;
      {$ELSE}
        Raise Exception.Create('TargetValid: Linux and w_HDC');
        result := False;
      {$ENDIF}
    end;
    w_XWindow : begin
               {$IFDEF LINUX}
                  old_handler := XSetErrorHandler(@MufasaXErrorHandler);
                  { There must be a better way to do this, at least with less overhead. }
                  if XGetWindowAttributes(Self.XDisplay, Self.CurWindow, @Attrib) = 0 then
                    result := false
                  else
                    result := true;
                  XSetErrorHandler(old_handler);
                  {$ENDIF}
                end;
  end;
end;

procedure TMWindow.OnTargetBitmapDestroy(Bitmap: TMufasaBitmap);
begin
  Self.SetDesktop;
  writeln('Our current bitmap is being freed! Defaulting to Desktop.');
 // raise Exception.CreateFmt('Our targetbitmap has been destroyed, what now?',[]);
end;

function TMWindow.GetColor(x, y: integer): TColor;
begin
  {$IFDEF WINDOWS}
  if Self.TargetMode = w_Window then
    Result := GetPixel(Self.TargetDC,x,y)
  else
  {$ENDIF}
  begin
    with ReturnData(x,y,1,1) do
      Result := RGBToColor(Ptr[0].r,Ptr[0].g,Ptr[0].b);
    FreeReturnData;
  end;
end;

function TMWindow.ReturnData(xs, ys, width, height: Integer): TRetData;
var
{$IFDEF LINUX}
   Old_Handler: TXErrorHandler;
{$ENDIF}
   TmpData: PRGB32;
   w,h : integer;
begin
  Self.GetDimensions(w,h);
  if (xs < 0) or (xs + width > w) or (ys < 0) or (ys + height > h) then
    raise Exception.CreateFMT('TMWindow.ReturnData: The parameters passed are wrong; xs,ys %d,%d width,height %d,%d',[xs,ys,width,height]);

  if Self.Frozen then
  begin;
    TmpData := Self.FrozenData;
    Result.RowLen:= Self.FrozenSize.x;
    Result.IncPtrWith:= Result.RowLen - width;
    Inc(TmpData, ys * Result.RowLen + xs);
    Result.Ptr:= tmpData;
  end else
  case Self.TargetMode of
    w_BMP :
      begin;
      // Copy the pointer as we will perform operations on it.
      TmpData := TargetBitmap.FData;

      // Increase the pointer to the specified start of the data.
      Result.RowLen:= TargetBitmap.Width;
      Result.IncPtrWith:= Result.RowLen - width;
      Inc(TmpData, ys * Result.RowLen + xs);
      Result.Ptr := TmpData;
      end;
    w_Window:
    begin
      {$IFDEF MSWINDOWS}
      BitBlt(Self.DrawBitmap.Canvas.Handle,0,0, width, height, Self.TargetDC, xs,ys, SRCCOPY);
      Result.Ptr:= Self.DrawBmpDataPtr;
      Result.IncPtrWith:= DrawBmpW - Width;
      Result.RowLen:= DrawBmpW;
      {$ENDIF}
    end;
    w_XWindow:
    begin
      {$IFDEF LINUX}
      if not Self.XImageFreed then
        Raise Exception.CreateFmt('ReturnData was called again without freeing'+
                                  ' the previously used data. Do not forget to'+
                                  ' call FreeReturnData', []);
      { Should be this. }
      Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);

      Self.XWindowImage := XGetImage(Self.XDisplay, Self.curWindow, xs, ys, width, height, AllPlanes, ZPixmap);
      if Self.XWindowImage = nil then
      begin
        Writeln('ReturnData: XGetImage Error. Dumping data now:');
        Writeln('xs, ys, width, height: ' + inttostr(xs) + ', '  + inttostr(ys) +
                ', ' + inttostr(width) + ', ' + inttostr(height));

        Result.Ptr := nil;
        Result.IncPtrWith := 0;

        XSetErrorHandler(Old_Handler);
        raise Exception.CreateFMT('TMWindow.ReturnData: ReturnData: XGetImage Error', []);
        Exit;
      end;
      //WriteLn(IntToStr(Self.XWindowImage^.width) + ', ' + IntToStr(Self.XWindowImage^.height));
      Result.Ptr := PRGB32(Self.XWindowImage^.data);
      Result.IncPtrWith := 0;
      Result.RowLen := width;
      Self.XImageFreed:=False;

      XSetErrorHandler(Old_Handler);
      {$ELSE}
      raise Exception.createFMT('ReturnData: You cannot use ' +
                                'the XImage mode on Windows.', []);
      {$ENDIF}
    end;
    w_ArrayPtr:
    begin
      // Copy the pointer as we will perform operations on it.
      TmpData := Self.ArrayPtr;

      // Increase the pointer to the specified start of the data.
      Result.RowLen:= Self.ArraySize.x;
      Result.IncPtrWith:= Result.RowLen - width;
      Inc(TmpData, ys * Result.RowLen + xs);
      Result.Ptr := TmpData;
    end;
  end;
end;

procedure TMWindow.FreeReturnData;
begin
  if (Self.TargetMode <> w_XWindow) or FreezeState then
    Exit;
  {$IFDEF LINUX}
  if not Self.XImageFreed then
  begin
    Self.XImageFreed:=True;
    if(Self.XWindowImage <> nil) then
    begin
      XDestroyImage(Self.XWindowImage);
    end;
  end;
  {$ENDIF}
end;

{
 This will draw the ENTIRE client to a bitmap.
 And ReturnData / CopyClientToBitmap will always use this bitmap.
 They must NEVER update, unless Unfreeze is called.

 I am not entirely sure how to do this, yet.
 Best option for now seems to copy the entire data to a PRGB32,
 and use it like the ArrPtr mode.

 I currently added "Frozen", "FreezeState", "Freeze" and "Unfreeze".
 We will have to either "abuse" the current system, and set the client to
 PtrArray mode, or edit in some extra variables.
 (We will still need extra variables to remember the old mode,
 to which we will switch back with Unfreeze.)

 Several ways to do it, what's the best way?

 Also, should a box be passed to Freeze, or should we just copy the entire
 client?
}
function TMWindow.Freeze: Boolean;
var
  w,h : integer;
  PtrReturn : TRetData;
begin
  if Self.FreezeState then
    raise Exception.CreateFMT('TMWindow.Freeze: The window is already frozen.',[]);
  Result := true;
  Self.GetDimensions(w,h);
  Self.FrozenSize := Classes.Point(w,h);
  PtrReturn := Self.ReturnData(0,0,w,h);
  GetMem(Self.FrozenData, w * h * sizeof(TRGB32));
  Move(PtrReturn.Ptr[0], FrozenData[0], w*h*sizeof(TRGB32));
  Self.FreeReturnData;
  Self.FreezeState:=True;
end;

function TMWindow.Unfreeze: Boolean;
begin
  if Self.FreezeState = false then
    raise Exception.CreateFMT('TMWindow.Unfreeze: The window is not frozen.',[]);
  FreeMem(Self.FrozenData);
  Self.FrozenData := nil;
  Self.FreezeState:=False;
  Result := True;
end;

// Set's input focus on Linux, does not mean the window will look `active', but
// it surely is. Try typing something after ActivateClient.
procedure TMWindow.ActivateClient;
{$IFDEF LINUX}
var
   Old_Handler: TXErrorHandler;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if TargetMode = w_Window then
    SetForegroundWindow(Self.TargetHandle);
  {$ENDIF}
  {$IFDEF LINUX}
  if TargetMode = w_XWindow then
  begin;
    Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);

    { TODO: Check if Window is valid? }
    XSetInputFocus(Self.XDisplay,Self.CurWindow,RevertToParent,CurrentTime);
    XFlush(Self.XDisplay);
    XSetErrorHandler(Old_Handler);
  end;
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
function TMWindow.UpdateDrawBitmap :boolean;
var
  w,h : integer;
  BmpInfo : Windows.TBitmap;
begin
  GetDimensions(w,h);
  DrawBitmap.SetSize(w,h);
//  DrawBitmap.PixelFormat:=
  DrawBmpW := w;
  DrawBmpH := h;
  GetObject(DrawBitmap.Handle, SizeOf(BmpInfo), @BmpInfo);
  DrawBmpDataPtr := BmpInfo.bmBits;
end;
{$ENDIF}

// Returns dimensions of the Window
procedure TMWindow.GetDimensions(out W, H: Integer);
{$IFDEF LINUX}
var
   Attrib: TXWindowAttributes;
   newx,newy : integer;
   childwindow : x.TWindow;
   Old_Handler: TXErrorHandler;
{$ENDIF}
{$IFDEF MSWINDOWS}
var
  Rect : TRect;
{$ENDIF}
begin
  if Frozen then
  begin;
    w := FrozenSize.x;
    h := FrozenSize.y;
  end else
  case TargetMode of
    w_BMP :
      begin
        w := TargetBitmap.Width;
        h := TargetBitmap.Height;
      end;
    w_Window:
    begin
      {$IFDEF MSWINDOWS}
      GetWindowRect(Self.TargetHandle, Rect);
      w:= Rect.Right - Rect.Left;
      h:= Rect.Bottom - Rect.Top;
      {$ENDIF}
    end;
    w_XWindow:
    begin
      {$IFDEF LINUX}
      Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);
      if XGetWindowAttributes(Self.XDisplay, Self.CurWindow, @Attrib) <> 0 Then
      begin
        { I don't think we need this XTranslateCoordinates... :D }
        XTranslateCoordinates(Self.XDisplay, Self.CurWindow, Self.DesktopWindow, 0,0, @newx, @newy, @childwindow);
        W := Attrib.Width;
        H := Attrib.Height;
      end else
      begin
        { TODO: Raise Exception because the Window does not exist? }
        W := -1;
        H := -1;
      end;
      XSetErrorHandler(Old_Handler);
      {$ELSE}
       raise Exception.createFMT('GetDimensions: You cannot use ' +
                                 'the XImage mode on Windows.', []);
      {$ENDIF}
    end;
    w_ArrayPtr:
    begin
      W := Self.ArraySize.X;
      H := Self.ArraySize.Y;
    end;
  end;
end;

function TMWindow.GetDimensionBox(out Box : TBox) : boolean;
function IntToTBox(x1,y1,x2,y2 : integer) : TBox;inline;
begin;
  result.x1 := x1;
  result.y1 := y1;
  result.x2 := x2;
  result.y2 := y2;
end;

{$IFDEF LINUX}
var
   Attrib: TXWindowAttributes;
   newx,newy : integer;
   childwindow : x.TWindow;
   Old_Handler: TXErrorHandler;
{$ENDIF}
{$IFDEF MSWINDOWS}
var
  Rect : TRect;
{$ENDIF}
begin
  result := false;
  case TargetMode of
    w_Window:
    begin
      {$IFDEF MSWINDOWS}
      result := true;
      GetWindowRect(Self.TargetHandle, Rect);
      box := IntToTBox(Rect.Left,Rect.top,Rect.Right - 1,Rect.Bottom - 1);
      {$ENDIF}
    end;
    w_XWindow:
    begin
      {$IFDEF LINUX}
      result := true;
      Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);
      if XGetWindowAttributes(Self.XDisplay, Self.CurWindow, @Attrib) <> 0 Then
      begin
        { I don't think we need this XTranslateCoordinates... :D }
        XTranslateCoordinates(Self.XDisplay, Self.CurWindow, Self.DesktopWindow, 0,0, @newx, @newy, @childwindow);
        box := IntToTBox(Attrib.x,Attrib.y,Attrib.x + Attrib.Width -1,Attrib.y +Attrib.Height-1 );
      end else
        box := IntToTBox(-1,-1,-1,-1);
      XSetErrorHandler(Old_Handler);
      {$ELSE}
       raise Exception.createFMT('GetDimensions: You cannot use ' +
                                 'the XImage mode on Windows.', []);
      {$ENDIF}
    end;
  end;
end;

// Set target to X-Window
{$IFDEF LINUX}
function TMWindow.SetTarget(XWindow: x.TWindow): integer; overload;
var
   Old_Handler: TXErrorHandler;
begin
  if Self.Frozen then
    raise Exception.CreateFMT('You cannot set a target when Frozen',[]);
  OnSetTarget(w_XWindow,Self.TargetMode);
  Self.CurWindow := XWindow;
end;
{$ENDIF}

// Set target to Windows Window
function TMWindow.SetTarget(Window: THandle; NewType: TTargetWindowMode): integer; overload;
begin
  if Self.Frozen then
    raise Exception.CreateFMT('You cannot set a target when Frozen',[]);
  if NewType in [ w_XWindow, w_ArrayPtr ] then
    raise Exception.createFMT('SetTarget: Invalid new type.', []);
  OnSetTarget(NewType,self.TargetMode);
  case NewType of
    w_HDC :
    begin
      {$ifdef MSWindows}
      Self.TargetDC:= Window;
      {$else}
      Raise Exception.Create('HDC not supported on linux (yet)');
      {$endif}
    end;
    w_Window :
    begin;
      {$IFDEF MSWINDOWS}
      //The old DC is free'd in OnSetTarget.
      Self.TargetHandle := Window;
      Self.TargetDC := GetWindowDC(Window);
      {$ENDIF}
    end;
  end;
  {$IFDEF MSWINDOWS}
  UpdateDrawBitmap;
  {$ENDIF}
end;

{
    This functionality is very BETA.
    We have no way to send events to a window, so we should probably use the
    desktop window?

    eg: In mouse/keys: if Self.TargetMode not in [w_Window, w_XWindow], send it
        to the desktop.
}
function TMWindow.SetTarget(ArrPtr: PRGB32; Size: TPoint): integer; overload;
begin
  if Self.Frozen then
    raise Exception.CreateFMT('You cannot set a target when Frozen',[]);
  Self.SetDesktop;//Set the underlaying window to desktop for key-sending etc..
  OnSetTarget(w_ArrayPtr,self.TargetMode);
  Self.ArrayPtr := ArrPtr;
  Self.ArraySize := Size;
end;

// Set target to Bitmap, set desktop for keyinput/output
function TMWindow.SetTarget(Bitmap: TMufasaBitmap): integer;
begin
  if Self.Frozen then
    raise Exception.CreateFMT('You cannot set a target when Frozen',[]);
  OnSetTarget(w_BMP,self.TargetMode);
  Self.SetDesktop;
  Self.TargetBitmap := Bitmap;
  Bitmap.OnDestroy:= @OnTargetBitmapDestroy;
end;

end.
