# This module is a WORK IN PROGRESS!
Currently this module only handles computers where a BIOS password is not set.  
The `Get-LenovoBiosSettings` and `Set-LenovoBiosSettings` functions are otherwise functional.  

# Summary
A PowerShell wrapper for interfacing with modern Lenovo BIOSes via their WMI interfaces.  

Lenovo's full documentation for the WMI BIOS interface, which is actually quite good, is located here:
- Lenovo WMI BIOS Interface documentation: https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/
- Lenovo (ThinkPad) BIOS settings documentaiton: https://docs.lenovocdrt.com/ref/bios/settings/thinkpad/main/

# Usage
1. Download `LenovoWmiBiosInterfaceWrapper.psm1` to the appropriate subdirectory of your PowerShell [modules directory](https://github.com/engrit-illinois/how-to-install-a-custom-powershell-module).
2. Run the desired functions using the documentation below.


# Examples
Get all BIOS settings from a given computer:
```powershell
Get-LenovoBiosSettings -ComputerName "comp-name-01"
```

Set one or more BIOS settings on a given computer:
```powershell
Set-LenovoBiosSetting -ComputerName "comp-name-01" -SettingValuePairs "WakeOnLAN,ACandBattery","WakeUponAlarm,Disable"
```

# Functions

## Get-LenovoBiosSettings
Gets all BIOS settings from a given computer and returns them in an array of custom PowerShell objects, which each have the following properties:
- Name: The name of a particular setting.
- Value: The value to which the particular setting is currently set.
- PossibleValues: The possible valid values to which the particular setting can be set. This information is provided by the BIOS itself, and so exposed here for convenience.

For convenience, BIOS password status information (which is provided by the Lenovo WMI interfaces separately from the BIOS settings themselves) are merged into the array as objects with a bespoke name, prefixed with the string `_Pass_`.  

### Parameters

#### -ComputerName [string]
Mandatory string.  
The name of the computer from which to gather BIOS settings.  

#### -OperationTimeoutSec [int]
Optional integer.  
The number of seconds to wait for a response from CIM comands before timing out.  
Default is `10`.  

#### -CimSession [CimSession]
Optional CimSession object.  
The CimSession to use when performing various CIM commands.  
Intended for internal use between the module's functions.  

## Set-LenovoBiosSetting
Sets a given set of BIOS settings on a given computer.  

### Parameters

#### -ComputerName [string]
Required string.  
The name of the computer on which to set BIOS settings.  
As far as I can tell, the Lenovo WMI BIOS interface does not throw errors when a set operation fails for any reason, so this function performs a check afterward to verify whether the setting was actually changed.  
It will detect and warn about any settings which ended up unchanged for whatever reason, and will also warn if a setting value was given which doesn't appear to be valid, based on the possible valid settings reported by the BIOS.  

#### -SettingValuePairs [string[]]
Mandatory string array.  
An array of one or more strings, formatted as comma-separated setting-value pairs to set on the target computer.  
E.g. `"WakeOnLAN,ACandBattery","WakeUponAlarm,Disable"` or `@("WakeOnLAN,ACandBattery","WakeUponAlarm,Disable")`.  

#### -Force
Optional switch.  
By default, if the function detects that a given setting on the target computer is already configured to the given value, it will skip attempting to set that setting.  
When `-Force` is specified, it will set it regardless.  
Not sure why you would need this, but provided in case it's useful for some reason.  

#### -SupervisorPassword [string]
NOT YET IMPLEMENTED.

#### -OperationTimeoutSec [int]
Optional integer.  
The number of seconds to wait for a response from CIM comands before timing out.  
Default is `10`.  

#### -CimSession [CimSession]
Optional CimSession object.  
The CimSession to use when performing various CIM commands.  
Intended for internal use between the module's functions.  

## Set-LenovoBiosPassword
NOT YET IMPLEMENTED.
Note: per the [documentation](), the BIOS password cannot be intially set via WMI; only changed or removed.  

### Parameters

#### -ComputerName [string]
WIP

# Notes
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.