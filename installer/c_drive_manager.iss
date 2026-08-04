; C 盘管家 Windows 安装脚本（Inno Setup 6）
; 由 tools/build_installer.ps1 调用 ISCC 编译。
; 安装后提供可见卸载入口：Uninstall.exe、开始菜单与安装目录内“卸载”快捷方式。

#define MyAppName "C 盘管家"
#define MyAppNameEn "CDriveManager"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "C 盘管家"
#define MyAppExeName "c_drive_manager.exe"

[Setup]
AppId={{8F3A9C2E-4B71-4D56-9E1A-C0D8B5A47213}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppNameEn}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename=CDriveManager-Setup-{#MyAppVersion}
SetupIconFile=..\apps\desktop_flutter\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Uninstallable=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
UninstallFilesDir={app}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} 安装程序
VersionInfoProductName={#MyAppName}
DisableProgramGroupPage=no
DisableWelcomePage=no
DisableDirPage=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"; Flags: unchecked

[Files]
Source: "..\apps\desktop_flutter\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "CDriveManager.exe"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"; Comment: "卸载 C 盘管家"
; 安装目录内也放一份卸载入口，方便在资源管理器中找到
Name: "{app}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"; Comment: "卸载 C 盘管家"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 清理安装时额外复制的友好卸载入口，以及中文路径兼容联接残留
Type: files; Name: "{app}\Uninstall.exe"
Type: files; Name: "{app}\Uninstall.dat"
Type: dirifempty; Name: "{app}"

[Code]
{ 复制一份 Uninstall.exe，名称更直观；需同步复制 .dat，否则卸载程序无法读取清单。 }
procedure CurStepChanged(CurStep: TSetupStep);
var
  UninsExe, UninsDat, DestExe, DestDat: string;
begin
  if CurStep = ssPostInstall then
  begin
    UninsExe := ExpandConstant('{uninstallexe}');
    UninsDat := ChangeFileExt(UninsExe, '.dat');
    DestExe := ExpandConstant('{app}\Uninstall.exe');
    DestDat := ExpandConstant('{app}\Uninstall.dat');
    if FileExists(UninsExe) and FileExists(UninsDat) then
    begin
      CopyFile(UninsExe, DestExe, False);
      CopyFile(UninsDat, DestDat, False);
    end;
  end;
end;
