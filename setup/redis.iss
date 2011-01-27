; TODO grant the RedisService account full-permission to the data and logs
;      directories.
; TODO after uninstall, setup-helper.dll is left behind... figure out why its
;      not being automatically deleted.
; TODO show a blurb after the install to alert the user to create a dedicated
;      windows account to run redis, change the "data" directory permissions
;      and modify the service startup type to automatic (maybe this should be
;      done automatically?).
; TODO display a redis logo on the left of the setup dialog boxes.
; TODO create start menu entry for redis-cli.exe? for redis doc url too?
; TODO strip the binaries? its enough to build with make DEBUG=''
; TODO sign the setup?
;      NB: Unizeto Certum has free certificates to open-source authors.
;      See http://www.certum.eu/certum/cert,offer_software_publisher.xml
;      See https://developer.mozilla.org/en/Signing_a_XPI

#define AppVersion GetFileVersion(AddBackslash(SourcePath) + "..\src\redis-service.exe")

[Setup]
AppID={{B882ADC5-9DA9-4729-899A-F6728C146D40}
AppName=Redis
AppVersion={#AppVersion}
;AppVerName=Redis {#AppVersion}
AppPublisher=rgl
AppPublisherURL=https://github.com/rgl/redis
AppSupportURL=https://github.com/rgl/redis
AppUpdatesURL=https://github.com/rgl/redis
DefaultDirName={pf}\Redis
DefaultGroupName=Redis
LicenseFile=..\COPYING
InfoBeforeFile=..\README
OutputDir=.
OutputBaseFilename=redis-setup
SetupIconFile=redis.ico
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Dirs]
Name: "{app}\data";
Name: "{app}\logs";

[Files]
Source: "..\src\service-setup-helper.dll"; DestDir: "{app}"; DestName: "setup-helper.dll"
Source: "..\src\redis-benchmark.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\redis-check-aof.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\redis-check-dump.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\redis-cli.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\redis-server.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\redis-service.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\redis.conf"; DestDir: "{app}"; DestName: "redis-dist.conf"; BeforeInstall: BeforeInstallConf; AfterInstall: AfterInstallConf;
Source: "..\README"; DestDir: "{app}"; DestName: "README.txt"
Source: "..\COPYING"; DestDir: "{app}"; DestName: "COPYING.txt"

[Code]
#include "service.pas"
#include "service-account.pas"

const
  SERVICE_ACCOUNT_NAME = 'RedisService';
  SERVICE_ACCOUNT_DESCRIPTION = 'Redis Server Service';
  SERVICE_NAME = 'redis';
  SERVICE_DISPLAY_NAME = 'Redis Server';
  SERVICE_DESCRIPTION = 'Persistent key-value database';

const
  LM20_PWLEN = 14;

var
  ConfDistFilePath: string;
  ConfFilePath: string;
  ReplaceExistingConfFile: boolean;

function BoolToStr(B: boolean): string;
begin
  if B then Result := 'Yes' else Result := 'No';
end;

function ToForwardSlashes(S: string): string;
begin
  Result := S;
  StringChangeEx(Result, '\', '/', True);
end;

function GeneratePassword: string;
var
  N: integer;
begin
  for N := 1 to LM20_PWLEN do
  begin
    Result := Result + Chr(33 + Random(255 - 33));
  end;
end;

function InitializeSetup(): boolean;
begin
  if IsServiceRunning(SERVICE_NAME) then
  begin
    MsgBox('Please stop the ' + SERVICE_NAME + ' service before running this install', mbError, MB_OK);
    Result := false;
  end
  else
    Result := true
end;

function InitializeUninstall(): boolean;
begin
  if IsServiceRunning(SERVICE_NAME) then
  begin
    MsgBox('Please stop the ' + SERVICE_NAME + ' service before running this uninstall', mbError, MB_OK);
    Result := false;
  end
  else
    Result := true
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ServicePath: string;
  Password: string;
  Status: integer;
begin
  case CurStep of
    ssPostInstall:
      begin
        if ServiceAccountExists(SERVICE_ACCOUNT_NAME) <> 0 then
        begin
          Password := GeneratePassword;

          Status := CreateServiceAccount(SERVICE_ACCOUNT_NAME, Password, SERVICE_ACCOUNT_DESCRIPTION);

          if Status <> 0 then
          begin
            MsgBox('Failed to create service account for ' + SERVICE_ACCOUNT_NAME + ' (#' + IntToStr(Status) + ')' #13#13 'You need to create it manually.', mbError, MB_OK);
          end;
        end;

        if IsServiceInstalled(SERVICE_NAME) then
          Exit;

        ServicePath := ExpandConstant('{app}\redis-service.exe');

        if not InstallService(ServicePath, SERVICE_NAME, SERVICE_DISPLAY_NAME, SERVICE_DESCRIPTION, SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START, SERVICE_ACCOUNT_NAME, Password) then
        begin
          MsgBox('Failed to install the ' + SERVICE_NAME + ' service.' #13#13 'You need to install it manually.', mbError, MB_OK)
        end
      end
  end
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Status: integer;
begin
  case CurUninstallStep of
    usPostUninstall:
      begin
        if not RemoveService(SERVICE_NAME) then
        begin
          MsgBox('Failed to uninstall the ' + SERVICE_NAME + ' service.' #13#13 'You need to uninstall it manually.', mbError, MB_OK);
        end;

        Status := DestroyServiceAccount(SERVICE_ACCOUNT_NAME);

        if Status <> 0 then
        begin
          MsgBox('Failed to delete the service account for ' + SERVICE_ACCOUNT_NAME + ' (#' + IntToStr(Status) + ')' #13#13 'You need to delete it manually.', mbError, MB_OK);
        end;
      end
  end
end;

procedure BeforeInstallConf;
var
  ConfDistFileHash: string;
  ConfFileHash: string;
begin
  ConfFilePath := ExpandConstant('{app}\redis.conf');
  ConfDistFilePath := ExpandConstant('{app}\redis-dist.conf');

  if not FileExists(ConfFilePath) then
  begin
    ReplaceExistingConfFile := true;
    Exit;
  end;

  if not FileExists(ConfDistFilePath) then
  begin
    ReplaceExistingConfFile := false;
    Exit;
  end;

  ConfFileHash := GetSHA1OfFile(ConfFilePath);
  ConfDistFileHash := GetSHA1OfFile(ConfDistFilePath);
  ReplaceExistingConfFile := CompareStr(ConfFileHash, ConfDistFileHash) = 0;
end;

procedure AfterInstallConf;
var
  BasePath: string;
  ConfLines: TArrayOfString;
  N: integer;
  Line: string;
begin
  BasePath := RemoveBackslash(ExtractFileDir(ConfDistFilePath));

  if not LoadStringsFromFile(ConfDistFilePath, ConfLines) then
  begin
    MsgBox('Failed to load the ' + ConfDistFilePath + ' configuration file.' #13#13 'This program will not run correctly unless you manually edit the configuration file.', mbError, MB_OK);
    Abort;
  end;

  // NB we need to escape the backslashes in the string arguments on the redis
  //    configuration file. If we are using a file path, we can instead use
  //    forward slashes.

  for N := 0 to GetArrayLength(ConfLines)-1 do
  begin
    Line := Trim(ConfLines[N]);

    if Pos('#', Line) = 1 then
      Continue;

    if Pos('dir ', Line) = 1 then
    begin
      ConfLines[N] := ToForwardSlashes(Format('dir "%s\data"', [BasePath]));
      Continue;
    end;

    if Pos('logfile ', Line) = 1 then
    begin
      ConfLines[N] := ToForwardSlashes(Format('logfile "%s\logs\redis.log"', [BasePath]));
      Continue;
    end;
  end;

  if not SaveStringsToFile(ConfDistFilePath, ConfLines, false) then
  begin
    MsgBox('Failed to save the ' + ConfDistFilePath + ' configuration file.' #13#13 'This program will not run correctly unless you manually edit the configuration file.', mbError, MB_OK);
    Abort;
  end;

  if ReplaceExistingConfFile then
    FileCopy(ConfDistFilePath, ConfFilePath, false);
end;