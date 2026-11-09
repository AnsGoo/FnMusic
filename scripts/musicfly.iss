; MusicFly（乐记）Windows 安装包定义。
; 由 scripts/package_windows.sh 调用 ISCC 编译，也可手动执行：
;   ISCC.exe /DAppVersion=1.0.0 /DSourceDir=... /DOutputDir=... scripts/musicfly.iss
;
; 安装到当前用户目录（{autopf} 在非管理员模式下解析为
; %LocalAppData%\Programs），未签名应用这样装不会弹 UAC。

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\flutter_app\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define AppName "乐记 MusicFly"
#define AppExeName "musicfly.exe"

[Setup]
AppId={{B7C1F0A2-3E4D-4F6B-9C21-7A5D8E2B4F31}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=MusicFly
VersionInfoVersion={#AppVersion}
VersionInfoCompany=MusicFly
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoDescription={#AppName} 安装程序
DefaultDirName={autopf}\MusicFly
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename=MusicFly-{#AppVersion}-windows-x64-setup
SetupIconFile=..\flutter_app\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
CloseApplications=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
#if FileExists(AddBackslash(SourcePath) + "inno\ChineseSimplified.isl")
Name: "zh"; MessagesFile: "inno\ChineseSimplified.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
