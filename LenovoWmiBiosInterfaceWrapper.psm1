# Logging function
function log {
	param(
		[string]$Msg,
		[int]$L = 0,
		[string]$Indent = "    ",
		[string]$FC,
		[switch]$S,
		[switch]$W,
		[switch]$E
	)
	
	for($i = 0; $i -lt $L; $i += 1) {
		$Msg = "$($Indent)$Msg"
	}
	
	$ts = Get-Date -Format "HH:mm:ss"
	$Msg = "[$ts] $Msg"
	
	$params = @{
		Object = $Msg
	}
	if($S) { $params.ForegroundColor = "green" }
	if($W) { $params.ForegroundColor = "yellow" }
	if($E) { $params.ForegroundColor = "red" }
	if($FC) { $params.ForegroundColor = $FC }
	
	Write-Host @params
}

# Create and use a CimSession instead of many individual CIM connections for various CIM commands. Should hopefully be a little more efficient.
function Get-CimSessionObject {
	[CmdletBinding()]
	
	param(
		[Parameter(Mandatory=$true)]
		[string]$ComputerName,
		[int]$OperationTimeoutSec = 10
	)
	$cimSessionOptions = New-CimSessionOption -Impersonation "Impersonate"
	log "Creating CimSession object..."
	New-CimSession -ComputerName $ComputerName -SessionOption $cimSessionOptions -OperationTimeoutSec $OperationTimeoutSec | Tee-Object -Variable "object" | Out-Host
	if(-not $object) {
		throw "Could not create CimSession to computer `"$ComputerName`"!"
	}
	$object
}

function Get-LenovoBiosSettings {
	[CmdletBinding()]
	
	param(
		[Parameter(ParameterSetName="Get-LenovoBiosSettings", Mandatory=$true)]
		[string]$ComputerName,
		[Parameter(ParameterSetName="Get-LenovoBiosSettings")]
		[int]$OperationTimeoutSec = 10,
		[Parameter(ParameterSetName="Set-LenovoBiosSettings", Mandatory=$true)]
		[CimSession]$CimSession
	)
	
	$namespace = "root/wmi"
	
	# Get CimSession object
	if(-not $CimSession) {
		$CimSession = Get-CimSessionObject -ComputerName $ComputerName -OperationTimeoutSec $OperationTimeoutSec
	}
	
	# Create object to store data
	$settings = [PSCustomObject]@{
		_ComputerName = $ComputerName
	}
	
	# Get password state
	# https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/#detecting-password-state
	$passSettings = Get-CimInstance -CimSession $CimSession -Namespace $namespace -Class "Lenovo_BiosPasswordSettings"
	$settings | Add-Member -NotePropertyName "PassSettings" -NotePropertyValue $passSettings
	
	# Build simplified array of password settings
	$simplifiedPassSettings = $passSettings.PSObject.Properties | Sort "Name" | ForEach-Object {
		$prop = $_
		$propName = $prop.Name
		if($propName -notin "Active","CimClass","CimInstanceProperties","CimSystemProperties","InstanceName","PSComputerName","PSShowComputerName") {
			$newPropName = "_Pass_$($prop.Name)"
			[PSCustomObject]@{
				Name = $newPropName
				Value = $prop.Value
			}
		}
	}
	$settings | Add-Member -NotePropertyName "SimplifiedPassSettings" -NotePropertyValue $simplifiedPassSettings
	
	# Get all BIOS settings
	# https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/#get-all-current-bios-settings
	$biosSettings = Get-CimInstance -CimSession $CimSession -Namespace $namespace -Class "Lenovo_BiosSetting"
	$settings | Add-Member -NotePropertyName "BiosSettings" -NotePropertyValue $biosSettings
	
	# Build simplified array of BIOS settings
	$simplifiedBiosSettings = $biosSettings | ForEach-Object {
		$setting = $_.CurrentSetting
		if(($setting) -and ($setting -ne "")) {
			$settingParts = $setting.Split(",")
			[PSCustomObject]@{
				Name = $settingParts[0]
				Value = $settingParts[1]
			}
		}
	}
	$settings | Add-Member -NotePropertyName "SimplifiedBiosSettings" -NotePropertyValue $simplifiedBiosSettings
	
	# Build overall array of simplified settings
	$settings | Add-Member -NotePropertyName "SimplifiedSettings" -NotePropertyValue (@($simplifiedPassSettings) + @($simplifiedBiosSettings))
	
	# Get possible values for each setting
	$allSelections = Get-CimInstance -CimSession $CimSession -Namespace $namespace -Class "Lenovo_GetBiosSelections"
	$settings.SimplifiedSettings | ForEach-Object {
		# https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/#typical-usage
		# BIOS settings and values are case sensitive.
		$selections = $allSelections | Invoke-CimMethod -MethodName "GetBiosSelections" -Arguments @{ Item = $_.Name } | Select -ExpandProperty "Selections"
		$_ | Add-Member -NotePropertyName "PossibleValues" -NotePropertyValue $selections
	}
	
	# Output simplified settings
	$settings.SimplifiedSettings | Sort "Name"
}

function Set-LenovoBiosSetting {
	# https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/#set-and-save-a-bios-setting-on-newer-models
	# BIOS settings and values are case sensitive.
	# After making changes to the BIOS settings, you must reboot the computer before the changes will take effect.
	[CmdletBinding()]
	
	param(
		[Parameter(Mandatory=$true)]
		[string]$ComputerName,
		[Parameter(ParameterSetName="PairsFromArray",Mandatory=$true)]
		[string[]]$SettingValuePairs,
		[Parameter(ParameterSetName="PairsFromCsv",Mandatory=$true)]
		[string]$SettingValuePairsCsv,
		[string]$SupervisorPassword,
		[int]$OperationTimeoutSec = 10,
		[CimSession]$CimSession,
		[switch]$Force
	)
	
	function Set-Settings {
		# Get a set settings instance
		log "Getting Lenovo_SetBiosSetting CimInstance..."
		Get-CimInstance -CimSession $CimSession -Namespace $namespace -Class "Lenovo_SetBiosSetting" | Tee-Object -Variable "set" | Out-Host
		
		# Record current settings for later verification of the change, and then make the desired change
		log "Invoking SetBiosSetting CimMethod for given -SettingValuePairs..."
		$SettingValuePairs | ForEach-Object {
			log "Given SettingValuePair: `"$_`"..." -L 1
			
			$pairString = $_
			$pairArray = $_.Split(",")
			$setting = $pairArray[0]
			$value = $pairArray[1]
			
			$oldObject = $old | Where { $_.Name -eq $setting }
			$oldValue = $oldObject.Value
			log "Old value: `"$oldValue`"" -L 2
			log "Given value: `"$value`"" -L 2
			$possibleValuesString = $oldObject.PossibleValues
			log "Possible values: `"$possibleValuesString`"" -L 2
			
			# Since we can, warn user about likely invalid values/typos
			$possibleValues = $possibleValuesString.Split(",")
			if($value -notin $possibleValues) {
				log "Given value is not recognized as one of the possible values! Setting this value should fail!" -L 2 -E
			}
			
			# Evaluate current state and -Force intention
			$setValue = $true
			if($oldValue -ne $value) {
				log "Current value is not already equal to given value." -L 2
			}
			else {
				log "Current value already equals given `"$value`"." -L 2 -W
				if(-not $Force) {
					log "-Force parameter was not specified. Skipping setting this value." -L 3
					$setValue = $false
				}
				else {
					log "-Force parameter was specified. Setting this value anyway..." -L 3
				}
			}
			
			# Perform the set operation
			if($setValue) {
				log "Invoking SetBiosSetting CimMethod to set `"$_`"..." -L 1
				# Note: this operation will still return a success regardless of whether the value was actually changed.
				# I.e. even if you specify the same value that the setting is already configured to, or specify an invalid value.
				$set | Invoke-CimMethod -MethodName "SetBiosSetting" -Arguments @{ parameter = $_ } | Out-Host
			}
		}
	}
	
	function Save-Settings {
		# Save the new setting
		log "Getting LenovoSaveBiosSettings CimInstance..."
		Get-CimInstance -CimSession $CimSession -Namespace $namespace -Class "Lenovo_SaveBiosSettings" | Tee-Object -Variable "save" | Out-Host
		log "Invoking SaveBiosSettings CimMethod..."
		$save | Invoke-CimMethod -MethodName "SaveBiosSettings" | Out-Host
	}
	
	function Specify-SupervisorPassword {
		<# Currently no passwords set
		# Specify the supervisor password
		# Not sure if this is necessary if we securely authenticate via the CimSession in the first place
		$opcodeInterface = Get-CimInstance -CimSession $CimSession -Namespace $namespace -Class "Lenovo_WmiOpcodeInterface"
		$opcodeInterface | Invoke-CimMethod -MethodName "WmiOpcodeInterface" -Arguments @{ Parameter = "WmiOpcodePasswordAdmin:$($SupervisorPassword);"}
		#>
	}
	
	function Check-Settings {
		# Check that the new settings took effect
		log "Checking whether changes were successful..."
		$SettingValuePairs | ForEach-Object {
			log "Given SettingValuePair: `"$_`"..." -L 1
			
			$pairString = $_
			$pairArray = $_.Split(",")
			$setting = $pairArray[0]
			$value = $pairArray[1]
			
			$oldObject = $old | Where { $_.Name -eq $setting }
			$oldValue = $oldObject.Value
			log "Old value: `"$oldValue`"" -L 2
			log "Given value: `"$value`"" -L 2
			$newObject = $new | Where { $_.Name -eq $setting }
			$newValue = $newObject.Value
			log "New value: `"$newValue`"" -L 2
			$possibleValuesString = $newObject.PossibleValues
			log "Possible values: `"$possibleValuesString`"" -L 2
			
			# Evaluate the difference between old, given, and new values
			if($newValue -ne $value) {
				log "New value does not equal given value! So setting was not successful!" -L 2 -E
			}
			else {
				log "New value equals given value." -L 2
				if($oldValue -ne $value) {
					log "Old value was not already qual to given value. So setting was successful." -L 2 -S
				}
				else {
					log "Old value was already equal to given value." -L 2
					if($Force) {
						log "And -Force was specified, so it was forcefully set again anyway, and setting was successful." -L 3 -S
					}
					else {
						log "But -Force wasn't specified, so no attempt was made to set it again." -L 3
					}
				}
			}
		}
	}
	
	$namespace = "root/wmi"
	
	# Import setting-value pairs from CSV
	if($SettingValuePairsCsv) {
		log "-SettingValuePairsCsv was specified. Getting setting-value pairs from specified file and using that for the value of -SettingValuePairs..."
		$SettingValuePairs = Get-Content -Path $SettingValuePairsCsv
	}
	
	# Get CimSession object
	if(-not $CimSession) {
		$CimSession = Get-CimSessionObject -ComputerName $ComputerName -OperationTimeoutSec $OperationTimeoutSec
	}
	
	# Get current BIOS settings so we can compare before and after to verify if the change worked
	log "Getting current BIOS settings..."
	$old = Get-LenovoBiosSettings -CimSession $CimSession
	
	Set-Settings
	Specify-SupervisorPassword
	Save-Settings
	
	log "Getting current BIOS settings..."
	$new = Get-LenovoBiosSettings -CimSession $CimSession
		
	Check-Settings
	
	log "EOF"
}

Export-ModuleMember "Get-LenovoBiosSettings","Set-LenovoBiosSetting"