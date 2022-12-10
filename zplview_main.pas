unit zplview_main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  StdCtrls, ComCtrls, Sockets, ssockets, fphttpclient, zplview_settings, dateutils,
  INIFiles, Printers, lazlogger;

type

  ArrayChar = array of char;

  { TForm1 }

  TForm1 = class(TForm)
    BRenderManual: TButton;
    Image1: TImage;
    MainMenu1: TMainMenu;
    MSourceCode: TMemo;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    AcceptTimer: TTimer;
    Panel1: TPanel;
    Panel2: TPanel;
    Shape1: TShape;
    StatusBar1: TStatusBar;
    procedure AcceptTimerTimer(Sender: TObject);
    procedure BRenderManualClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure Image1DragDrop(Sender, Source: TObject; X, Y: integer);
    procedure Image1DragOver(Sender, Source: TObject; X, Y: integer; State: TDragState; var Accept: boolean);
    procedure Image1Paint(Sender: TObject);
    procedure Image1StartDrag(Sender: TObject; var DragObject: TDragObject);
    procedure MenuItem2Click(Sender: TObject);
    procedure MenuItem3Click(Sender: TObject);
    procedure Panel2Click(Sender: TObject);
    procedure Shape1EndDrag(Sender, Target: TObject; X, Y: integer);
    procedure Shape1MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure Shape1MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure Shape1StartDrag(Sender: TObject; var DragObject: TDragObject);
    procedure StatusBar1Click(Sender: TObject);
  private
    socket: TINetServer;
    zpldata: Pointer;
    zpldatalen: longint;
    dragDir: integer;
    dragData: integer;
    rulers: array of integer;
    rulertypes: array of integer; // 0=Vertical, 1=horizonal
    RulersVisible: boolean;
    settings: ZViewSettings;
    inifile: string;
    procedure ReadJetData(Sender: TObject; DataStream: TSocketStream);
    procedure GetLabelaryData;
    procedure NothingHappened(Sender: TObject);
    procedure LoadSettings;
    procedure SaveSettings;
    procedure ResetSettings;
    function IniFileName(): string;
    function GetLANIp(): string;
    procedure RePrint;
    procedure SavePng;
    procedure SaveRaw(Data: string);

    procedure GetIPAddr(var buf: array of char; const len: longint);
  public

  end;

var
  Form1: TForm1;

implementation


{$R *.lfm}

{ TForm1 }

procedure TForm1.GetIPAddr(var buf: array of char; const len: longint);
const
  CN_GDNS_ADDR = '127.0.0.1';
  CN_GDNS_PORT = 53;
var
  s: string;
  sock: longint;
  err: longint;
  HostAddr: TSockAddr;
  l: integer;
  IPAddr: TInetSockAddr;

begin
  err := 0;
  Assert(len >= 16);

  sock := fpsocket(AF_INET, SOCK_DGRAM, 0);
  assert(sock <> -1);

  IPAddr.sin_family := AF_INET;
  IPAddr.sin_port := htons(CN_GDNS_PORT);
  IPAddr.sin_addr.s_addr := StrToHostAddr(CN_GDNS_ADDR).s_addr;

  if (fpConnect(sock, @IPAddr, SizeOf(IPAddr)) = 0) then
  begin
    try
      l := SizeOf(HostAddr);
      if (fpgetsockname(sock, @HostAddr, @l) = 0) then
      begin
        s := NetAddrToStr(HostAddr.sin_addr);
        StrPCopy(PChar(Buf), s);
      end
      else
      begin
        err := socketError;
      end;
    finally
      if (CloseSocket(sock) <> 0) then
      begin
        err := socketError;
      end;
    end;
  end
  else
  begin
    err := socketError;
  end;
end;

function TForm1.GetLANIp(): string;
var
  s: TInetSocket;

  buf: ArrayChar;
begin
  //try
  //  s := TInetSocket.Create('1.1.1.1',80);
  //  GetLANIp:=NetAddrToStr(s.LocalAddress.sin_addr);
  //finally
  //  s.Free;
  //end;

  SetLength(buf, 30);
  self.GetIPAddr(buf, 30);
  GetLANIp := Pchar(buf);
end;

function TForm1.IniFileName(): string;
var
  f, i, g_path: string;
begin
  i := ChangeFileExt(ExtractFileName(Application.ExeName), '.ini');
  //if GetEnvironmentVariable('APPDATA') <> '' then
  //  IniFileName := GetEnvironmentVariable('APPDATA') + '\' + i
  //else if GetEnvironmentVariable('HOME') <> '' then
  //  IniFileName := GetEnvironmentVariable('HOME') + '/.config/' + i
  //else
  //  IniFileName := i;

  g_path := ExtractFilePath(Application.ExeName);
  {$IFDEF DARWIN}
  g_path := LeftStr(g_path, Pos('myapp.app', g_path)-1);
  {$ENDIF}
  IniFileName := g_path + '/' + i;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  GetMem(zpldata, 1000000);        // 1MB 内存应该足够ZPL使用?!?
  FillChar(zpldata^, 1000000, 0);
  zpldatalen := 0;

  inifile := IniFileName();
  ResetSettings();
  LoadSettings();
  StatusBar1.Panels[3].Text := concat(GetLANIp(), ':', IntToStr(settings.tcpport));
  socket := TINetServer.Create(settings.bindadr, settings.tcpport);
  socket.ReuseAddress := True;
  socket.MaxConnections := 1;
  socket.OnConnect := @ReadJetData;
  socket.OnIdle := @NothingHappened;
  socket.Bind;
  socket.Listen;
  //socket.SetNonBlocking;
  socket.AcceptIdleTimeOut := 100;

  SetLength(rulers, 0);
  SetLength(rulertypes, 0);
  DragDir := -1;
  RulersVisible := True;
  Panel1.Width := 15;
end;

procedure TForm1.Image1DragDrop(Sender, Source: TObject; X, Y: integer);
var
  aspect: longint;
begin
  if ((Source = Shape1) and (DragDir > -1) and (Image1.Picture.Graphic <> nil)) then
  begin
    // Drop it like its hot...
    SetLength(rulers, Length(rulers) + 1);
    SetLength(rulertypes, Length(rulertypes) + 1);
    rulertypes[Length(rulertypes) - 1] := DragDir;
    aspect := DragData * Image1.Picture.Width div Image1.Width;
    rulers[Length(rulers) - 1] := aspect;
    DragDir := -1;
    StatusBar1.Panels[2].Text := '';
    Image1.Repaint;
  end;
end;

procedure TForm1.Image1DragOver(Sender, Source: TObject; X, Y: integer;
  State: TDragState; var Accept: boolean);
var
  pt: tPoint;
begin
  if (Source = Shape1) then
  begin
    Accept := True;
    RulersVisible := True;
    pt := ScreenToClient(Mouse.CursorPos);
    if DragDir = -1 then
    begin
      // now have FORM position
      if pt.x >= 15 then DragDir := 0;  // User wants to drag horizontally
      if pt.y >= 15 then DragDir := 1;  // User wants to drag vertically
    end;
    if DragDir = 0 then
    begin
      StatusBar1.Panels[2].Text := 'X = ' + IntToStr(pt.x);
      dragData := pt.x;
    end;

    if DragDir = 1 then
    begin
      StatusBar1.Panels[2].Text := 'Y = ' + IntToStr(pt.y);
      dragData := pt.y;
    end;
    Image1.Repaint;
  end;
end;

procedure TForm1.Image1Paint(Sender: TObject);
var
  n: integer;
  aspect: longint;
begin
  if RulersVisible and (Image1.Picture.Graphic <> nil) then
  begin
    if Length(rulertypes) > 0 then
    begin
      Image1.Canvas.Pen.Color := clGreen;
      for n := 0 to Length(rulertypes) - 1 do
      begin
        aspect := rulers[n] * Image1.Width div Image1.Picture.Width;
        if rulertypes[n] = 0 then
        begin
          Image1.Canvas.MoveTo(aspect, 0);
          Image1.Canvas.LineTo(aspect, Image1.Canvas.Height);
        end;
        if rulertypes[n] = 1 then
        begin
          Image1.Canvas.MoveTo(0, aspect);
          Image1.Canvas.LineTo(Image1.Canvas.Width, aspect);
        end;
      end;
    end;
    if DragDir > -1 then
    begin
      Image1.Canvas.Pen.Color := clRed;
      if DragDir = 0 then
      begin
        Image1.Canvas.MoveTo(DragData, 0);
        Image1.Canvas.LineTo(DragData, Image1.Canvas.Height);
      end;
      if DragDir = 1 then
      begin
        Image1.Canvas.MoveTo(0, DragData);
        Image1.Canvas.LineTo(Image1.Canvas.Width, DragData);
      end;
    end;
  end;
end;

procedure TForm1.Image1StartDrag(Sender: TObject; var DragObject: TDragObject);
begin
  //
end;

procedure TForm1.MenuItem2Click(Sender: TObject);
begin
  FormSettings.PutSettings(settings);
  if FormSettings.ShowModal = mrOk then
  begin
    FormSettings.GetSettings(settings);
    StatusBar1.Panels[1].Text := IntToStr(settings.rotation);
    StatusBar1.Panels[3].Text := GetLANIp() + ':' + IntToStr(settings.tcpport);
    SaveSettings;
    if zpldatalen > 0 then GetLabelaryData;
    if socket.Port <> settings.tcpport then
    begin
      socket.Free;
      socket := TINetServer.Create(settings.bindadr, settings.tcpport);
      socket.ReuseAddress := True;
      socket.MaxConnections := 1;
      socket.OnConnect := @ReadJetData;
      socket.OnIdle := @NothingHappened;
      socket.Bind;
      socket.Listen;
      socket.AcceptIdleTimeOut := 100;
    end;
  end;
end;

procedure TForm1.MenuItem3Click(Sender: TObject);
begin
  Form1.Close;
end;

procedure TForm1.Panel2Click(Sender: TObject);
begin
  if Panel1.Width < 50 then
  begin
    Form1.Width := Form1.Width + Form1.Width;
    Panel1.Width := Panel1.Width + (Form1.Width div 2);
  end
  else
  begin
    Form1.Width := Form1.Width div 2;
    Panel1.Width := 15;
  end;
end;

procedure TForm1.Shape1EndDrag(Sender, Target: TObject; X, Y: integer);
begin
  DragDir := -1;
  Image1.Repaint;
end;

procedure TForm1.Shape1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
begin
  if (Button = mbLeft) and (Image1.Picture.Graphic <> nil) then
  begin
    Shape1.BeginDrag(False);
    if not RulersVisible then
    begin
      RulersVisible := True;
      Image1.Repaint;
    end;
  end;
  if Button = mbRight then
  begin
    SetLength(rulers, 0);
    SetLength(rulertypes, 0);
    Image1.Repaint;
  end;
end;

procedure TForm1.Shape1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
begin
  if (Button = mbLeft) and (X < Shape1.Width) and (Y < Shape1.Height) then
  begin
    RulersVisible := False;
    Image1.Repaint;
    //StatusBar1.Panels[2].Text:= 'Tilt';
  end;
end;

procedure TForm1.Shape1StartDrag(Sender: TObject; var DragObject: TDragObject);
begin
  DragDir := -1;
  RulersVisible := True;
end;

procedure TForm1.StatusBar1Click(Sender: TObject);
begin
  with settings do
  begin
    rotation := rotation + 90;
    if rotation > 270 then rotation := 0;
    StatusBar1.Panels[1].Text := IntToStr(rotation);
  end;
  if zpldatalen > 0 then GetLabelaryData;
  //  Image1.Picture.Clear;
end;

procedure TForm1.AcceptTimerTimer(Sender: TObject);
begin
  socket.StartAccepting;
end;

procedure TForm1.BRenderManualClick(Sender: TObject);
begin
  if MSourceCode.Lines.Count > 3 then
  begin
    zpldatalen := MSourceCode.Lines.Text.Length;
    Move(MSourceCode.Lines.Text[1], zpldata^, zpldatalen);
    GetLabelaryData;
    ;
  end;
end;

procedure TForm1.NothingHappened(Sender: TObject);
begin
  socket.StopAccepting;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  socket.Free;
  FreeMem(zpldata, 1000000);
end;

procedure TForm1.SavePng;
var
  filename: string;
begin
  filename := settings.savepath;
  if filename <> '' then filename := filename + '/';
  filename := Format('%s%d.png', [SetDirSeparators(filename), DateTimeToUnix(now)]);
  Image1.Picture.SaveToFile(filename);
end;

procedure TForm1.SaveRaw(Data: string);
var
  File1: TextFile;
  filename: string;
begin
  filename := settings.savepath;
  if filename <> '' then filename := filename + '/';
  filename := Format('%srawdata.txt', [SetDirSeparators(filename)]);
  AssignFile(File1, filename);
  try
    Rewrite(File1);
    Writeln(File1, Data);
  finally
    CloseFile(File1);
  end;
end;

procedure TForm1.RePrint;
var
  p: integer;
  written: integer;
  //Data: string;
begin
  p := Printer.Printers.IndexOf(settings.printer);
  if p < 0 then
  begin
    ShowMessage('配置的打印机无效');
    exit;
  end;
  if zpldatalen = 0 then
  begin
    ShowMessage('没有可打印内容！');
    exit;
  end;
  Printer.PrinterIndex := p;
  if Printer.Printing then Printer.Abort;
  try
    Printer.Title := 'ZPL-View reprint';
    Printer.RawMode := settings.printraw;
    Printer.BeginDoc;
    if settings.printraw then
      Printer.Write(self.zpldata^, self.zpldatalen, written)
    else
      printer.Canvas.StretchDraw(Classes.Rect(0, 0,
        Image1.Picture.Graphic.Width * printer.XDPI div settings.resolution,
        Image1.Picture.Graphic.Height * printer.YDPI div settings.resolution),
        Image1.Picture.Graphic);
  finally
    Printer.EndDoc;
  end;

end;

procedure TForm1.GetLabelaryData;
var
  FPHTTPClient: TFPHTTPClient;
  Fmt, URL, dpi: string;
  FmtSet: TFormatSettings;
  PostData: TMemoryStream;
  PngData: TMemoryStream;
  //filename:string;
  errormsg: string;
begin
  FPHTTPClient := TFPHTTPClient.Create(nil);
  PostData := TMemoryStream.Create;
  PngData := TMemoryStream.Create;
  try
    FPHTTPClient.AllowRedirect := True;
    PostData.Write(zpldata^, zpldatalen);
    PostData.Position := 0;
    FPHTTPClient.RequestBody := PostData;
    FPHTTPClient.AddHeader('X-Rotation', IntToStr(settings.rotation));
    try
      case settings.resolution of
        152: dpi := '6dpmm';
        203: dpi := '8dpmm';
        300: dpi := '12dpmm';
        600: dpi := '24dpmm';
        else
          dpi := '8dpmm';
      end;
      FmtSet := DefaultFormatSettings;
      FmtSet.DecimalSeparator := '.';
      Fmt := 'http://api.labelary.com/v1/printers/%s/labels/%nx%n/0/';
      //URL:='http://api.labelary.com/v1/printers/8dpmm/labels/6x6/0/';
      URL := Format(Fmt, [dpi, settings.Width, settings.Height], FmtSet);
      FPHTTPClient.Post(URL, PngData);
      PngData.Position := 0;
      if FPHTTPClient.ResponseStatusCode = 200 then
      begin
        Image1.Picture.LoadFromStream(PngData);
        StatusBar1.Panels[0].Text := DateTimeToStr(Now);
        if settings.save then SavePng;
        if settings.print then RePrint;
      end
      else
      begin
        if PngData.Size < 100 then
        begin
          SetString(errormsg, pansichar(PngData.Memory), PngData.Size);
          ShowMessage('标签数据错误:' + errormsg);
        end
        else
          ShowMessage('标签数据错误:' + FPHTTPClient.ResponseStatusText);
      end;
    except
      on E: Exception do
        ShowMessage(E.Message);
    end;
  finally
    FreeAndNil(PostData);
    FreeAndNil(PngData);
    FreeAndNil(FPHTTPClient);
  end;

end;

procedure TForm1.ReadJetData(Sender: TObject; DataStream: TSocketStream);
var
  len: longint;
  db: string;
begin
  //WriteLn('Accepting client: ', HostAddrToStr(NetToHost(Data.RemoteAddress.sin_addr)));
  zpldatalen := 0;
  repeat
    len := DataStream.Read((zpldata + zpldatalen)^, 1000000 - zpldatalen);
    if len > 0 then zpldatalen := zpldatalen + len;
  until len <= 0;
  SetString(db, pansichar(zpldata), zpldatalen);
  DebugLn(DateTimeToStr(Now));
  DebugLn(db);
  DataStream.Free;
  if MSourceCode.Text = '' then MSourceCode.Text := db;
  if settings.saverawdata then SaveRaw(db);
  GetLabelaryData;
end;

procedure TForm1.LoadSettings;
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(inifile);
  with settings do
  begin
    resolution := INI.ReadInteger('SETTINGS', 'resolution', 203);
    rotation := INI.ReadInteger('SETTINGS', 'rotation', 0);
    Width := INI.ReadFloat('SETTINGS', 'width', 4.0);
    Height := INI.ReadFloat('SETTINGS', 'height', 3.0);
    save := INI.ReadBool('SETTINGS', 'save', False);
    savepath := INI.ReadString('SETTINGS', 'savepath', '');
    print := INI.ReadBool('SETTINGS', 'print', False);
    printraw := INI.ReadBool('SETTINGS', 'printraw', False);
    printer := INI.ReadString('SETTINGS', 'printer', '');
    executescript := INI.ReadBool('SETTINGS', 'executescript', False);
    saverawdata := INI.ReadBool('SETTINGS', 'saverawdata', False);
    scriptpath := INI.ReadString('SETTINGS', 'scriptpath', '');
    tcpport := INI.ReadInteger('SETTINGS', 'tcpport', 9100);
    ;
    bindadr := INI.ReadString('SETTINGS', 'bindadr', '0.0.0.0');
    ;
  end;
  INI.Free;
end;

procedure TForm1.SaveSettings;
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(inifile);
  with settings do
  begin
    INI.WriteInteger('SETTINGS', 'resolution', resolution);
    INI.WriteInteger('SETTINGS', 'rotation', rotation);
    INI.WriteFloat('SETTINGS', 'width', Width);
    INI.WriteFloat('SETTINGS', 'height', Height);
    INI.WriteBool('SETTINGS', 'save', save);
    INI.WriteString('SETTINGS', 'savepath', savepath);
    INI.WriteBool('SETTINGS', 'print', print);
    INI.WriteBool('SETTINGS', 'printraw', printraw);
    INI.WriteString('SETTINGS', 'printer', printer);
    INI.WriteBool('SETTINGS', 'executescript', executescript);
    INI.WriteBool('SETTINGS', 'saverawdata', saverawdata);
    INI.WriteString('SETTINGS', 'scriptpath', scriptpath);
    INI.WriteInteger('SETTINGS', 'tcpport', tcpport);
    ;
    INI.WriteString('SETTINGS', 'bindadr', bindadr);
    ;
  end;
  INI.Free;
end;

procedure TForm1.ResetSettings;
begin
  with settings do
  begin
    resolution := 203;
    rotation := 0;
    Width := 4.0;
    Height := 3.0;
    save := False;
    savepath := '';
    print := False;
    printraw := False;
    printer := '';
    executescript := False;
    saverawdata := False;
    scriptpath := '';
    tcpport := 9100;
    bindadr := '0.0.0.0';
  end;
end;

end.
