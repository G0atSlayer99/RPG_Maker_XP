@echo off
rem Builds AttributesEditor.exe with the C# compiler that ships with Windows (.NET Framework 4).
cd /d "%~dp0"
"%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x86 /optimize+ /out:AttributesEditor.exe /resource:Attributes.rb,Attributes.rb /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Core.dll src\*.cs
