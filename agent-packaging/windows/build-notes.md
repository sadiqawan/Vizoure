
# Vizoure NMS Windows Agent Build

## Requirements

- Windows 10/11 or Windows Server 2016+

- Visual Studio 2019+ with C++ workload

- WiX Toolset v3.11+ (https://wixtoolset.org)

- OpenSSL for Windows (optional, for encryption)

## Build Steps

1. Open Developer Command Prompt for Visual Studio

2. Navigate to zabbix-source directory

3. Run: cd build\win64

4. Run: build.bat Release agent

5. Binary output: bin\win64\zabbix_agentd.exe

6. Rename: copy bin\win64\zabbix_agentd.exe vizoure_agentd.exe

7. Run WiX installer build:

   cd ..\agent-packaging\windows

   candle installer.wxs

   light -out vizoure-agent.msi installer.wixobj

## Notes

- Change GUID in installer.wxs before first build

- Do NOT reuse Zabbix GUIDs — causes conflict on machines with real Zabbix installed

