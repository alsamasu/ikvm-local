# iKVM Local Launcher

Run ATEN Java iKVM viewer from JNLP files without Java Web Start security issues.

## Requirements

- Windows 10+
- Java 8 (JRE) - [Download](https://www.java.com/download/)

## Usage

1. Download a `launch.jnlp` from your IPMI/BMC web interface
2. Double-click `Run-iKVM.bat`
3. Select the JNLP file in the dialog
4. The iKVM viewer launches

## How it works

Java Web Start (javaws) was deprecated and has strict security requirements that block many IPMI KVM viewers. This launcher:

1. Parses the JNLP file to extract connection parameters
2. Downloads the packed JAR files directly from the IPMI
3. Unpacks them using `unpack200`
4. Extracts native DLLs
5. Launches the viewer with `javaw.exe`
