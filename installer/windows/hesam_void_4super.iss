#define AppName "Hesam Void 4SUPER"
#define AppVersion "4.0.5"
#define AppPublisher "Hesam"
#define AppExeName "hesam_void.exe"
#define BuildOutput "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{6C8C03B1-07A8-47DC-A567-5C26A8B16AB4}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Hesam Void 4SUPER
DefaultGroupName={#AppName}
OutputDir=..\..\dist\windows
OutputBaseFilename=Hesam-Void-4SUPER-Windows-Setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildOutput}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
